import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleListeningMenuItem: NSMenuItem!
    private var clipboardMenuItem: NSMenuItem!
    private var previewMenuItem: NSMenuItem!
    private var spokenMenuItem: NSMenuItem!
    private weak var monitor: MonitorWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupEventHandlers()
        
        // Start speech listening
        if PreferencesManager.shared.isListeningEnabled {
            SpeechRecognizer.shared.startListening()
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let symbolImage = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "VoiceShot") {
                symbolImage.isTemplate = true
                button.image = symbolImage
            } else {
                button.title = "📸"
            }
            button.toolTip = "VoiceShot Pro - Voice-Activated Screenshot"
        }
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "VoiceShot Pro 🎙️📸", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        statusMenuItem = NSMenuItem(title: "Status: Initializing...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Window Badging Action
        let showBadgesItem = NSMenuItem(title: "🏷️ Show Window Numbers On Screen", action: #selector(showBadgesNow), keyEquivalent: "n")
        showBadgesItem.keyEquivalentModifierMask = [.command, .shift]
        showBadgesItem.target = self
        menu.addItem(showBadgesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Manual capture actions
        let captureW1Item = NSMenuItem(title: "🪟 Capture Window 1 (snap1)", action: #selector(captureWindow1Now), keyEquivalent: "1")
        captureW1Item.keyEquivalentModifierMask = [.command, .shift]
        captureW1Item.target = self
        menu.addItem(captureW1Item)
        
        let captureW2Item = NSMenuItem(title: "🪟 Capture Window 2 (snap2)", action: #selector(captureWindow2Now), keyEquivalent: "2")
        captureW2Item.keyEquivalentModifierMask = [.command, .shift]
        captureW2Item.target = self
        menu.addItem(captureW2Item)
        
        let captureW3Item = NSMenuItem(title: "🪟 Capture Window 3 (snap3)", action: #selector(captureWindow3Now), keyEquivalent: "3")
        captureW3Item.keyEquivalentModifierMask = [.command, .shift]
        captureW3Item.target = self
        menu.addItem(captureW3Item)
        
        let captureAllItem = NSMenuItem(title: "📸 Capture All Displays", action: #selector(captureAllNow), keyEquivalent: "s")
        captureAllItem.keyEquivalentModifierMask = [.command, .shift]
        captureAllItem.target = self
        menu.addItem(captureAllItem)
        
        let captureAreaItem = NSMenuItem(title: "✂️ Capture Selection Area", action: #selector(captureAreaNow), keyEquivalent: "4")
        captureAreaItem.keyEquivalentModifierMask = [.command, .shift]
        captureAreaItem.target = self
        menu.addItem(captureAreaItem)
        
        let captureOCRItem = NSMenuItem(title: "📝 Extract Text (OCR)", action: #selector(captureOCRNow), keyEquivalent: "t")
        captureOCRItem.keyEquivalentModifierMask = [.command, .shift]
        captureOCRItem.target = self
        menu.addItem(captureOCRItem)
        
        menu.addItem(NSMenuItem.separator())
        
        toggleListeningMenuItem = NSMenuItem(title: "⏸️ Pause Listening", action: #selector(toggleListening), keyEquivalent: "")
        toggleListeningMenuItem.target = self
        menu.addItem(toggleListeningMenuItem)
        
        clipboardMenuItem = NSMenuItem(title: "📋 Copy to Clipboard", action: #selector(toggleClipboard), keyEquivalent: "")
        clipboardMenuItem.target = self
        clipboardMenuItem.state = PreferencesManager.shared.copyToClipboard ? .on : .off
        menu.addItem(clipboardMenuItem)
        
        previewMenuItem = NSMenuItem(title: "🖼️ Floating Preview", action: #selector(togglePreview), keyEquivalent: "")
        previewMenuItem.target = self
        previewMenuItem.state = PreferencesManager.shared.showFloatingPreview ? .on : .off
        menu.addItem(previewMenuItem)
        
        spokenMenuItem = NSMenuItem(title: "🗣️ Voice Feedback", action: #selector(toggleSpoken), keyEquivalent: "")
        spokenMenuItem.target = self
        spokenMenuItem.state = PreferencesManager.shared.spokenFeedback ? .on : .off
        menu.addItem(spokenMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let folderItem = NSMenuItem(title: "📂 Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        
        let prefsItem = NSMenuItem(title: "⚙️ Preferences & Live Monitor...", action: #selector(showMonitorWindow), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit VoiceShot", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func setupEventHandlers() {
        let speech = SpeechRecognizer.shared
        
        speech.onTriggerDetected = { [weak self] target, delay, trigger in
            self?.flashMenuBarIcon()
            self?.monitor?.showDetectedCommand(target: target, delay: delay, trigger: trigger)
            ScreenshotManager.shared.captureScreenshot(target: target, delay: delay > 0 ? delay : nil) { result in
                DispatchQueue.main.async {
                    self?.monitor?.showCaptureResult(result, target: target)
                }
                switch result {
                case .success(let path):
                    print("[VoiceShot] \(target.description) handled: \(path)")
                case .failure(let error):
                    print("[VoiceShot] Capture error: \(error.localizedDescription)")
                }
            }
        }
        
        speech.onStatusChanged = { [weak self] state in
            self?.updateMenuState(state)
            self?.monitor?.handleSpeechState(state)
        }
    }
    
    private func updateMenuState(_ state: SpeechState) {
        switch state {
        case .listening:
            statusMenuItem.title = "Status: Listening 🎙️"
            toggleListeningMenuItem.title = "⏸️ Pause Listening"
            setMenuBarSymbol(name: "camera.viewfinder")
        case .paused, .idle:
            statusMenuItem.title = "Status: Paused ⏸️"
            toggleListeningMenuItem.title = "▶️ Resume Listening"
            setMenuBarSymbol(name: "camera.viewfinder", alternateSymbol: "mic.slash")
        case .requestingPermission:
            statusMenuItem.title = "Status: Requesting Permission..."
        case .permissionDenied:
            statusMenuItem.title = "Status: ⚠️ Permission Denied"
            toggleListeningMenuItem.title = "⚙️ Open Settings..."
        case .error(let msg):
            statusMenuItem.title = "Status: Error (\(msg))"
        }
    }
    
    private func setMenuBarSymbol(name: String, alternateSymbol: String? = nil) {
        guard let button = statusItem.button else { return }
        let symbol = (alternateSymbol != nil ? NSImage(systemSymbolName: alternateSymbol!, accessibilityDescription: nil) : nil)
            ?? NSImage(systemSymbolName: name, accessibilityDescription: "VoiceShot")
        symbol?.isTemplate = true
        button.image = symbol
    }
    
    private func flashMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let flashSymbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        flashSymbol?.isTemplate = true
        button.image = flashSymbol
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.setMenuBarSymbol(name: "camera.viewfinder")
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func showBadgesNow() {
        WindowManager.shared.showWindowBadges()
    }
    
    @objc private func captureWindow1Now() {
        flashMenuBarIcon()
        ScreenshotManager.shared.captureScreenshot(target: .window(1)) { _ in }
    }
    
    @objc private func captureWindow2Now() {
        flashMenuBarIcon()
        ScreenshotManager.shared.captureScreenshot(target: .window(2)) { _ in }
    }
    
    @objc private func captureWindow3Now() {
        flashMenuBarIcon()
        ScreenshotManager.shared.captureScreenshot(target: .window(3)) { _ in }
    }
    
    @objc private func captureAllNow() {
        flashMenuBarIcon()
        ScreenshotManager.shared.captureScreenshot(target: .allDisplays) { _ in }
    }
    
    @objc private func captureAreaNow() {
        flashMenuBarIcon()
        ScreenshotManager.shared.captureScreenshot(target: .interactiveArea) { _ in }
    }
    
    @objc private func captureOCRNow() {
        flashMenuBarIcon()
        ScreenshotManager.shared.captureScreenshot(target: .extractText) { _ in }
    }
    
    @objc private func toggleListening() {
        let speech = SpeechRecognizer.shared
        speech.toggleListening()
    }
    
    @objc private func toggleClipboard() {
        let prefs = PreferencesManager.shared
        prefs.copyToClipboard.toggle()
        clipboardMenuItem.state = prefs.copyToClipboard ? .on : .off
        monitor?.refreshSettingsValues()
    }
    
    @objc private func togglePreview() {
        let prefs = PreferencesManager.shared
        prefs.showFloatingPreview.toggle()
        previewMenuItem.state = prefs.showFloatingPreview ? .on : .off
        monitor?.refreshSettingsValues()
    }
    
    @objc private func toggleSpoken() {
        let prefs = PreferencesManager.shared
        prefs.spokenFeedback.toggle()
        spokenMenuItem.state = prefs.spokenFeedback ? .on : .off
        monitor?.refreshSettingsValues()
    }
    
    @objc private func openFolder() {
        ScreenshotManager.shared.openScreenshotsFolder()
    }
    
    @objc func showMonitorWindow() {
        let controller = MonitorWindowController.shared
        monitor = controller
        controller.handleSpeechState(SpeechRecognizer.shared.currentState)
        controller.refreshSettingsValues()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func quitApp() {
        SpeechRecognizer.shared.stopListening()
        NSApplication.shared.terminate(nil)
    }
}
