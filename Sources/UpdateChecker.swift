import AppKit
import Sparkle

@MainActor
final class UpdateChecker: NSObject, NSMenuItemValidation {
    private var started = false
    private lazy var driver = VoiceShotUpdateDriver(hostBundle: .main, delegate: nil)
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)

    lazy var automaticChecksItem: NSMenuItem = {
        let item = NSMenuItem(title: "Automatically Check for Updates",
                              action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        item.target = self
        return item
    }()

    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        do {
            try updater.start()
            started = true
            driver.onOptOut = { [weak self] in self?.updater.automaticallyChecksForUpdates = false }
        } catch {
            NSLog("VoiceShot updater could not start: %@", error.localizedDescription)
        }
    }

    @objc func checkNow() {
        updater.checkForUpdates()
    }

    @objc private func toggleAutomaticChecks() {
        updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard started else { return false }
        if menuItem === automaticChecksItem {
            menuItem.state = updater.automaticallyChecksForUpdates ? .on : .off
            return true
        }
        return updater.canCheckForUpdates
    }
}

@MainActor
private final class VoiceShotUpdateDriver: SPUStandardUserDriver {
    var onOptOut: (() -> Void)?

    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // Keep the standard progress window for downloading, after the user chooses Update.
    }

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !appcastItem.isInformationOnlyUpdate else {
            super.showUpdateFound(with: appcastItem, state: state, reply: reply)
            return
        }

        let alert = NSAlert()
        alert.messageText = "VoiceShot \(appcastItem.displayVersionString) is available"
        let installMessage = "VoiceShot will download the update and restart when it’s ready."
        if appcastItem.itemDescriptionFormat == "plain-text",
           let notes = appcastItem.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            let summary = String(notes.prefix(280)) + (notes.count > 280 ? "…" : "")
            alert.informativeText = "What’s New\n\(summary)\n\n\(installMessage)"
        } else {
            alert.informativeText = installMessage
        }
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later").keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask me again"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            onOptOut?()
        }
        reply(response == .alertFirstButtonReturn ? .install : .dismiss)
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }
}
