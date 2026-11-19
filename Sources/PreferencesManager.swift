import Foundation

final class PreferencesManager {
    static let shared = PreferencesManager()
    
    private let defaults: UserDefaults
    
    private enum Keys {
        static let saveFolderPath = "voiceshot.saveFolderPath"
        static let playShutterSound = "voiceshot.playShutterSound"
        static let flashScreen = "voiceshot.flashScreen"
        static let showNotification = "voiceshot.showNotification"
        static let delayBeforeCapture = "voiceshot.delayBeforeCapture"
        static let includeCursor = "voiceshot.includeCursor"
        static let copyToClipboard = "voiceshot.copyToClipboard"
        static let showFloatingPreview = "voiceshot.showFloatingPreview"
        static let spokenFeedback = "voiceshot.spokenFeedback"
        static let triggerPhrases = "voiceshot.triggerPhrases"
        static let isListeningEnabled = "voiceshot.isListeningEnabled"
        static let automaticListeningBreaks = "voiceshot.automaticListeningBreaks"
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }
    
    private func registerDefaults() {
        let defaultDesktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? ("~/Desktop" as NSString).expandingTildeInPath
        let defaultTriggers = ["take screenshot", "take a screenshot", "screenshot", "capture screen"]
        
        defaults.register(defaults: [
            Keys.saveFolderPath: defaultDesktop,
            Keys.playShutterSound: true,
            Keys.flashScreen: true,
            Keys.showNotification: true,
            Keys.delayBeforeCapture: 0.0,
            Keys.includeCursor: false,
            Keys.copyToClipboard: true,
            Keys.showFloatingPreview: true,
            Keys.spokenFeedback: false,
            Keys.triggerPhrases: defaultTriggers,
            Keys.isListeningEnabled: true,
            Keys.automaticListeningBreaks: true
        ])
    }
    
    var saveFolderPath: String {
        get { defaults.string(forKey: Keys.saveFolderPath) ?? ("~/Desktop" as NSString).expandingTildeInPath }
        set { defaults.set(newValue, forKey: Keys.saveFolderPath) }
    }
    
    var playShutterSound: Bool {
        get { defaults.bool(forKey: Keys.playShutterSound) }
        set { defaults.set(newValue, forKey: Keys.playShutterSound) }
    }
    
    var flashScreen: Bool {
        get { defaults.bool(forKey: Keys.flashScreen) }
        set { defaults.set(newValue, forKey: Keys.flashScreen) }
    }
    
    var showNotification: Bool {
        get { defaults.bool(forKey: Keys.showNotification) }
        set { defaults.set(newValue, forKey: Keys.showNotification) }
    }
    
    var delayBeforeCapture: Double {
        get { defaults.double(forKey: Keys.delayBeforeCapture) }
        set { defaults.set(newValue, forKey: Keys.delayBeforeCapture) }
    }
    
    var includeCursor: Bool {
        get { defaults.bool(forKey: Keys.includeCursor) }
        set { defaults.set(newValue, forKey: Keys.includeCursor) }
    }
    
    var saveLocally: Bool {
        get { defaults.bool(forKey: "voiceshot.saveLocally") }
        set { defaults.set(newValue, forKey: "voiceshot.saveLocally") }
    }

    var copyToClipboard: Bool {
        get { !saveLocally || defaults.bool(forKey: Keys.copyToClipboard) }
        set { defaults.set(newValue, forKey: Keys.copyToClipboard) }
    }
    
    var showFloatingPreview: Bool {
        get { defaults.bool(forKey: Keys.showFloatingPreview) }
        set { defaults.set(newValue, forKey: Keys.showFloatingPreview) }
    }
    
    var spokenFeedback: Bool {
        get { defaults.bool(forKey: Keys.spokenFeedback) }
        set { defaults.set(newValue, forKey: Keys.spokenFeedback) }
    }
    
    var triggerPhrases: [String] {
        get {
            defaults.stringArray(forKey: Keys.triggerPhrases) ?? ["take screenshot", "take a screenshot", "screenshot", "capture screen"]
        }
        set {
            defaults.set(newValue, forKey: Keys.triggerPhrases)
        }
    }
    
    var isListeningEnabled: Bool {
        get { defaults.bool(forKey: Keys.isListeningEnabled) }
        set { defaults.set(newValue, forKey: Keys.isListeningEnabled) }
    }

    var automaticListeningBreaks: Bool {
        get { defaults.bool(forKey: Keys.automaticListeningBreaks) }
        set { defaults.set(newValue, forKey: Keys.automaticListeningBreaks) }
    }
}
