import AppKit
import CoreGraphics
import Foundation

struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let number: Int
    let appName: String
    let title: String
    let bounds: CGRect
}

final class WindowManager {
    static let shared = WindowManager()
    
    private var badgeWindows: [NSWindow] = []
    private var badgeTimer: Timer?
    
    private init() {}
    
    /// Queries Quartz Window Services for on-screen application windows and numbers them 1, 2, 3, 4, 5...
    func getVisibleWindows() -> [WindowItem] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        var result: [WindowItem] = []
        var number = 1
        
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard bounds.width > 150 && bounds.height > 150 else { continue }
            
            let owner = info[kCGWindowOwnerName as String] as? String ?? "Window"
            let title = info[kCGWindowName as String] as? String ?? ""
            if owner == "VoiceShot" || owner == "WindowServer" || owner == "Dock" || owner == "universalAccessAuthWarn" {
                continue
            }
            
            let id = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            guard id != 0 else { continue }
            
            result.append(WindowItem(id: id, number: number, appName: owner, title: title, bounds: bounds))
            number += 1
            if number > 10 { break } // Support up to top 10 windows
        }
        return result
    }
    
    /// Looks up window by assigned number (1, 2, 3, 4, 5...)
    func window(forNumber number: Int) -> WindowItem? {
        let windows = getVisibleWindows()
        return windows.first { $0.number == number }
    }
    
    /// Looks up window by application name (e.g. "Safari", "Slack", "Chrome")
    func window(forApp query: String) -> WindowItem? {
        let clean = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let windows = getVisibleWindows()
        return windows.first {
            $0.appName.lowercased().contains(clean) || (!clean.isEmpty && $0.title.lowercased().contains(clean))
        }
    }
    
    // MARK: - Visual Window Number Overlays
    
    /// Displays floating numbered badges [ 1 ], [ 2 ], [ 3 ]... over the top-left of each open window
    func showWindowBadges(duration: TimeInterval = 4.0) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dismissBadges()
            
            let windows = self.getVisibleWindows()
            guard !windows.isEmpty else { return }
            
            let mainScreenHeight = NSScreen.main?.frame.height ?? 1080
            
            for item in windows {
                let badgeWidth: CGFloat = 52
                let badgeHeight: CGFloat = 34
                
                // Convert top-left Quartz coords to bottom-left Cocoa coords
                let cocoaY = mainScreenHeight - (item.bounds.origin.y + item.bounds.height)
                let badgeX = item.bounds.origin.x + 18
                let badgeY = cocoaY + item.bounds.height - badgeHeight - 12
                
                let window = NSWindow(
                    contentRect: NSRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = false
                window.backgroundColor = .clear
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
                label.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .heavy)
                label.textColor = .white
                label.alignment = .center
                label.frame = NSRect(x: 0, y: 5, width: badgeWidth, height: 24)
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
            
            self.badgeTimer?.invalidate()
            self.badgeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.dismissBadges()
            }
        }
    }
    
    /// Hides and destroys all active badge overlay windows
    func dismissBadges() {
        badgeTimer?.invalidate()
        badgeTimer = nil
        
        for w in badgeWindows {
            w.orderOut(nil)
        }
        badgeWindows.removeAll()
    }
}
