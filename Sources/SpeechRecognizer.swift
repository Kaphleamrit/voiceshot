import AVFoundation
import Foundation
import Speech

enum SpeechState: Equatable {
    case idle
    case listening
    case onBreak
    case paused
    case requestingPermission
    case permissionDenied(String)
    case error(String)
}

final class SpeechRecognizer: NSObject, SFSpeechRecognizerDelegate {
    static let shared = SpeechRecognizer()
    private static let inactivityInterval: TimeInterval = 15 * 60
    private static let wakePhrase = "wake up"

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private(set) var currentState: SpeechState = .idle

    private func updateState(_ state: SpeechState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentState != state else { return }
            self.currentState = state
            self.onStatusChanged?(state)
        }
    }
    
    var onTranscriptChanged: ((String) -> Void)?
    var onAudioLevelChanged: ((Float) -> Void)?
    /// Parameters: (CaptureTarget, DelayInSeconds, TriggerPhrase)
    var onTriggerDetected: ((CaptureTarget, Double, String) -> Void)?
    var onStatusChanged: ((SpeechState) -> Void)?
    
    private var isIntentionallyListening = false
    private var isOnBreak = false
    private var permissionRequestID: UUID?
    private var inactivityWorkItem: DispatchWorkItem?
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
    
    private func checkPermissions(completion: @escaping (Bool, String?) -> Void) {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        
        switch speechStatus {
        case .authorized:
            checkMicrophonePermission(completion: completion)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self?.checkMicrophonePermission(completion: completion)
                    } else {
                        let msg = "Speech Recognition permission was denied. Please enable it in System Settings > Privacy & Security > Speech Recognition."
                        completion(false, msg)
                    }
                }
            }
        case .denied, .restricted:
            let msg = "Speech Recognition is disabled. Please enable it in System Settings > Privacy & Security > Speech Recognition."
            completion(false, msg)
        @unknown default:
            let msg = "Unknown speech authorization status."
            completion(false, msg)
        }
    }
    
    private func checkMicrophonePermission(completion: @escaping (Bool, String?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true, nil)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        completion(true, nil)
                    } else {
                        let msg = "Microphone access was denied. Please allow microphone access in System Settings > Privacy & Security > Microphone."
                        completion(false, msg)
                    }
                }
            }
        case .denied, .restricted:
            let msg = "Microphone access is denied. Please allow microphone access in System Settings > Privacy & Security > Microphone."
            completion(false, msg)
        @unknown default:
            completion(false, "Unknown microphone authorization status.")
        }
    }
    
    // MARK: - Listening Lifecycle
    
    func startListening() {
        queue.async { [weak self] in self?.startListeningOnQueue() }
    }

    private func startListeningOnQueue() {
        guard !isIntentionallyListening else { return }
        isIntentionallyListening = true
        let requestID = UUID()
        permissionRequestID = requestID
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined ||
            AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            updateState(.requestingPermission)
        }
        DispatchQueue.main.async { [weak self] in
            self?.checkPermissions { [weak self] granted, errorMsg in
                self?.queue.async { [weak self] in
                    guard let self, self.permissionRequestID == requestID else { return }
                    self.permissionRequestID = nil
                    guard granted else {
                        self.isIntentionallyListening = false
                        self.updateState(.permissionDenied(errorMsg ?? "Listening permission is required."))
                        return
                    }
                    self.startAudioPipeline()
                    self.resetInactivityTimer()
                }
            }
        }
    }

    func stopListening() {
        queue.async { [weak self] in self?.stopListeningOnQueue() }
    }

    private func stopListeningOnQueue() {
        isIntentionallyListening = false
        isOnBreak = false
        permissionRequestID = nil
        inactivityWorkItem?.cancel()
        inactivityWorkItem = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil
        settleWorkItem?.cancel()
        settleWorkItem = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        updateState(.paused)
    }

    func toggleListening() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isOnBreak {
                self.resumeFromBreak()
            } else if self.isIntentionallyListening {
                self.stopListeningOnQueue()
            } else {
                self.startListeningOnQueue()
            }
        }
    }

    func setAutomaticListeningBreaks(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            PreferencesManager.shared.automaticListeningBreaks = enabled
            if self.isOnBreak && !enabled {
                self.resumeFromBreak()
            } else {
                self.resetInactivityTimer()
            }
        }
    }

    private func resetInactivityTimer() {
        inactivityWorkItem?.cancel()
        inactivityWorkItem = nil
        guard isIntentionallyListening, permissionRequestID == nil, !isOnBreak,
              PreferencesManager.shared.automaticListeningBreaks else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.inactivityWorkItem = nil
            self.isOnBreak = true
            self.startAudioPipeline()
        }
        inactivityWorkItem = workItem
        queue.asyncAfter(deadline: .now() + Self.inactivityInterval, execute: workItem)
    }

    private func resumeFromBreak() {
        isOnBreak = false
        startAudioPipeline()
        resetInactivityTimer()
    }

    // MARK: - Audio Pipeline & Continuous Recognition
    
    private func startAudioPipeline() {
        guard isIntentionallyListening else { return }
        restartWorkItem?.cancel()
        restartWorkItem = nil

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
                            guard self.currentState == .listening else { return }
                            self.onAudioLevelChanged?(clamped)
                        }
                    }
                }
                audioEngine.prepare()
                try audioEngine.start()
            }
            
            startRecognitionTask()
        } catch {
            updateState(.error("Audio Engine error: \(error.localizedDescription)"))
            handleSessionEnded()
        }
    }
    
    private func startRecognitionTask() {
        guard isIntentionallyListening else { return }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        settleWorkItem?.cancel()
        settleWorkItem = nil

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            updateState(.error("Speech Recognizer is unavailable."))
            handleSessionEnded(retryAfter: 1)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) { request.addsPunctuation = true }
        if isOnBreak {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.contextualStrings = [Self.wakePhrase]
        } else {
            let triggerPhrases = PreferencesManager.shared.triggerPhrases
            commandStream = CommandStream(triggerPhrases: triggerPhrases)
            lastPartialTranscript = nil
            request.contextualStrings = VoiceCommandDictionary.recognitionHints(triggerPhrases: triggerPhrases)
        }
        self.recognitionRequest = request
        
        updateState(isOnBreak ? .onBreak : .listening)
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
            self?.queue.async { [weak self, weak request] in
                guard let self = self, let request = request, self.recognitionRequest === request else { return }

                if self.isOnBreak {
                    if let result, Self.containsWakePhrase(Self.separateUtterances(result.bestTranscription)) {
                        self.resumeFromBreak()
                    } else if error != nil {
                        self.handleSessionEnded(retryAfter: 0.3)
                    } else if result?.isFinal == true {
                        self.startRecognitionTask()
                    }
                    return
                }

                if let result {
                    let transcription = result.bestTranscription.formattedString
                    let commandText = Self.separateUtterances(result.bestTranscription)
                    if commandText != self.lastPartialTranscript {
                        DispatchQueue.main.async { self.onTranscriptChanged?(transcription) }
                    }
                    let segments = result.bestTranscription.segments
                    if let first = segments.first, let last = segments.last,
                       self.commandStream.beginFreshUtterance(commandText, start: first.timestamp,
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

    static func containsWakePhrase(_ text: String) -> Bool {
        let wakeWords = VoiceCommandDictionary.words(in: wakePhrase)
        return text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).contains {
            VoiceCommandDictionary.words(in: $0) == wakeWords
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
        mutating func beginFreshUtterance(_ text: String, start: TimeInterval, end: TimeInterval) -> Bool {
            guard end > start else { return false }
            let previousEnd = lastAudioEnd
            lastAudioEnd = max(lastAudioEnd ?? end, end)
            guard let previousEnd, start >= previousEnd,
                  let target = dictionary.match(VoiceCommandDictionary.words(in: text)[...])?.target,
                  target == .showWindowNumbers || target == .paste else {
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
            guard let pending else { return nil }
            switch pending.target {
            case .allDisplays: return 0.25
            case .paste: return 0.45
            case .extractText: return 0.65
            default: return 0.10
            }
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
                        if !explicitSeparator,
                           command.target == .paste || VoiceCommandDictionary.pasteSoundAlikes.contains(word) {
                            continue
                        }
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
        guard !commands.isEmpty else { return }
        resetInactivityTimer()
        for command in commands {
            DispatchQueue.main.async { [weak self] in
                self?.onTriggerDetected?(command.target, command.delay, command.trigger)
            }
        }
    }
}
