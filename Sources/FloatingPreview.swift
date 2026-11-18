import AppKit
import Foundation

final class FloatingPreviewController: NSWindowController {
    static let shared = FloatingPreviewController()
    
    private var dismissTimer: Timer?
    private var currentFilePath: String?
    
    private var fileButtons: [NSButton] = []
    private let imageView = NSImageView()
    private let filenameLabel = NSTextField(labelWithString: "")
    
    init() {
        let width: CGFloat = 260
        let height: CGFloat = 170
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        setupUI(width: width, height: height)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI(width: CGFloat, height: CGFloat) {
        guard let window = window else { return }
        
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        window.contentView = visualEffect
        
        // Thumbnail Image
        imageView.frame = NSRect(x: 10, y: 44, width: width - 20, height: 96)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        visualEffect.addSubview(imageView)
        
        // Target / Filename label
        filenameLabel.frame = NSRect(x: 12, y: 144, width: width - 40, height: 16)
        filenameLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        filenameLabel.textColor = .secondaryLabelColor
        filenameLabel.lineBreakMode = .byTruncatingTail
        visualEffect.addSubview(filenameLabel)
        
        // Close Button (X)
        let closeButton = NSButton(frame: NSRect(x: width - 24, y: height - 24, width: 16, height: 16))
        closeButton.title = "✕"
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(dismissPreview)
        visualEffect.addSubview(closeButton)
        
        // Action Buttons Row: [📋 Copy] [✏️ Edit] [📂 Finder] [🗑️ Delete]
        let btnStack = NSStackView(frame: NSRect(x: 8, y: 8, width: width - 16, height: 28))
        btnStack.orientation = .horizontal
        btnStack.distribution = .fillEqually
        btnStack.spacing = 6
        visualEffect.addSubview(btnStack)
        
        let copyBtn = createActionButton(title: "Copy", symbol: "doc.on.doc", action: #selector(copyClicked))
        let openBtn = createActionButton(title: "Preview", symbol: "pencil.tip", action: #selector(openClicked))
        let finderBtn = createActionButton(title: "Finder", symbol: "folder", action: #selector(finderClicked))
        let trashBtn = createActionButton(title: "Trash", symbol: "trash", action: #selector(trashClicked))
        fileButtons = [openBtn, finderBtn, trashBtn]
        trashBtn.contentTintColor = .systemRed
        
        btnStack.addArrangedSubview(copyBtn)
        btnStack.addArrangedSubview(openBtn)
        btnStack.addArrangedSubview(finderBtn)
        btnStack.addArrangedSubview(trashBtn)
        
        // Click on thumbnail opens file in Preview
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(openClicked))
        imageView.addGestureRecognizer(clickGesture)
    }
    
    private func createActionButton(title: String, symbol: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .roundRect
        btn.isBordered = true
        btn.target = self
        btn.action = action
        btn.toolTip = title
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            btn.image = img
            btn.imagePosition = .imageOnly
        } else {
            btn.title = title
        }
        return btn
    }
    
    func show(image: NSImage, filePath: String?, title: String) {
        guard PreferencesManager.shared.showFloatingPreview else { return }
        
        currentFilePath = filePath
        filenameLabel.stringValue = title
        
        imageView.image = image
        fileButtons.forEach { $0.isHidden = filePath == nil }
        
        guard let window = window, let screen = NSScreen.main else { return }
        
        // Position in bottom-right corner of main screen (above dock)
        let visibleFrame = screen.visibleFrame
        let targetX = visibleFrame.maxX - window.frame.width - 20
        let targetY = visibleFrame.minY + 24
        window.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        
        window.alphaValue = 0.0
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1.0
        }
        
        // Reset dismiss timer (auto-dismiss after 4.5 seconds)
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            self?.dismissPreview()
        }
    }
    
    @objc func dismissPreview() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        guard let window = window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
    
    @objc private func copyClicked() {
        guard let image = imageView.image else { return }
        ScreenshotManager.shared.copyToClipboard(image: image, path: currentFilePath)
        dismissPreview()
    }
    
    @objc private func openClicked() {
        guard let path = currentFilePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        dismissPreview()
    }
    
    @objc private func finderClicked() {
        guard let path = currentFilePath else { return }
        ScreenshotManager.shared.revealScreenshot(at: path)
        dismissPreview()
    }
    
    @objc private func trashClicked() {
        guard let path = currentFilePath else { return }
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        dismissPreview()
    }
}
