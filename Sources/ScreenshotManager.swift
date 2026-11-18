import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import UserNotifications
import Vision

enum CaptureTarget: Equatable, CustomStringConvertible {
    case allDisplays
    case display(Int)
    case window(Int)
    case app(String)
    case interactiveArea
    case extractText
    case showWindowNumbers
    
    var description: String {
        switch self {
        case .allDisplays: return "All Displays"
        case .display(let n): return "Display \(n)"
        case .window(let n): return "Window \(n)"
        case .app(let name): return "\(name.capitalized)"
        case .interactiveArea: return "Selection Area"
        case .extractText: return "Extract Text (OCR)"
        case .showWindowNumbers: return "Show Window Numbers"
        }
    }
}

final class ScreenshotManager {
    static let shared = ScreenshotManager()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private init() {
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    /// Speaks voice feedback confirmation if enabled
    func speakFeedback(_ message: String) {
        guard PreferencesManager.shared.spokenFeedback else { return }
        DispatchQueue.main.async { [weak self] in
            let utterance = AVSpeechUtterance(string: message)
            utterance.rate = 0.52
            self?.speechSynthesizer.speak(utterance)
        }
    }
    
    /// Flashes all connected screens briefly with a smooth white fade
    func flashScreens() {
        DispatchQueue.main.async {
            for screen in NSScreen.screens {
                let window = NSWindow(contentRect: screen.frame,
                                      styleMask: .borderless,
                                      backing: .buffered,
                                      defer: false)
                window.isOpaque = false
                window.backgroundColor = NSColor.white.withAlphaComponent(0.65)
                window.level = .floating
                window.ignoresMouseEvents = true
                window.orderFrontRegardless()
                
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 0.0
                }, completionHandler: {
                    window.orderOut(nil)
                })
            }
        }
    }
    
    /// Resolves an accessible, writable folder for saving screenshots
    func resolveOutputFolder() -> String {
        let prefs = PreferencesManager.shared
        var candidate = (prefs.saveFolderPath as NSString).expandingTildeInPath
        if candidate.isEmpty {
            candidate = ("~/Desktop" as NSString).expandingTildeInPath
        }
        
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        
        do {
            try FileManager.default.createDirectory(atPath: candidate, withIntermediateDirectories: true, attributes: nil)
            return candidate
        } catch {
            let pictures = ("~/Pictures/Screenshots" as NSString).expandingTildeInPath
            if (try? FileManager.default.createDirectory(atPath: pictures, withIntermediateDirectories: true)) != nil {
                return pictures
            }
            return NSTemporaryDirectory()
        }
    }
    
    /// Captures a screenshot based on current preferences and target
    func captureScreenshot(target: CaptureTarget = .allDisplays, delay: Double? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        // Special case: Action to show visual window number badges
        if target == .showWindowNumbers {
            WindowManager.shared.showWindowBadges()
            speakFeedback("Showing window numbers")
            completion(.success("Window badges displayed"))
            return
        }
        
        // Always dismiss visual badges so they don't appear in the captured image
        WindowManager.shared.dismissBadges()
        
        let prefs = PreferencesManager.shared
        let captureDelay = delay ?? prefs.delayBeforeCapture
        
        let performCapture = { [weak self] in
            guard let self = self else { return }
            
            // Visual flash (skip for interactive crosshair mode)
            if prefs.flashScreen && target != .interactiveArea {
                self.flashScreens()
            }
            
            let folder = self.resolveOutputFolder()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let timestamp = dateFormatter.string(from: Date())
            
            var targetLabel = ""
            var targetDetail = target.description
            var arguments: [String] = []
            
            switch target {
            case .allDisplays:
                targetLabel = ""
            case .display(let displayIndex):
                targetLabel = " - Display \(displayIndex)"
                arguments.append(contentsOf: ["-D", "\(displayIndex)"])
            case .window(let windowIndex):
                if let win = WindowManager.shared.window(forNumber: windowIndex) {
                    targetLabel = " - Window \(windowIndex) (\(win.appName))"
                    targetDetail = "Window \(windowIndex) (\(win.appName))"
                    arguments.append(contentsOf: ["-l", "\(win.id)"])
                } else if let fallbackWin = WindowManager.shared.window(forNumber: 1) {
                    targetLabel = " - Window 1 (\(fallbackWin.appName))"
                    targetDetail = "Window 1 (\(fallbackWin.appName))"
                    arguments.append(contentsOf: ["-l", "\(fallbackWin.id)"])
                } else {
                    targetLabel = " - Window \(windowIndex)"
                }
            case .app(let appName):
                if let win = WindowManager.shared.window(forApp: appName) {
                    targetLabel = " - \(win.appName)"
                    targetDetail = "\(win.appName) Window"
                    arguments.append(contentsOf: ["-l", "\(win.id)"])
                } else {
                    targetLabel = " - \(appName.capitalized)"
                    targetDetail = "\(appName.capitalized) (App Not Found - Captured Main Display)"
                }
            case .interactiveArea:
                targetLabel = " - Selection"
                targetDetail = "Selected Area"
                arguments.append("-i")
            case .extractText:
                targetLabel = " - OCR Text"
                targetDetail = "Text Extraction"
            case .showWindowNumbers:
                break
            }
            
            let baseName = "Screenshot \(timestamp)\(targetLabel)"
            var targetPath = (folder as NSString).appendingPathComponent("\(baseName).png")
            
            var counter = 1
            while FileManager.default.fileExists(atPath: targetPath) {
                targetPath = (folder as NSString).appendingPathComponent("\(baseName) (\(counter)).png")
                counter += 1
            }
            
            if !prefs.playShutterSound {
                arguments.append("-x")
            }
            if prefs.includeCursor && target != .allDisplays && target != .interactiveArea {
                arguments.append("-C")
            }
            arguments.append(targetPath)
            
            // Execute /usr/sbin/screencapture
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            
            let pipe = Pipe()
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: targetPath) {
                    if target == .extractText {
                        self.performTextExtraction(from: targetPath)
                    } else {
                        let copied = self.copyToClipboard(filePath: targetPath)
                        self.notifyUser(path: targetPath, targetDescription: targetDetail, copiedToClipboard: copied)
                    }
                    
                    self.speakFeedback("\(targetDetail) captured")
                    
                    DispatchQueue.main.async {
                        FloatingPreviewController.shared.show(filePath: targetPath, title: targetDetail)
                    }
                    
                    completion(.success(targetPath))
                } else {
                    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let description = (errMsg?.isEmpty == false) ? errMsg! : "Failed to capture \(targetDetail)"
                    let err = NSError(domain: "VoiceShot", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: description])
                    completion(.failure(err))
                }
            } catch {
                completion(.failure(error))
            }
        }
        
        if captureDelay > 0.05 {
            DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) {
                performCapture()
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                performCapture()
            }
        }
    }
    
    /// Extracts text from captured image and copies text directly to clipboard
    func performTextExtraction(from filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        let request = VNRecognizeTextRequest { [weak self] req, error in
            guard let observations = req.results as? [VNRecognizedTextObservation], error == nil else {
                return
            }
            
            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
            let fullText = strings.joined(separator: "\n")
            
            DispatchQueue.main.async {
                if !fullText.isEmpty {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(fullText, forType: .string)
                    
                    let wordCount = fullText.split(separator: " ").count
                    self?.speakFeedback("Text copied to clipboard")
                    self?.notifyOCRSuccess(wordCount: wordCount, preview: fullText)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(url: fileURL, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
    
    private func notifyOCRSuccess(wordCount: Int, preview: String) {
        guard PreferencesManager.shared.showNotification else { return }
        let snippet = String(preview.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        
        if Bundle.main.bundleIdentifier != nil {
            let content = UNMutableNotificationContent()
            content.title = "Text Extracted & Copied! 📝📋"
            content.subtitle = "\(wordCount) words copied to clipboard"
            content.body = "\"\(snippet)...\""
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        } else {
            let script = "display notification \"\(snippet)...\" with title \"Text Copied! 📝📋\" subtitle \"\(wordCount) words on clipboard\""
            var errorInfo: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        }
    }
    
    /// Copies image and file URL to macOS general pasteboard
    @discardableResult
    func copyToClipboard(filePath: String) -> Bool {
        guard PreferencesManager.shared.copyToClipboard else { return false }
        
        let url = URL(fileURLWithPath: filePath)
        if let image = NSImage(contentsOfFile: filePath) {
            let pb = NSPasteboard.general
            pb.clearContents()
            return pb.writeObjects([image, url as NSURL])
        }
        return false
    }
    
    private func notifyUser(path: String, targetDescription: String, copiedToClipboard: Bool) {
        guard PreferencesManager.shared.showNotification else { return }
        
        let filename = (path as NSString).lastPathComponent
        let folderName = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let clipNotice = copiedToClipboard ? " (Copied to Clipboard!)" : ""
        
        if Bundle.main.bundleIdentifier != nil {
            let content = UNMutableNotificationContent()
            content.title = "VoiceShot Captured 📸"
            content.subtitle = "\(targetDescription)\(copiedToClipboard ? " (Copied to Clipboard)" : "")"
            content.body = "Saved to \(folderName): \(filename)"
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if error != nil {
                    let script = "display notification \"Saved to \(folderName)\(clipNotice)\" with title \"VoiceShot 📸\" subtitle \"\(targetDescription)\""
                    var errorInfo: NSDictionary?
                    NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
                }
            }
        } else {
            let script = "display notification \"Saved to \(folderName)\(clipNotice)\" with title \"VoiceShot 📸\" subtitle \"\(targetDescription)\""
            var errorInfo: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        }
    }
    
    func openScreenshotsFolder() {
        let folder = resolveOutputFolder()
        let url = URL(fileURLWithPath: folder)
        NSWorkspace.shared.open(url)
    }
    
    func revealScreenshot(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
