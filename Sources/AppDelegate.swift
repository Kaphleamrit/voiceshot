import AppKit
import CoreGraphics
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleListeningMenuItem: NSMenuItem!
    private var clipboardMenuItem: NSMenuItem!
    private var previewMenuItem: NSMenuItem!
    private var spokenMenuItem: NSMenuItem!
    private var isShowingPastePermissionAlert = false
    private weak var monitor: MonitorWindowController?
    @MainActor private lazy var updateChecker = UpdateChecker()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupEventHandlers()
        WindowManager.shared.startMonitoringWindowNumbers()
        updateChecker.start()
        
        // Start speech listening
        if PreferencesManager.shared.isListeningEnabled {
            SpeechRecognizer.shared.startListening()
        }
    }
    
    @MainActor private func setupStatusItem() {
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
        
        let saveItem = NSMenuItem(title: "Save Screenshots Locally", action: #selector(toggleSaving), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

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

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(UpdateChecker.checkNow), keyEquivalent: "")
        updateItem.target = updateChecker
        menu.addItem(updateItem)
        menu.addItem(updateChecker.automaticChecksItem)
        
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
                    if case .failure(let error) = result {
                        self?.statusItem.button?.toolTip = error.localizedDescription
                        if case .permissionRequired? = error as? VoicePasteError {
                            self?.showPastePermissionAlert()
                        }
                    } else {
                        self?.statusItem.button?.toolTip = "VoiceShot Pro - Voice-Activated Screenshot"
                    }
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

    private func showPastePermissionAlert() {
        guard !isShowingPastePermissionAlert else { return }
        isShowingPastePermissionAlert = true
        defer { isShowingPastePermissionAlert = false }

        let alert = NSAlert()
        alert.messageText = "Allow VoiceShot to paste"
        alert.informativeText = "In Accessibility settings, turn on VoiceShot. Then return to the app where you want to paste and say “paste” again."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        _ = CGRequestPostEventAccess()
        if let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settings)
        }
    }
    
    private func updateMenuState(_ state: SpeechState) {
        switch state {
        case .listening:
            statusMenuItem.title = "Status: Listening 🎙️"
            toggleListeningMenuItem.title = "⏸️ Pause Listening"
        case .onBreak:
            statusMenuItem.title = "Status: On Break · Say \"wake up\""
            toggleListeningMenuItem.title = "▶️ Resume Listening"
        case .paused, .idle:
            statusMenuItem.title = "Status: Paused ⏸️"
            toggleListeningMenuItem.title = "▶️ Resume Listening"
        case .requestingPermission:
            statusMenuItem.title = "Status: Requesting Permission..."
        case .permissionDenied:
            statusMenuItem.title = "Status: ⚠️ Permission Denied"
            toggleListeningMenuItem.title = "⚙️ Open Settings..."
        case .error(let msg):
            statusMenuItem.title = "Status: Error (\(msg))"
        }
        updateMenuBarSymbol(for: state)
    }

    private func updateMenuBarSymbol(for state: SpeechState) {
        switch state {
        case .onBreak:
            setMenuBarSymbol(name: "camera.viewfinder", alternateSymbol: "moon")
        case .paused, .idle:
            setMenuBarSymbol(name: "camera.viewfinder", alternateSymbol: "mic.slash")
        default:
            setMenuBarSymbol(name: "camera.viewfinder")
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
            self?.updateMenuBarSymbol(for: SpeechRecognizer.shared.currentState)
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
    
    @objc private func toggleSaving() {
        PreferencesManager.shared.saveLocally.toggle()
        monitor?.refreshSettingsValues()
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


extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleSaving) { item.state = PreferencesManager.shared.saveLocally ? .on : .off }
        if item === clipboardMenuItem {
            item.state = PreferencesManager.shared.copyToClipboard ? .on : .off
            return PreferencesManager.shared.saveLocally
        }
        return true
    }
}
