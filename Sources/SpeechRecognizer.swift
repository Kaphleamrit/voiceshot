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
    private var processedLength: Int = 0
    private var lastTriggerTime: Date = Date.distantPast
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
        
        processedLength = 0
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        
        currentState = .listening
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.onTranscriptChanged?(transcription)
                }
                self.processTranscription(transcription)
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.handleSessionEnded()
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
    
    // MARK: - Advanced Multi-Feature Target Parser
    
    static func parseTarget(spoken: String) -> (matched: Bool, target: CaptureTarget, delay: Double, trigger: String)? {
        let lower = spoken.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        let words = lower.split(separator: " ").map { String($0) }
        
        let wordToNumber: [String: Int] = [
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
        
        // Check countdown: "in 3 seconds", "in 5 sec"
        var delaySeconds: Double = 0.0
        for i in 0..<words.count {
            if words[i] == "in" && i + 1 < words.count {
                if let num = wordToNumber[words[i + 1]] {
                    if i + 2 < words.count && (words[i+2].hasPrefix("sec")) {
                        delaySeconds = Double(num)
                    } else if i + 1 == words.count - 1 {
                        delaySeconds = Double(num)
                    }
                }
            }
        }
        
        let joined = words.joined(separator: " ")
        
        // 0. Show Window Numbers / Badges
        let badgeTriggers = ["show numbers", "show window numbers", "show windows", "number windows", "numbers"]
        for bt in badgeTriggers {
            if joined.contains(bt) {
                return (true, .showWindowNumbers, 0.0, bt)
            }
        }
        
        // 1. OCR Text Extraction ("screenshot text", "copy text", "extract text")
        let ocrTriggers = ["screenshot text", "copy text", "extract text", "read text", "read screen"]
        for ocr in ocrTriggers {
            if joined.contains(ocr) {
                return (true, .extractText, delaySeconds, ocr)
            }
        }
        
        // 2. Interactive Selection Area ("screenshot area", "crop screenshot")
        let areaTriggers = ["screenshot area", "screenshot selection", "crop screenshot", "select area", "crop screen"]
        for area in areaTriggers {
            if joined.contains(area) {
                return (true, .interactiveArea, delaySeconds, area)
            }
        }
        
        // 3. Explicit "display N" / "screen N"
        for i in 0..<words.count {
            if (words[i] == "display" || words[i] == "screen") && i + 1 < words.count {
                if let num = wordToNumber[words[i + 1]] {
                    return (true, .display(num), delaySeconds, "\(words[i]) \(words[i+1])")
                }
            }
        }
        
        // 4. Compact window tokens: "ss1", "ss2", "ss3", "ss4", "ss5", "s1", "s2"
        for word in words {
            if word.hasPrefix("ss") && word.count > 2 {
                let numStr = String(word.dropFirst(2))
                if let num = wordToNumber[numStr], num >= 1 && num <= 10 {
                    return (true, .window(num), delaySeconds, word)
                }
            } else if word.hasPrefix("s") && word.count > 1 {
                let numStr = String(word.dropFirst(1))
                if let num = wordToNumber[numStr], num >= 1 && num <= 10 {
                    return (true, .window(num), delaySeconds, word)
                }
            }
        }
        
        // 5. Multi-word: "ss 1", "ss 2", "screenshot 1", "screenshot 2", "window 1", "window 2"
        for i in 0..<words.count {
            let w = words[i]
            let isPrefix = (w == "ss" || w == "screenshot" || w == "window" || (w == "shot" && i > 0 && words[i-1] == "screen"))
            if isPrefix && i + 1 < words.count {
                if let num = wordToNumber[words[i + 1]], num >= 1 && num <= 10 {
                    return (true, .window(num), delaySeconds, "\(words[i]) \(words[i+1])")
                }
            }
        }
        
        // 6. Named Application window: "screenshot <app>"
        let knownApps = [
            "safari", "chrome", "slack", "terminal", "code", "cursor",
            "discord", "finder", "notes", "mail", "messages", "music",
            "spotify", "xcode", "preview", "pages", "numbers", "keynote",
            "telegram", "zoom", "notion", "figma", "arc", "firefox"
        ]
        for app in knownApps {
            if joined.contains("screenshot \(app)") || joined.contains("take screenshot \(app)") || joined.contains("capture \(app)") {
                return (true, .app(app), delaySeconds, "screenshot \(app)")
            }
        }
        
        // 7. General triggers without numbers (All Displays)
        let generalTriggers = PreferencesManager.shared.triggerPhrases.map {
            $0.lowercased()
                .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        for trigger in generalTriggers where !trigger.isEmpty {
            if joined.contains(trigger) {
                return (true, .allDisplays, delaySeconds, trigger)
            }
        }
        
        return nil
    }
    
    // MARK: - Stream Processing
    
    private func processTranscription(_ fullText: String) {
        if fullText.count < processedLength {
            processedLength = 0
        }
        
        let startIndex = fullText.index(fullText.startIndex, offsetBy: processedLength, limitedBy: fullText.endIndex) ?? fullText.startIndex
        let pendingText = String(fullText[startIndex...])
        
        if let match = SpeechRecognizer.parseTarget(spoken: pendingText) {
            let now = Date()
            if now.timeIntervalSince(lastTriggerTime) > 0.85 {
                lastTriggerTime = now
                processedLength = fullText.count
                
                DispatchQueue.main.async { [weak self] in
                    self?.onTriggerDetected?(match.target, match.delay, match.trigger)
                }
            }
        }
    }
}
