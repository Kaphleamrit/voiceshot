import AppKit
import CoreGraphics
import Foundation

struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let number: Int
    let appName: String
    let title: String
    let visibleBounds: CGRect
}

final class WindowManager {
    static let shared = WindowManager()
    private static let badgeInactivityInterval: TimeInterval = 15 * 60

    private var badgeWindows: [NSWindow] = []
    private var badgeTimer: Timer?
    private var badgeTargets: [WindowItem] = []
    private var numberingTimer: Timer?
    private var lastWindowIDs: [CGWindowID]?
    private var lastCommandTime = ProcessInfo.processInfo.systemUptime
    private var automaticBadgesPaused = false

    private init() {}

    /// Numbers the normal windows with an exposed region on an active display.
    func getVisibleWindows(limit: Int = 10) -> [WindowItem] {
        onScreenWindows(limit: limit, onlyExposed: true)
    }

    private func onScreenWindows(limit: Int, onlyExposed: Bool) -> [WindowItem] {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success, count > 0 else { return [] }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return Self.numberVisibleWindows(list, displays: displays.prefix(Int(count)).map { CGDisplayBounds($0) },
                                         excluding: ProcessInfo.processInfo.processIdentifier, limit: limit,
                                         onlyExposed: onlyExposed)
    }

    static func numberVisibleWindows(_ list: [[String: Any]], displays: [CGRect],
                                     excluding ownPID: pid_t, limit: Int, onlyExposed: Bool = true) -> [WindowItem] {
        guard limit > 0 else { return [] }
        var result: [WindowItem] = []
        var covered: [CGRect] = []
        let ignoredOwners: Set<String> = ["WindowServer", "Dock", "universalAccessAuthWarn", "loginwindow"]

        for info in list {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID, id != 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  !bounds.isEmpty else { continue }

            let owner = info[kCGWindowOwnerName as String] as? String ?? "Window"
            guard !ignoredOwners.contains(owner) else { continue }
            var visible = displays.map { $0.intersection(bounds) }.filter { !$0.isEmpty }
            for occluder in covered {
                visible = visible.flatMap { subtract(occluder, from: $0) }
                if visible.isEmpty { break }
            }
            guard let mostVisible = visible.max(by: { $0.width * $0.height < $1.width * $1.height }) else { continue }

            // Use fully opaque normal window bounds for occlusion. Translucent windows can reveal those below.
            if onlyExposed, alpha >= 1 { covered.append(contentsOf: visible) }
            guard owner != "VoiceShot", info[kCGWindowOwnerPID as String] as? pid_t != ownPID else { continue }
            result.append(WindowItem(id: id, number: result.count + 1, appName: owner,
                                     title: info[kCGWindowName as String] as? String ?? "", visibleBounds: mostVisible))
            if result.count == limit { break }
        }
        return result
    }

