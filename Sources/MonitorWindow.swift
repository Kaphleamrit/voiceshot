import AppKit
import Foundation

final class MonitorWindowController: NSWindowController {
    static let shared = MonitorWindowController()
    
    // UI Elements
    private let statusLabel = NSTextField(labelWithString: "Status: Initializing...")
    private let statusIndicator = NSView()
    private let audioLevelIndicator = NSProgressIndicator()
    private let transcriptLabel = NSTextField(wrappingLabelWithString: "Commands: \"snap1\", \"snap2\", \"snap3\", \"snap Safari\", \"show numbers\"...")
    private let lastActionLabel = NSTextField(labelWithString: "Last screenshot: None")
    
    private let toggleListeningButton = NSButton()
    private let showBadgesButton = NSButton()
    private let testAllButton = NSButton()
    private let testWindow1Button = NSButton()
    private let testWindow2Button = NSButton()
    private let testWindow3Button = NSButton()
    private let testAreaButton = NSButton()
    private let testOCRButton = NSButton()
    private let openFolderButton = NSButton()
    
    private let windowListLabel = NSTextField(wrappingLabelWithString: "Active Windows: Loading...")
    
    private let savePathField = NSTextField()
    private let triggersField = NSTextField()
    private let clipboardCheckbox = NSButton(checkboxWithTitle: "Copy screenshot to clipboard automatically", target: nil, action: nil)
    private let floatingPreviewCheckbox = NSButton(checkboxWithTitle: "Show floating preview thumbnail (quick actions)", target: nil, action: nil)
    private let spokenFeedbackCheckbox = NSButton(checkboxWithTitle: "Spoken voice confirmation (e.g. \"Window 1 captured\")", target: nil, action: nil)
    private let shutterSoundCheckbox = NSButton(checkboxWithTitle: "Play camera shutter sound", target: nil, action: nil)
    private let flashScreenCheckbox = NSButton(checkboxWithTitle: "Flash screen on capture", target: nil, action: nil)
    private let notificationCheckbox = NSButton(checkboxWithTitle: "Show desktop notification", target: nil, action: nil)
    private let cursorCheckbox = NSButton(checkboxWithTitle: "Include mouse cursor in screenshot", target: nil, action: nil)
    private let delayPopUp = NSPopUpButton()
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 750),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceShot Pro - Preferences & Live Monitor"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        
        setupUI()
        setupBindings()
        refreshSettingsValues()
        refreshActiveWindowsList()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        contentView.wantsLayer = true
        window.contentView = contentView
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
        contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // 1. Header
        let headerBox = NSStackView()
        headerBox.orientation = .horizontal
        headerBox.spacing = 12
        headerBox.alignment = .centerY
        
        let titleLabel = NSTextField(labelWithString: "VoiceShot Pro 🎙️📸")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        headerBox.addArrangedSubview(titleLabel)
        
        statusIndicator.wantsLayer = true
        statusIndicator.layer?.cornerRadius = 6
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusIndicator.widthAnchor.constraint(equalToConstant: 12),
            statusIndicator.heightAnchor.constraint(equalToConstant: 12)
        ])
        updateStatusBadge(isListening: false)
        headerBox.addArrangedSubview(statusIndicator)
        
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        headerBox.addArrangedSubview(statusLabel)
        
        mainStack.addArrangedSubview(headerBox)
        
        // 2. Live Audio & Speech Monitor Card
        let monitorCard = createCardView()
        let monitorStack = NSStackView()
        monitorStack.orientation = .vertical
        monitorStack.alignment = .leading
        monitorStack.spacing = 8
        monitorStack.translatesAutoresizingMaskIntoConstraints = false
        monitorStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        monitorCard.addSubview(monitorStack)
        
        NSLayoutConstraint.activate([
            monitorStack.topAnchor.constraint(equalTo: monitorCard.topAnchor),
            monitorStack.leadingAnchor.constraint(equalTo: monitorCard.leadingAnchor),
            monitorStack.trailingAnchor.constraint(equalTo: monitorCard.trailingAnchor),
            monitorStack.bottomAnchor.constraint(equalTo: monitorCard.bottomAnchor)
        ])
        
        let monitorTitle = NSTextField(labelWithString: "LIVE SPEECH & AUDIO MONITOR")
        monitorTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        monitorTitle.textColor = .secondaryLabelColor
        monitorStack.addArrangedSubview(monitorTitle)
        
        // Audio Level Bar
        let audioStack = NSStackView()
        audioStack.orientation = .horizontal
        audioStack.spacing = 8
        audioStack.alignment = .centerY
        
        let micLabel = NSTextField(labelWithString: "Mic:")
        micLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        audioStack.addArrangedSubview(micLabel)
        
        audioLevelIndicator.isIndeterminate = false
        audioLevelIndicator.minValue = 0.0
        audioLevelIndicator.maxValue = 1.0
        audioLevelIndicator.doubleValue = 0.0
        audioLevelIndicator.translatesAutoresizingMaskIntoConstraints = false
        audioLevelIndicator.widthAnchor.constraint(equalToConstant: 420).isActive = true
        audioStack.addArrangedSubview(audioLevelIndicator)
        
        monitorStack.addArrangedSubview(audioStack)
        
        // Live transcript
        transcriptLabel.font = NSFont.systemFont(ofSize: 12)
        transcriptLabel.textColor = .labelColor
        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false
        transcriptLabel.widthAnchor.constraint(equalToConstant: 480).isActive = true
        monitorStack.addArrangedSubview(transcriptLabel)
        
        lastActionLabel.font = NSFont.systemFont(ofSize: 11)
        lastActionLabel.textColor = .secondaryLabelColor
        monitorStack.addArrangedSubview(lastActionLabel)
        
        mainStack.addArrangedSubview(monitorCard)
        
        // 3. Numbered Windows Mapping Card
        let windowMapCard = createCardView()
        let windowMapStack = NSStackView()
        windowMapStack.orientation = .vertical
        windowMapStack.alignment = .leading
        windowMapStack.spacing = 6
        windowMapStack.translatesAutoresizingMaskIntoConstraints = false
        windowMapStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        windowMapCard.addSubview(windowMapStack)
        
        NSLayoutConstraint.activate([
            windowMapStack.topAnchor.constraint(equalTo: windowMapCard.topAnchor),
            windowMapStack.leadingAnchor.constraint(equalTo: windowMapCard.leadingAnchor),
            windowMapStack.trailingAnchor.constraint(equalTo: windowMapCard.trailingAnchor),
            windowMapStack.bottomAnchor.constraint(equalTo: windowMapCard.bottomAnchor)
        ])
        
        let mapHeader = NSStackView()
        mapHeader.orientation = .horizontal
        mapHeader.spacing = 10
        mapHeader.alignment = .centerY
        
        let mapTitle = NSTextField(labelWithString: "OPEN WINDOWS BY VOICE COMMAND")
        mapTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        mapTitle.textColor = .secondaryLabelColor
        mapHeader.addArrangedSubview(mapTitle)
        
        showBadgesButton.title = "🏷️ Show Badges on Screen"
        showBadgesButton.bezelStyle = .inline
        showBadgesButton.target = self
        showBadgesButton.action = #selector(showBadgesClicked)
        mapHeader.addArrangedSubview(showBadgesButton)
        
        let refreshBtn = NSButton(title: "🔄", target: self, action: #selector(refreshActiveWindowsList))
        refreshBtn.bezelStyle = .inline
        refreshBtn.toolTip = "Refresh active window list"
        mapHeader.addArrangedSubview(refreshBtn)
        
        windowMapStack.addArrangedSubview(mapHeader)
        
        windowListLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        windowListLabel.textColor = .labelColor
        windowListLabel.translatesAutoresizingMaskIntoConstraints = false
        windowListLabel.widthAnchor.constraint(equalToConstant: 480).isActive = true
        windowMapStack.addArrangedSubview(windowListLabel)
        
        mainStack.addArrangedSubview(windowMapCard)
        
        // 4. Quick Action Buttons Row 1 & Row 2
        let actionsStack1 = NSStackView()
        actionsStack1.orientation = .horizontal
        actionsStack1.spacing = 6
        actionsStack1.alignment = .centerY
        
        toggleListeningButton.title = "Pause Listening"
        toggleListeningButton.bezelStyle = .rounded
        toggleListeningButton.target = self
        toggleListeningButton.action = #selector(toggleListeningClicked)
        actionsStack1.addArrangedSubview(toggleListeningButton)
        
        testAllButton.title = "📸 Full"
        testAllButton.bezelStyle = .rounded
        testAllButton.target = self
        testAllButton.action = #selector(testAllClicked)
        actionsStack1.addArrangedSubview(testAllButton)
        
        testWindow1Button.title = "🪟 snap1"
        testWindow1Button.bezelStyle = .rounded
        testWindow1Button.target = self
        testWindow1Button.action = #selector(testWindow1Clicked)
        actionsStack1.addArrangedSubview(testWindow1Button)
        
        testWindow2Button.title = "🪟 snap2"
        testWindow2Button.bezelStyle = .rounded
        testWindow2Button.target = self
        testWindow2Button.action = #selector(testWindow2Clicked)
        actionsStack1.addArrangedSubview(testWindow2Button)
        
        testWindow3Button.title = "🪟 snap3"
        testWindow3Button.bezelStyle = .rounded
        testWindow3Button.target = self
        testWindow3Button.action = #selector(testWindow3Clicked)
        actionsStack1.addArrangedSubview(testWindow3Button)
        
        testAreaButton.title = "✂️ Area"
        testAreaButton.bezelStyle = .rounded
        testAreaButton.target = self
        testAreaButton.action = #selector(testAreaClicked)
        actionsStack1.addArrangedSubview(testAreaButton)
        
        testOCRButton.title = "📝 OCR"
        testOCRButton.bezelStyle = .rounded
        testOCRButton.target = self
        testOCRButton.action = #selector(testOCRClicked)
        actionsStack1.addArrangedSubview(testOCRButton)
        
        openFolderButton.title = "📂 Folder"
        openFolderButton.bezelStyle = .rounded
        openFolderButton.target = self
        openFolderButton.action = #selector(openFolderClicked)
        actionsStack1.addArrangedSubview(openFolderButton)
        
        mainStack.addArrangedSubview(actionsStack1)
        
        // 5. Settings Section
        let settingsTitle = NSTextField(labelWithString: "SETTINGS & PREFERENCES")
        settingsTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        settingsTitle.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(settingsTitle)
        
        // Save Folder Row
        let folderRow = NSStackView()
        folderRow.orientation = .horizontal
        folderRow.spacing = 8
        folderRow.alignment = .centerY
        
        let folderLabel = NSTextField(labelWithString: "Save:")
        folderLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        folderRow.addArrangedSubview(folderLabel)
        
        savePathField.isEditable = false
        savePathField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        savePathField.translatesAutoresizingMaskIntoConstraints = false
        savePathField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        folderRow.addArrangedSubview(savePathField)
        
        let browseButton = NSButton(title: "Choose...", target: self, action: #selector(chooseFolderClicked))
        browseButton.bezelStyle = .rounded
        folderRow.addArrangedSubview(browseButton)
        
        mainStack.addArrangedSubview(folderRow)
        
        // Checkboxes
        clipboardCheckbox.target = self
        clipboardCheckbox.action = #selector(checkboxChanged)
        clipboardCheckbox.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        mainStack.addArrangedSubview(clipboardCheckbox)
        
        floatingPreviewCheckbox.target = self
        floatingPreviewCheckbox.action = #selector(checkboxChanged)
        mainStack.addArrangedSubview(floatingPreviewCheckbox)
        
        spokenFeedbackCheckbox.target = self
        spokenFeedbackCheckbox.action = #selector(checkboxChanged)
        mainStack.addArrangedSubview(spokenFeedbackCheckbox)
        
        shutterSoundCheckbox.target = self
        shutterSoundCheckbox.action = #selector(checkboxChanged)
        mainStack.addArrangedSubview(shutterSoundCheckbox)
        
        flashScreenCheckbox.target = self
        flashScreenCheckbox.action = #selector(checkboxChanged)
        mainStack.addArrangedSubview(flashScreenCheckbox)
        
        notificationCheckbox.target = self
        notificationCheckbox.action = #selector(checkboxChanged)
        mainStack.addArrangedSubview(notificationCheckbox)
    }
    
    private func createCardView() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 8
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: 510).isActive = true
        return card
    }
    
    @objc func refreshActiveWindowsList() {
        let windows = WindowManager.shared.getVisibleWindows()
        if windows.isEmpty {
            windowListLabel.stringValue = "No standard application windows detected."
        } else {
            let lines = windows.prefix(6).map { item in
                let titleTrunc = item.title.isEmpty ? "" : " - \"\(String(item.title.prefix(28)))\""
                return " snap\(item.number)  \(item.appName)\(titleTrunc)"
            }
            windowListLabel.stringValue = lines.joined(separator: "\n")
        }
    }
    
    private func setupBindings() {
        let speech = SpeechRecognizer.shared
        
        speech.onAudioLevelChanged = { [weak self] level in
            self?.audioLevelIndicator.doubleValue = Double(level)
        }
        
        speech.onTranscriptChanged = { [weak self] text in
            self?.transcriptLabel.stringValue = "Heard: \"\(text)\""
        }
        
    }

    func showDetectedCommand(target: CaptureTarget, delay: Double, trigger: String) {
        let delayMsg = delay > 0 ? " in \(Int(delay))s" : ""
        transcriptLabel.stringValue = "🎯 Command detected: \"\(trigger)\"\(delayMsg) -> \(target.description)!"
    }
    
    func handleSpeechState(_ state: SpeechState) {
        switch state {
        case .listening:
            statusLabel.stringValue = "Listening for voice commands 🎙️"
            statusLabel.textColor = .labelColor
            updateStatusBadge(isListening: true)
            toggleListeningButton.title = "Pause Listening"
        case .paused, .idle:
            statusLabel.stringValue = "Paused"
            statusLabel.textColor = .secondaryLabelColor
            updateStatusBadge(isListening: false)
            toggleListeningButton.title = "Resume Listening"
            audioLevelIndicator.doubleValue = 0.0
        case .requestingPermission:
            statusLabel.stringValue = "Requesting permissions..."
            statusLabel.textColor = .systemOrange
            updateStatusBadge(isListening: false, color: .systemOrange)
        case .permissionDenied(let msg):
            statusLabel.stringValue = "Permission Required"
            statusLabel.textColor = .systemRed
            transcriptLabel.stringValue = msg
            updateStatusBadge(isListening: false, color: .systemRed)
            toggleListeningButton.title = "Grant Permissions"
        case .error(let msg):
            statusLabel.stringValue = "Error"
            statusLabel.textColor = .systemRed
            transcriptLabel.stringValue = msg
            updateStatusBadge(isListening: false, color: .systemRed)
        }
    }
    
    private func updateStatusBadge(isListening: Bool, color: NSColor? = nil) {
        let chosenColor = color ?? (isListening ? NSColor.systemGreen : NSColor.systemGray)
        statusIndicator.layer?.backgroundColor = chosenColor.cgColor
    }
    
    func refreshSettingsValues() {
        let prefs = PreferencesManager.shared
        savePathField.stringValue = prefs.saveFolderPath
        clipboardCheckbox.state = prefs.copyToClipboard ? .on : .off
        floatingPreviewCheckbox.state = prefs.showFloatingPreview ? .on : .off
        spokenFeedbackCheckbox.state = prefs.spokenFeedback ? .on : .off
        shutterSoundCheckbox.state = prefs.playShutterSound ? .on : .off
        flashScreenCheckbox.state = prefs.flashScreen ? .on : .off
        notificationCheckbox.state = prefs.showNotification ? .on : .off
        refreshActiveWindowsList()
    }
    
    // MARK: - Actions
    
    @objc private func showBadgesClicked() {
        WindowManager.shared.showWindowBadges()
    }
    
    @objc private func toggleListeningClicked() {
        let speech = SpeechRecognizer.shared
        speech.toggleListening()
    }
    
    @objc private func testAllClicked() {
        handleCaptureTriggered(target: .allDisplays)
    }
    
    @objc private func testWindow1Clicked() {
        handleCaptureTriggered(target: .window(1))
    }
    
    @objc private func testWindow2Clicked() {
        handleCaptureTriggered(target: .window(2))
    }
    
    @objc private func testWindow3Clicked() {
        handleCaptureTriggered(target: .window(3))
    }
    
    @objc private func testAreaClicked() {
        handleCaptureTriggered(target: .interactiveArea)
    }
    
    @objc private func testOCRClicked() {
        handleCaptureTriggered(target: .extractText)
    }
    
    private func handleCaptureTriggered(target: CaptureTarget) {
        ScreenshotManager.shared.captureScreenshot(target: target) { [weak self] result in
            DispatchQueue.main.async {
                self?.showCaptureResult(result, target: target)
            }
        }
    }

    func showCaptureResult(_ result: Result<String, Error>, target: CaptureTarget) {
        switch result {
        case .success(let path):
            let filename = (path as NSString).lastPathComponent
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss"
            let time = df.string(from: Date())
            let clipMsg = PreferencesManager.shared.copyToClipboard ? " (📋 Copied)" : ""
            lastActionLabel.stringValue = "Last: \(target.description) - \(filename) at \(time)\(clipMsg)"
        case .failure(let error):
            lastActionLabel.stringValue = "Capture failed: \(error.localizedDescription)"
        }
    }
    
    @objc private func openFolderClicked() {
        ScreenshotManager.shared.openScreenshotsFolder()
    }
    
    @objc private func chooseFolderClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose destination folder for voice screenshots:"
        
        if panel.runModal() == .OK, let url = panel.url {
            PreferencesManager.shared.saveFolderPath = url.path
            savePathField.stringValue = url.path
        }
    }
    
    @objc private func checkboxChanged() {
        let prefs = PreferencesManager.shared
        prefs.copyToClipboard = clipboardCheckbox.state == .on
        prefs.showFloatingPreview = floatingPreviewCheckbox.state == .on
        prefs.spokenFeedback = spokenFeedbackCheckbox.state == .on
        prefs.playShutterSound = shutterSoundCheckbox.state == .on
        prefs.flashScreen = flashScreenCheckbox.state == .on
        prefs.showNotification = notificationCheckbox.state == .on
    }
}
