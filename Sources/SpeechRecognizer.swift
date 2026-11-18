import AVFoundation
import Foundation
import Speech

enum SpeechState: Equatable {
    case idle
    case listening
    case paused
    case requestingPermission
    case permissionDenied(String)
    case error(String)
}

final class SpeechRecognizer: NSObject, SFSpeechRecognizerDelegate {
    static let shared = SpeechRecognizer()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private(set) var currentState: SpeechState = .idle {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onStatusChanged?(self.currentState)
            }
        }
    }
    
    var onTranscriptChanged: ((String) -> Void)?
    var onAudioLevelChanged: ((Float) -> Void)?
    /// Parameters: (CaptureTarget, DelayInSeconds, TriggerPhrase)
    var onTriggerDetected: ((CaptureTarget, Double, String) -> Void)?
    var onStatusChanged: ((SpeechState) -> Void)?
    
    private var isIntentionallyListening = false
    private var commandStream = CommandStream()
    private var settleWorkItem: DispatchWorkItem?
    private var lastPartialTranscript: String?
    private var restartWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.voiceshot.speechQueue", qos: .userInitiated)
    
    private override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    // MARK: - Permissions
    
    func checkPermissions(completion: @escaping (Bool, String?) -> Void) {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        
        switch speechStatus {
        case .authorized:
            checkMicrophonePermission(completion: completion)
        case .notDetermined:
            currentState = .requestingPermission
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self?.checkMicrophonePermission(completion: completion)
                    } else {
                        let msg = "Speech Recognition permission was denied. Please enable it in System Settings > Privacy & Security > Speech Recognition."
                        self?.currentState = .permissionDenied(msg)
                        completion(false, msg)
                    }
                }
            }
        case .denied, .restricted:
            let msg = "Speech Recognition is disabled. Please enable it in System Settings > Privacy & Security > Speech Recognition."
            currentState = .permissionDenied(msg)
            completion(false, msg)
        @unknown default:
            let msg = "Unknown speech authorization status."
            currentState = .error(msg)
            completion(false, msg)
        }
    }
    
    private func checkMicrophonePermission(completion: @escaping (Bool, String?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true, nil)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        completion(true, nil)
                    } else {
                        let msg = "Microphone access was denied. Please allow microphone access in System Settings > Privacy & Security > Microphone."
                        self?.currentState = .permissionDenied(msg)
                        completion(false, msg)
                    }
                }
            }
        case .denied, .restricted:
            let msg = "Microphone access is denied. Please allow microphone access in System Settings > Privacy & Security > Microphone."
            currentState = .permissionDenied(msg)
            completion(false, msg)
        @unknown default:
            completion(false, "Unknown microphone authorization status.")
        }
    }
    
    // MARK: - Listening Lifecycle
    
    func startListening() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionallyListening = true
            
            DispatchQueue.main.async {
                self.checkPermissions { [weak self] granted, errorMsg in
                    guard let self = self else { return }
                    if granted {
                        self.queue.async {
                            self.startAudioPipeline()
                        }
                    } else {
                        self.isIntentionallyListening = false
                        if let errorMsg = errorMsg {
                            self.currentState = .permissionDenied(errorMsg)
                        }
                    }
                }
            }
        }
    }
    
    func stopListening() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionallyListening = false
            self.restartWorkItem?.cancel()
            self.restartWorkItem = nil
            self.settleWorkItem?.cancel()
            self.settleWorkItem = nil
            
            self.recognitionRequest?.endAudio()
            self.recognitionRequest = nil
            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
            }
            self.currentState = .paused
        }
    }
    
    func toggleListening() {
        if isIntentionallyListening {
            stopListening()
        } else {
            startListening()
        }
    }
    
    // MARK: - Audio Pipeline & Continuous Recognition
    
    private func startAudioPipeline() {
        guard isIntentionallyListening else { return }
        
        do {
            if !audioEngine.isRunning {
                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                
                inputNode.removeTap(onBus: 0)
                var lastMeterTime: TimeInterval = 0
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    self.recognitionRequest?.append(buffer)
                    
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastMeterTime >= 0.05, buffer.frameLength > 0, let channelData = buffer.floatChannelData?[0] {
                        lastMeterTime = now
                        let frameLength = Int(buffer.frameLength)
                        var sum: Float = 0
                        for i in 0..<frameLength {
                            let sample = channelData[i]
                            sum += sample * sample
                        }
                        let rms = sqrt(sum / Float(frameLength))
                        let clamped = min(max(rms * 5.0, 0.0), 1.0)
                        DispatchQueue.main.async {
                            self.onAudioLevelChanged?(clamped)
                        }
                    }
                }
                audioEngine.prepare()
                try audioEngine.start()
            }
            
            startRecognitionTask()
        } catch {
            currentState = .error("Audio Engine error: \(error.localizedDescription)")
            handleSessionEnded()
        }
    }
    
    private func startRecognitionTask() {
        guard isIntentionallyListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            currentState = .error("Speech Recognizer is unavailable.")
            handleSessionEnded(retryAfter: 1)
            return
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        settleWorkItem?.cancel()
        settleWorkItem = nil
        let triggerPhrases = PreferencesManager.shared.triggerPhrases
        commandStream = CommandStream(triggerPhrases: triggerPhrases)
        lastPartialTranscript = nil
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) { request.addsPunctuation = true }
        request.contextualStrings = VoiceCommandDictionary.recognitionHints(triggerPhrases: triggerPhrases)
        self.recognitionRequest = request
        
        currentState = .listening
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
            self?.queue.async { [weak self, weak request] in
                guard let self = self, let request = request, self.recognitionRequest === request else { return }

                if let result {
                    let transcription = result.bestTranscription.formattedString
                    let commandText = Self.separateUtterances(result.bestTranscription)
                    if commandText != self.lastPartialTranscript {
                        DispatchQueue.main.async { self.onTranscriptChanged?(transcription) }
                    }
                    let segments = result.bestTranscription.segments
                    if let first = segments.first, let last = segments.last,
                       self.commandStream.beginFreshBadgeUtterance(commandText, start: first.timestamp,
                                                                   end: last.timestamp + last.duration) {
                        self.lastPartialTranscript = nil
                    }
                    self.processTranscription(commandText, isFinal: result.isFinal)
                }
                if error != nil {
                    self.settleWorkItem?.cancel()
                    self.emit(self.commandStream.flush())
                    self.handleSessionEnded(retryAfter: 0.3)
                } else if result?.isFinal == true {
                    self.startRecognitionTask()
                }
            }
        }
    }

    // Speech can accumulate unrelated speech and the next command without punctuation.
    private static func separateUtterances(_ transcription: SFTranscription) -> String {
        let text = transcription.formattedString
        let segments = transcription.segments
        var pauses: [Int] = []
        for (previous, next) in zip(segments, segments.dropFirst()) {
            if previous.duration > 0, next.timestamp - previous.timestamp - previous.duration >= 0.8 {
                pauses.append(next.substringRange.location)
            }
        }
        guard !pauses.isEmpty else { return text }
        let separated = NSMutableString(string: text)
        for offset in pauses.reversed() where offset < separated.length {
            separated.insert(".", at: offset)
        }
        return separated as String
    }

    private func handleSessionEnded(retryAfter: TimeInterval = 0.3) {
        guard isIntentionallyListening else { return }
        
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isIntentionallyListening else { return }
            self.startAudioPipeline()
        }
        restartWorkItem = workItem
        queue.asyncAfter(deadline: .now() + retryAfter, execute: workItem)
    }
    
    // MARK: - Voice Command Processing

    typealias Command = VoiceCommandDictionary.Command

    static func parseTarget(spoken: String, triggerPhrases: [String] = PreferencesManager.shared.triggerPhrases) -> Command? {
        VoiceCommandDictionary(triggerPhrases: triggerPhrases).match(VoiceCommandDictionary.words(in: spoken)[...])
    }

    struct CommandStream {
        private let dictionary: VoiceCommandDictionary
        private var processedWordCount = 0
        private var pending: Command?
        private var pendingWordCount = 0
        private var lastAudioEnd: TimeInterval?

        // Speech may replace a previous utterance with identical text covering new audio.
        mutating func beginFreshBadgeUtterance(_ text: String, start: TimeInterval, end: TimeInterval) -> Bool {
            guard end > start else { return false }
            let previousEnd = lastAudioEnd
            lastAudioEnd = max(lastAudioEnd ?? end, end)
            guard let previousEnd, start >= previousEnd,
                  dictionary.match(VoiceCommandDictionary.words(in: text)[...])?.target == .showWindowNumbers else {
                return false
            }
            processedWordCount = 0
            pending = nil
            return true
        }

        init(triggerPhrases: [String] = PreferencesManager.shared.triggerPhrases) {
            dictionary = VoiceCommandDictionary(triggerPhrases: triggerPhrases)
        }

        var settleInterval: TimeInterval? {
            pending.map { $0.target == .allDisplays ? 0.25 : 0.10 }
        }

        mutating func commands(in transcript: String, settled: Bool, badgesActive: Bool = false) -> [Command] {
            pending = nil
            let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            var words: [String] = []
            var boundaries: [Int] = []
            for (index, sentence) in sentences.enumerated() {
                let phrase = VoiceCommandDictionary.words(in: sentence)
                guard !phrase.isEmpty else { continue }
                words.append(contentsOf: phrase)
                if index < sentences.count - 1 { boundaries.append(words.count) }
            }
            guard processedWordCount < words.count else { return [] }

            var commands: [Command] = []
            var selectingBadge = badgesActive
            var start = processedWordCount
            var remainingBoundaries = boundaries.drop(while: { $0 <= start })
            while start < words.count {
                let phraseEnd = remainingBoundaries.first ?? words.count
                let phrase = words[start..<phraseEnd]
                if let command = dictionary.match(phrase) ?? (selectingBadge ? VoiceCommandDictionary.badgeSelection(phrase) : nil) {
                    pending = command
                    pendingWordCount = phraseEnd
                    if settled || phraseEnd < words.count || command.target == .showWindowNumbers ||
                        (command.delay > 0 && VoiceCommandDictionary.endsWithSeconds(phrase.last)) {
                        if command.target == .showWindowNumbers { selectingBadge = true }
                        commands.append(contentsOf: flush())
                        start = phraseEnd
                        if remainingBoundaries.first == phraseEnd { remainingBoundaries = remainingBoundaries.dropFirst() }
                        continue
                    }
                    break
                }

                // A following command establishes the previous command's boundary.
                let badgeAfterChatter = dictionary.badgeCommandAfterChatter(phrase)
                let end = min(phraseEnd - 1, start + dictionary.maxWordCount + 6)
                var next: (Int, Command)?
                if end > start {
                    for boundary in (start + 1...end).reversed() {
                        let word = words[boundary]
                        let explicitSeparator = words[boundary - 1] == "then" || words[boundary - 1] == "and"
                        guard let command = dictionary.match(words[start..<boundary]) ??
                                (selectingBadge ? VoiceCommandDictionary.badgeSelection(words[start..<boundary]) : nil) else { continue }
                        let badgeFollowsChatter = badgeAfterChatter.map { $0 >= boundary } == true
                        let numberedSnap = words[start] == "snap" && command.trigger.hasPrefix("snap") &&
                            Int(command.trigger.dropFirst(4)) != nil
                        let canSkipToBadge = badgeFollowsChatter && (command.target == .showWindowNumbers || numberedSnap)
                        guard canSkipToBadge || explicitSeparator || dictionary.canStartCommand(word) || VoiceCommandDictionary.badgeSelection(words[boundary..<phraseEnd]) != nil,
                              (dictionary.hasCommandPrefix(words[boundary..<phraseEnd]) ||
                               (command.target == .showWindowNumbers && VoiceCommandDictionary.badgeSelection(words[boundary..<phraseEnd]) != nil) ||
                               canSkipToBadge) else { continue }
                        if command.target == .allDisplays, ["window", "screen", "display"].contains(word),
                           !explicitSeparator { continue }
                        next = (boundary, command)
                        break
                    }
                }
                if let (boundary, command) = next {
                    if command.target == .showWindowNumbers { selectingBadge = true }
                    commands.append(command)
                    start = boundary
                    processedWordCount = boundary
                } else if let commandStart = [dictionary.numberCommandAfterChatter(phrase), badgeAfterChatter].compactMap({ $0 }).min() {
                    start = commandStart
                } else if remainingBoundaries.first != nil {
                    start = phraseEnd
                    processedWordCount = phraseEnd
                    remainingBoundaries = remainingBoundaries.dropFirst()
                } else {
                    break
                }
            }
            return commands
        }

        mutating func flush() -> [Command] {
            guard let command = pending else { return [] }
            pending = nil
            processedWordCount = pendingWordCount
            return [command]
        }
    }

    private func processTranscription(_ text: String, isFinal: Bool) {
        guard isFinal || text != lastPartialTranscript else { return }
        lastPartialTranscript = text
        settleWorkItem?.cancel()
        settleWorkItem = nil
        let badgesActive = DispatchQueue.main.sync { WindowManager.shared.hasBadgeTargets }
        emit(commandStream.commands(in: text, settled: isFinal, badgesActive: badgesActive))
        guard let interval = commandStream.settleInterval else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.emit(self.commandStream.flush())
        }
        settleWorkItem = workItem
        queue.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    private func emit(_ commands: [Command]) {
        for command in commands {
            DispatchQueue.main.async { [weak self] in
                self?.onTriggerDetected?(command.target, command.delay, command.trigger)
            }
        }
    }
}