    private static func subtract(_ cover: CGRect, from bounds: CGRect) -> [CGRect] {
        let overlap = bounds.intersection(cover)
        guard !overlap.isEmpty else { return [bounds] }
        return [
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: overlap.minY - bounds.minY),
            CGRect(x: bounds.minX, y: overlap.maxY, width: bounds.width, height: bounds.maxY - overlap.maxY),
            CGRect(x: bounds.minX, y: overlap.minY, width: overlap.minX - bounds.minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: bounds.maxX - overlap.maxX, height: overlap.height)
        ].filter { !$0.isEmpty }
    }

    /// Looks up window by assigned number (1, 2, 3, 4, 5...)
    func window(forNumber number: Int) -> WindowItem? {
        guard (1...10).contains(number) else { return nil }
        return getVisibleWindows(limit: number).last.flatMap { $0.number == number ? $0 : nil }
    }

    /// Looks up window by application name (e.g. "Safari", "Slack", "Chrome")
    func window(forApp query: String) -> WindowItem? {
        let clean = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let alternateNames = [
            "chrome": ["google chrome"],
            "code": ["visual studio code"],
            "zoom": ["zoom.us", "zoom workplace"]
        ]
        let names = [clean] + (alternateNames[clean] ?? [])
        return onScreenWindows(limit: .max, onlyExposed: false).first { names.contains($0.appName.lowercased()) }
    }

    // MARK: - Visual Window Number Overlays

    func startMonitoringWindowNumbers() {
        guard numberingTimer == nil else { return }
        recordCommandActivity()
        lastWindowIDs = getVisibleWindows().map(\.id)
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateAutomaticBadges()
        }
        timer.tolerance = 0.1
        numberingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func recordCommandActivity() {
        lastCommandTime = ProcessInfo.processInfo.systemUptime
    }

    private func updateAutomaticBadges() {
        if PreferencesManager.shared.hideInactiveWindowBadges,
           ProcessInfo.processInfo.systemUptime - lastCommandTime >= Self.badgeInactivityInterval {
            guard lastWindowIDs != nil else { return }
            // Forget the last set so the first command refreshes even unchanged numbers.
            lastWindowIDs = nil
            dismissBadges()
            return
        }
        guard !automaticBadgesPaused, !hasBadgeTargets else { return }
        let windows = getVisibleWindows()
        let windowIDs = windows.map(\.id)
        guard windowIDs != lastWindowIDs else { return }

        lastWindowIDs = windowIDs
        dismissBadges()
        displayBadges(for: windows, duration: 1.25)
    }

    /// Places badges on the exposed part of each numbered window.
    func showWindowBadges(duration: TimeInterval = 4.0) {
        recordCommandActivity()
        dismissBadges()
        let windows = getVisibleWindows()
        lastWindowIDs = windows.map(\.id)
        badgeTargets = windows
        displayBadges(for: windows, duration: duration)
    }

    private func displayBadges(for windows: [WindowItem], duration: TimeInterval) {
        guard !windows.isEmpty else { return }
        let mainScreenHeight = CGDisplayBounds(CGMainDisplayID()).height

        for item in windows {
            let visible = item.visibleBounds
            let badgeWidth = min(52, visible.width)
            let badgeHeight = min(34, visible.height)
            let badgeX = visible.minX + min(18, visible.width - badgeWidth)
            let badgeY = mainScreenHeight - visible.minY - badgeHeight - min(12, visible.height - badgeHeight)

            let window = NSWindow(
                contentRect: NSRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hasShadow = true
            window.ignoresMouseEvents = true

            let container = NSView(frame: NSRect(x: 0, y: 0, width: badgeWidth, height: badgeHeight))
            container.wantsLayer = true
            container.layer?.cornerRadius = 8
            container.layer?.masksToBounds = true
            container.layer?.backgroundColor = NSColor(red: 0.08, green: 0.44, blue: 0.98, alpha: 0.95).cgColor
            container.layer?.borderWidth = 1.5
            container.layer?.borderColor = NSColor.white.cgColor

            let label = NSTextField(labelWithString: "\(item.number)")
            let fontSize = max(1, min(18, badgeHeight * 0.55, badgeWidth * 0.43))
            label.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy)
            label.textColor = .white
            label.alignment = .center
            let labelHeight = min(badgeHeight, label.intrinsicContentSize.height)
            label.frame = NSRect(x: 0, y: (badgeHeight - labelHeight) / 2, width: badgeWidth, height: labelHeight)
            container.addSubview(label)

            window.contentView = container
            window.alphaValue = 0.0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1.0
            }

            self.badgeWindows.append(window)
        }

        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismissBadges()
        }
        badgeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    var hasBadgeTargets: Bool { !badgeTargets.isEmpty }

    /// Full-screen and area captures need to keep automatic overlays hidden until the capture ends.
    func setAutomaticBadgesPausedForCapture(_ paused: Bool) {
        automaticBadgesPaused = paused
        if paused { hideBadgesForCapture() }
    }

    /// Hides badge overlays while preserving number assignments until the badge session expires.
    @discardableResult
    func hideBadgesForCapture() -> [WindowItem] {
        for window in badgeWindows { window.orderOut(nil) }
        badgeWindows.removeAll(keepingCapacity: true)
        return badgeTargets
    }

    private func dismissBadges() {
        badgeTargets.removeAll(keepingCapacity: true)
        badgeTimer?.invalidate()
        badgeTimer = nil
        hideBadgesForCapture()
    }
}
