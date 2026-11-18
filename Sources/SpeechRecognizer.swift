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
    private var restartWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.voiceshot.speechQueue")
    
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
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    self.recognitionRequest?.append(buffer)
                    
                    if let channelData = buffer.floatChannelData?[0] {
                        let frameLength = UInt(buffer.frameLength)
                        var sum: Float = 0
                        for i in 0..<Int(frameLength) {
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
            return
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        settleWorkItem?.cancel()
        settleWorkItem = nil
        commandStream = CommandStream()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        
        currentState = .listening
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
            self?.queue.async { [weak self, weak request] in
                guard let self = self, let request = request, self.recognitionRequest === request else { return }

                if let result = result {
                    let transcription = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.onTranscriptChanged?(transcription)
                    }
                    self.processTranscription(transcription, isFinal: result.isFinal)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.handleSessionEnded()
                }
            }
        }
    }

    private func handleSessionEnded() {
        guard isIntentionallyListening else { return }
        
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isIntentionallyListening else { return }
            self.startRecognitionTask()
        }
        restartWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    // MARK: - Voice Command Parsing

    typealias Command = (target: CaptureTarget, delay: Double, trigger: String)

    private static let wordToNumber: [String: Int] = [
        "1": 1, "one": 1,
        "2": 2, "two": 2,
        "3": 3, "three": 3,
        "4": 4, "four": 4,
        "5": 5, "five": 5,
        "6": 6, "six": 6,
        "7": 7, "seven": 7,
        "8": 8, "eight": 8,
        "9": 9, "nine": 9,
        "10": 10, "ten": 10
    ]

    private static func words(in spoken: String) -> [String] {
        spoken.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .flatMap { word -> [String] in
                // Give compact and spaced transcriptions the same positions in the stream.
                if word.hasPrefix("snap"), let number = wordToNumber[String(word.dropFirst(4))] {
                    return ["snap", String(number)]
                }
                return [String(word)]
            }
    }

    static func parseTarget(spoken: String) -> Command? {
        parseTarget(words: words(in: spoken)[...])
    }

    private static func parseTarget(words: ArraySlice<String>) -> Command? {
        // Check countdown: "in 3 seconds", "in 5 sec"
        var delaySeconds: Double = 0.0
        for i in words.indices {
            if words[i] == "in" && i + 1 < words.endIndex {
                if let num = wordToNumber[words[i + 1]] {
                    if i + 2 < words.endIndex && (words[i + 2].hasPrefix("sec")) {
                        delaySeconds = Double(num)
                    } else if i + 1 == words.endIndex - 1 {
                        delaySeconds = Double(num)
                    }
                }
            }
        }
        
        let joined = words.joined(separator: " ")
        
        // 0. Show Window Numbers / Badges
        let badgeTriggers = ["show numbers", "show window numbers", "show windows", "number windows"]
        for bt in badgeTriggers {
            if joined.contains(bt) {
                return (.showWindowNumbers, 0.0, bt)
            }
        }
        
        if joined == "numbers" { return (.showWindowNumbers, 0.0, "numbers") }

        // 1. OCR Text Extraction ("screenshot text", "copy text", "extract text")
        let ocrTriggers = ["screenshot text", "copy text", "extract text", "read text", "read screen", "snap text"]
        for ocr in ocrTriggers {
            if joined.contains(ocr) {
                return (.extractText, delaySeconds, ocr)
            }
        }
        
        // 2. Interactive Selection Area ("screenshot area", "crop screenshot", "snap area")
        let areaTriggers = ["screenshot area", "screenshot selection", "crop screenshot", "select area", "crop screen", "snap area"]
        for area in areaTriggers {
            if joined.contains(area) {
                return (.interactiveArea, delaySeconds, area)
            }
        }
        
        // 3. Explicit "display N" / "screen N"
        for i in words.indices {
            if (words[i] == "display" || words[i] == "screen") && i + 1 < words.endIndex {
                if let num = wordToNumber[words[i + 1]] {
                    return (.display(num), delaySeconds, "\(words[i]) \(words[i + 1])")
                }
            }
        }
        
        // Numbered windows, including compact snaps after tokenization.
        for i in words.indices {
            let word = words[i]
            let isPrefix = word == "snap" || word == "screenshot" || word == "window"
                || (word == "shot" && i > words.startIndex && words[i - 1] == "screen")
            guard isPrefix, i + 1 < words.endIndex else { continue }
            let hasWindowPrefix = (word == "snap" || word == "screenshot") && words[i + 1] == "window"
            let numberIndex = hasWindowPrefix ? i + 2 : i + 1
            guard numberIndex < words.endIndex, let number = wordToNumber[words[numberIndex]] else { continue }
            return (.window(number), delaySeconds, "snap\(number)")
        }

        // 6. Named Application window: "snap <app>" or "screenshot <app>"
        let knownApps = [
            "safari", "chrome", "slack", "terminal", "code", "cursor",
            "discord", "finder", "notes", "mail", "messages", "music",
            "spotify", "xcode", "preview", "pages", "numbers", "keynote",
            "telegram", "zoom", "notion", "figma", "arc", "firefox"
        ]
        for app in knownApps {
            if joined.contains("snap \(app)") || joined.contains("screenshot \(app)") || joined.contains("take screenshot \(app)") || joined.contains("capture \(app)") {
                return (.app(app), delaySeconds, "snap \(app)")
            }
        }
        
        // 7. General triggers without numbers (All Displays)
        let generalTriggers = PreferencesManager.shared.triggerPhrases.map {
            $0.lowercased()
                .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        for trigger in generalTriggers where !trigger.isEmpty {
            if trigger != "snap", " \(joined) ".contains(" \(trigger) ") {
                return (.allDisplays, delaySeconds, trigger)
            }
        }
        
        if words.last == "snap" || joined == "snap please" || (joined.hasPrefix("snap in ") && delaySeconds > 0) {
            return (.allDisplays, delaySeconds, "snap")
        }

        return nil
    }
    
    // MARK: - Stream Processing

    struct CommandStream {
        private var processedWordCount = 0

        mutating func commands(in transcript: String, settled: Bool) -> [Command] {
            let words = SpeechRecognizer.words(in: transcript)
            guard processedWordCount < words.count else { return [] }

            var commands: [Command] = []
            var start = processedWordCount
            for index in words.indices.dropFirst(start) where words[index] == "snap" && index > start {
                if let command = SpeechRecognizer.parseTarget(words: words[start..<index]) {
                    commands.append(command)
                }
                start = index
            }
            processedWordCount = start
            if settled, let command = SpeechRecognizer.parseTarget(words: words[start...]) {
                commands.append(command)
                processedWordCount = words.count
            }
            return commands
        }
    }

    private func processTranscription(_ text: String, isFinal: Bool) {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        emit(commandStream.commands(in: text, settled: isFinal))
        guard !isFinal else { return }

        // Give a partial phrase time to acquire a number or a countdown.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.emit(self.commandStream.commands(in: text, settled: true))
        }
        settleWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func emit(_ commands: [Command]) {
        for command in commands {
            DispatchQueue.main.async { [weak self] in
                self?.onTriggerDetected?(command.target, command.delay, command.trigger)
            }
        }
    }
}
