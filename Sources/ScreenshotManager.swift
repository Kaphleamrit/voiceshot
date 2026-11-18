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
    private let captureQueue = DispatchQueue(label: "com.voiceshot.captureQueue", qos: .userInitiated)
    private var flashWindows: [NSWindow] = []
    private var requestedScreenRecording = false
    
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
            self.dismissFlash()
            for screen in NSScreen.screens {
                let window = NSWindow(contentRect: screen.frame,
                                      styleMask: .borderless,
                                      backing: .buffered,
                                      defer: false)
                window.isOpaque = false
                window.isReleasedWhenClosed = false
                window.backgroundColor = NSColor.white.withAlphaComponent(0.65)
                window.level = .floating
                window.ignoresMouseEvents = true
                window.orderFrontRegardless()
                self.flashWindows.append(window)
                
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 0.0
                }, completionHandler: {
                    window.orderOut(nil)
                    self.flashWindows.removeAll { $0 === window }
                })
            }
        }
    }
    
    private func dismissFlash() {
        flashWindows.forEach { $0.orderOut(nil) }
        flashWindows.removeAll()
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
        let badgeTargets = WindowManager.shared.hideBadgesForCapture()
        
        let prefs = PreferencesManager.shared
        let captureDelay = delay ?? prefs.delayBeforeCapture
        
        let performCapture = { [weak self] in
            guard let self = self else { return }
            
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
                let win: WindowItem?
                if badgeTargets.isEmpty {
                    win = WindowManager.shared.window(forNumber: windowIndex)
                } else if let selected = badgeTargets.first(where: { $0.number == windowIndex }) {
                    win = WindowManager.shared.getVisibleWindows(limit: .max).first { $0.id == selected.id }
                } else {
                    win = nil
                }
                if let win {
                    targetLabel = " - Window \(windowIndex) (\(win.appName))"
                    targetDetail = "Window \(windowIndex) (\(win.appName))"
                    arguments.append(contentsOf: ["-l", "\(win.id)"])
                } else {
                    let message = "Window \(windowIndex) is no longer available. Say “show numbers” to see the current windows."
                    completion(.failure(NSError(domain: "VoiceShot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])))
                    return
                }
            case .app(let appName):
                if let win = WindowManager.shared.window(forApp: appName) {
                    targetLabel = " - \(win.appName)"
                    targetDetail = "\(win.appName) Window"
                    arguments.append(contentsOf: ["-l", "\(win.id)"])
                } else {
                    let message = "No visible window for \(appName.capitalized)."
                    completion(.failure(NSError(domain: "VoiceShot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])))
                    return
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
            
            let targetPath: String?
            if prefs.saveLocally {
                let folder = self.resolveOutputFolder()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
                let timestamp = dateFormatter.string(from: Date())
                let baseName = "Screenshot \(timestamp)\(targetLabel)"
                var candidate = (folder as NSString).appendingPathComponent("\(baseName).png")

                var counter = 1
                while FileManager.default.fileExists(atPath: candidate) {
                    candidate = (folder as NSString).appendingPathComponent("\(baseName) (\(counter)).png")
                    counter += 1
                }

                targetPath = candidate
            } else {
                targetPath = nil
            }

            if !prefs.playShutterSound {
                arguments.append("-x")
            }
            if prefs.includeCursor && target != .allDisplays && target != .interactiveArea {
                arguments.append("-C")
            }
            arguments.append(targetPath ?? "-c")
            
            // Execute /usr/sbin/screencapture
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            
            let pipe = Pipe()
            process.standardError = pipe
            
            do {
                DispatchQueue.main.sync {
                    self.dismissFlash()
                    switch target {
                    case .window, .app:
                        // A window capture excludes overlays. Keep any badges requested since it was queued.
                        break
                    default:
                        WindowManager.shared.hideBadgesForCapture()
                    }
                }
                let previousClipboard = targetPath == nil ? NSPasteboard.general.changeCount : nil
                try process.run()
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                let image: NSImage?
                if process.terminationStatus != 0 {
                    image = nil
                } else if let targetPath {
                    image = NSImage(contentsOfFile: targetPath)
                } else if previousClipboard != NSPasteboard.general.changeCount {
                    image = NSImage(pasteboard: .general)
                } else {
                    image = nil
                }

                if let image {
                    if prefs.flashScreen && target != .interactiveArea { self.flashScreens() }
                    DispatchQueue.main.async {
                        FloatingPreviewController.shared.show(image: image, filePath: targetPath, title: targetDetail)
                    }
                    if target == .extractText {
                        self.performTextExtraction(from: image, completion: completion)
                    } else {
                        let copied = targetPath == nil || (prefs.copyToClipboard && self.copyToClipboard(image: image, path: targetPath))
                        let message = targetPath.map { "Saved to \($0)" + (copied ? " and copied to clipboard" : "") } ?? "Copied to clipboard"
                        self.notifyUser(message: message, targetDescription: targetDetail)
                        self.speakFeedback("\(targetDetail) captured")
                        completion(.success(message))
                    }
                } else {
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let description: String
                    if !CGPreflightScreenCaptureAccess() {
                        DispatchQueue.main.async {
                            guard !self.requestedScreenRecording else { return }
                            self.requestedScreenRecording = true
                            _ = CGRequestScreenCaptureAccess()
                        }
                        description = "Enable VoiceShot in System Settings under Privacy & Security → Screen Recording."
                    } else {
                        description = (errMsg?.isEmpty == false) ? errMsg! : "Failed to capture \(targetDetail)"
                    }
                    let err = NSError(domain: "VoiceShot", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: description])
                    completion(.failure(err))
                }
            } catch {
                completion(.failure(error))
            }
        }
        
        if captureDelay > 0.05 {
            captureQueue.asyncAfter(deadline: .now() + captureDelay) {
                performCapture()
            }
        } else {
            captureQueue.async {
                performCapture()
            }
        }
    }
    
    /// Extracts text from captured image and copies text directly to clipboard
    private func performTextExtraction(from image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw NSError(domain: "VoiceShot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read the captured image."])
            }
            try VNImageRequestHandler(cgImage: pixels).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else {
                throw NSError(domain: "VoiceShot", code: 3, userInfo: [NSLocalizedDescriptionKey: "No text found in the capture."])
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            guard pb.setString(text, forType: .string) else {
                throw NSError(domain: "VoiceShot", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not copy text to the clipboard."])
            }
            speakFeedback("Text copied to clipboard")
            notifyOCRSuccess(wordCount: text.split(whereSeparator: { $0.isWhitespace }).count, preview: text)
            completion(.success("Text copied to clipboard"))
        } catch {
            completion(.failure(error))
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
    func copyToClipboard(image: NSImage, path: String?) -> Bool {
        var objects: [NSPasteboardWriting] = [image]
        if let path { objects.append(URL(fileURLWithPath: path) as NSURL) }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects(objects)
    }

    private func notifyUser(message: String, targetDescription: String) {
        guard PreferencesManager.shared.showNotification, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "VoiceShot captured \(targetDescription)"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
