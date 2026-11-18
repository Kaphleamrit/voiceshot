import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Set as Menu Bar accessory (no dock icon clutter)
app.setActivationPolicy(.accessory)

// Check CLI arguments
if CommandLine.arguments.contains("--monitor") || CommandLine.arguments.contains("-m") {
    DispatchQueue.main.async {
        delegate.showMonitorWindow()
    }
}

if CommandLine.arguments.contains("--test") {
    print("[VoiceShot] Running screenshot test...")
    ScreenshotManager.shared.captureScreenshot { result in
        switch result {
        case .success(let path):
            print("[VoiceShot] Test capture succeeded: \(path)")
        case .failure(let error):
            print("[VoiceShot] Test capture failed: \(error.localizedDescription)")
        }
    }
}

app.run()
