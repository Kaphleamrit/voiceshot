import Foundation

struct VoiceCommandDictionary {
    typealias Command = (target: CaptureTarget, delay: Double, trigger: String)

    private struct Entry {
        let target: CaptureTarget
        let trigger: String
    }

    private static let numbers = [
        ["one", "won", "wan", "wun"],
        ["two", "to", "too", "tou", "tew"],
        ["three", "tree", "free", "thre", "thee"],
        ["four", "for", "fore", "foor", "fohr"],
        ["five", "fife", "fyve", "faiv"],
        ["six", "sicks", "siks", "sixx"],
        ["seven", "sevin", "sevn", "sevan"],
        ["eight", "ate", "ait", "eyt", "eigt"],
        ["nine", "nain", "nien", "nyn"],
        ["ten", "tenn", "tehn"]
    ]
    private static let numberValues: [String: Int] = {
        var values: [String: Int] = [:]
        for (index, names) in numbers.enumerated() {
            for name in [String(index + 1)] + names { values[name] = index + 1 }
        }
        return values
    }()
    private static let apps = [
        "safari", "chrome", "slack", "terminal", "code", "cursor", "discord", "finder",
        "notes", "mail", "messages", "music", "spotify", "xcode", "preview", "pages",
        "numbers", "keynote", "telegram", "zoom", "notion", "figma", "arc", "firefox"
    ]
    private static let filler: Set<String> = ["please", "now", "then", "and", "hey", "voiceshot"]
    private static let snapWords: Set<String> = ["snap", "snapp", "snup", "snep", "snaap", "snaep",
                                                "snak", "snack", "snag", "snepp"]
    private static let compactPrefixes = ["snap"] + snapWords.subtracting(["snap"]).sorted()
    private static let seconds: Set<String> = ["second", "seconds", "sec", "secs", "secons", "sekonds",
                                              "sekund", "sekunds", "secunds", "segonds"]
    private static let separators = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted
    static let pasteSoundAlikes = [
        "paced", "past", "passed", "pastes", "pace", "pest", "piste",
        "baste", "based", "taste", "paist", "payst", "payste", "pased", "paysed", "payced",
        "pissed", "pierced", "best", "test", "peast", "pist", "paete", "paest", "peyst", "paeste"
    ]

    private static let badgeWords = ["numbers", "nums", "tags", "badges", "labels"]
    private static let badgeSpellings: [String: String] = [
        "numbrs": "numbers", "nummers": "numbers", "numz": "nums", "nummz": "nums",
        "tagz": "tags", "taggs": "tags", "badjez": "badges", "badjes": "badges", "badgez": "badges",
        "labelz": "labels", "laybels": "labels", "lables": "labels"
    ]
    private static let badgeSoundAlikes = ["numbs": "nums", "tax": "tags", "batches": "badges"]
    private static let splitLabelSoundAlike = ["lay", "bills"]
    private static let showWords: Set<String> = ["show", "sho", "shoh", "shwo", "shew"]
    private static let commandSpellings: [String: String] = [
        "screenshoot": "screenshot", "screenshut": "screenshot", "screenshort": "screenshot",
        "screenchot": "screenshot", "screanshot": "screenshot", "screenshots": "screenshot",
        "capchure": "capture", "captur": "capture", "kapture": "capture",
        "windo": "window", "windoh": "window", "windoe": "window", "windos": "windows",
        "displey": "display", "dissplay": "display", "moniter": "monitor", "monitore": "monitor",
        "xtract": "extract", "extrakt": "extract", "extrack": "extract", "exstract": "extract",
        "tekst": "text", "txet": "text", "tex": "text", "txt": "text",
        "aeria": "area", "areah": "area", "aria": "area",
        "safaree": "safari", "saphari": "safari", "krome": "chrome", "slak": "slack", "slaq": "slack"
    ]
    private static let badgeAliases = badgeSpellings.merging(badgeSoundAlikes) { canonical, _ in canonical }
    private static let bareBadgeCommands = Set(badgeWords + Array(badgeSpellings.keys))
    private static let textCommands = ["extract text", "copy text", "read text", "snap text", "get text"]

    private static let builtInEntries: [String: Entry] = {
        var entries: [String: Entry] = [:]
        func add(_ phrases: [String], target: CaptureTarget, trigger: String? = nil) {
            for phrase in phrases {
                entries[phrase] = Entry(target: target, trigger: trigger ?? phrase)
            }
        }

        add(["snap", "capture screen", "capture all screens", "capture all displays",
             "capture full screen", "full screen capture", "take a screen capture",
             "take a picture of the screen", "grab a screenshot"],
            target: .allDisplays)
        add(["paste"] + pasteSoundAlikes, target: .paste, trigger: "paste")
        add(["paste clipboard", "paste from clipboard", "paste the clipboard"], target: .paste, trigger: "paste")
        for word in badgeWords {
            add([word, "show \(word)", "show the \(word)", "show me \(word)", "show me the \(word)",
                 "show window \(word)", "window \(word)", "show me window \(word)", "show the window \(word)",
                 "show me the window \(word)"], target: .showWindowNumbers)
        }
        add(["show number", "show window number", "number the windows", "show windows", "show the windows",
             "show me the windows", "show me windows", "number windows",
             "label windows", "label the windows", "tag windows", "tag the windows"], target: .showWindowNumbers)
        add(["screenshot text", "take screenshot text", "take a screenshot text",
             "read screen", "read the screen", "copy screen text", "capture text"] + textCommands,
            target: .extractText)
        add(["screenshot area", "take screenshot area", "take a screenshot area", "screenshot selection",
             "crop screenshot", "select area", "crop screen", "snap area", "snap selection",
             "capture area", "capture selection", "select a region", "capture region", "snap region"],
            target: .interactiveArea)
        for (index, names) in numbers.enumerated() {
            let number = index + 1
            for value in [String(number)] + names {
                add(textCommands.flatMap { command in
                    ["", " from", " window", " from window"].map { "\(command)\($0) \(value)" }
                }, target: .extractWindowText(number), trigger: "extract text from \(number)")
                add(["snap", "snap window", "screenshot", "screenshot window", "window", "number", "window number",
                     "take screenshot", "take a screenshot", "capture", "capture window", "capture window number",
                     "snap window number", "capture the window", "snap the window"].map { "\($0) \(value)" },
                    target: .window(number), trigger: "snap\(number)")
                let displays = ["display", "screen", "monitor"]
                add(displays.flatMap { display in
                    ["", "snap ", "screenshot ", "capture "].map { "\($0)\(display) \(value)" }
                }, target: .display(number), trigger: "display \(number)")
            }
        }
        for app in apps {
            add(["snap", "screenshot", "take screenshot", "take a screenshot", "capture"].map { "\($0) \(app)" },
                target: .app(app), trigger: "snap \(app)")
        }
        for (alias, app) in [("google chrome", "chrome"), ("visual studio code", "code"),
                             ("vs code", "code"), ("fire fox", "firefox"), ("x code", "xcode")] {
            add(["snap", "screenshot", "take screenshot", "take a screenshot", "capture"].map { "\($0) \(alias)" },
                target: .app(app), trigger: "snap \(app)")
        }
        return entries
    }()

    private struct Index {
        let phrases: [String: Entry]
        private let deletions: [String: Set<String>]
        private let editablePhrases: Set<String>
        let maxWordCount: Int
        let firstWords: Set<String>

        init(_ phrases: [String: Entry]) {
            self.phrases = phrases
            var deletions: [String: Set<String>] = [:]
            var editablePhrases: Set<String> = []
            var maxWordCount = 0
            var firstWords: Set<String> = []
            for phrase in phrases.keys {
                let words = phrase.split(separator: " ")
                if let first = words.first { firstWords.insert(String(first)) }
                maxWordCount = max(maxWordCount, words.count)
                guard words.count > 1 else { continue }
                let keys = Self.deletionKeys(for: phrase, minimumWordLength: 4)
                if !keys.isEmpty { editablePhrases.insert(phrase) }
                for key in keys { deletions[key, default: []].insert(phrase) }
            }
            self.deletions = deletions
            self.editablePhrases = editablePhrases
            self.maxWordCount = maxWordCount
            self.firstWords = firstWords
        }

        func nearMatches(_ phrase: String, keys: [String]) -> Set<String> {
            var candidates = deletions[phrase] ?? []
            for key in keys {
                candidates.formUnion(deletions[key] ?? [])
                if editablePhrases.contains(key) { candidates.insert(key) }
            }
            return Set(candidates.filter { Self.isOneEdit(from: $0, to: phrase) })
        }

        static func deletionKeys(for phrase: String, minimumWordLength: Int) -> [String] {
            let bytes = Array(phrase.utf8)
            var keys: [String] = []
            var start = 0
            for end in 0...bytes.count where end == bytes.count || bytes[end] == 32 {
                if end - start >= minimumWordLength && bytes[start..<end].allSatisfy({ (97...122).contains($0) }) {
                    for position in start..<end {
                        var variant = bytes
                        variant.remove(at: position)
                        keys.append(String(decoding: variant, as: UTF8.self))
                    }
                }
                start = end + 1
            }
            return keys
        }

        private static func isOneEdit(from expected: String, to heard: String) -> Bool {
            let expectedWords = expected.split(separator: " ")
            let heardWords = heard.split(separator: " ")
            guard expectedWords.count == heardWords.count else { return false }
            var changed = false
            for (expectedWord, heardWord) in zip(expectedWords, heardWords) where expectedWord != heardWord {
                guard !changed, expectedWord.count >= 4,
                      expectedWord.utf8.allSatisfy({ (97...122).contains($0) }),
                      heardWord.utf8.allSatisfy({ (97...122).contains($0) }),
                      numberValues[String(expectedWord)] == nil else { return false }
                let a = Array(expectedWord.utf8)
                let b = Array(heardWord.utf8)
                switch a.count - b.count {
                case 0:
                    let differences = a.indices.filter { a[$0] != b[$0] }
                    guard differences.count == 1 ||
                            (differences.count == 2 && differences[1] == differences[0] + 1 &&
                             a[differences[0]] == b[differences[1]] && a[differences[1]] == b[differences[0]])
                    else { return false }
                case -1, 1:
                    let (longer, shorter) = a.count > b.count ? (a, b) : (b, a)
                    let firstMismatch = shorter.indices.first { longer[$0] != shorter[$0] } ?? shorter.count
                    guard longer.dropFirst(firstMismatch + 1).elementsEqual(shorter.dropFirst(firstMismatch)) else {
                        return false
                    }
                default:
                    return false
                }
                changed = true
            }
            return changed
        }
    }

    private static let builtInIndex = Index(builtInEntries)
    private let customIndex: Index

    init(triggerPhrases: [String]) {
        _ = Self.builtInIndex
        var phrases: [String: Entry] = [:]
        for trigger in triggerPhrases {
            let phrase = Self.words(in: trigger).joined(separator: " ")
            if !phrase.isEmpty { phrases[phrase] = Entry(target: .allDisplays, trigger: phrase) }
        }
        customIndex = Index(phrases)
    }

    static func words(in text: String) -> [String] {
        var result: [String] = []
        for word in text.lowercased().components(separatedBy: separators) where !word.isEmpty {
            if result.last == "screen", ["shot", "shoot", "shut", "short", "chot"].contains(word) {
                result[result.count - 1] = "screen" + word
                continue
            }
            var expanded = false
            for prefix in compactPrefixes where word.hasPrefix(prefix) {
                let suffix = String(word.dropFirst(prefix.count))
                if let number = numberValues[suffix] {
                    result.append(contentsOf: [prefix, String(number)])
                    expanded = true
                    break
                }
            }
            if !expanded { result.append(word) }
        }
        return result
    }

    static func recognitionHints(triggerPhrases: [String]) -> [String] {
        let commands = ["numbers", "show numbers", "show windows", "snap text", "snap area", "copy text",
                        "extract text", "screenshot", "paste", "please paste", "paste please",
                        "paste from clipboard", "capture window", "capture display", "capture screen",
                        "capture selection", "copy text from window"] +
                        badgeWords.flatMap { [$0, "show \($0)"] }
        let numbered = numbers.enumerated().flatMap { index, names in
            ["snap \(index + 1)", "snap\(index + 1)", "snap \(names[0])", "number \(names[0])",
             "extract text from \(names[0])"]
        }
        var seen: Set<String> = []
        return Array((commands + numbered + triggerPhrases + Self.apps.map { "snap \($0)" })
            .filter { seen.insert($0.lowercased()).inserted }.prefix(100))
    }

    var maxWordCount: Int { max(Self.builtInIndex.maxWordCount, customIndex.maxWordCount) }

    static func isSnapWord(_ word: String) -> Bool { snapWords.contains(word) }

    func canStartCommand(_ word: String) -> Bool {
        let canonical = Self.commandSpellings[word] ?? word
        return Self.builtInIndex.firstWords.contains(canonical) || customIndex.firstWords.contains(canonical) ||
            Self.snapWords.contains(word) || Self.showWords.contains(word) || Self.bareBadgeCommands.contains(word)
    }

    func hasCommandPrefix(_ words: ArraySlice<String>) -> Bool {
        guard !words.isEmpty else { return false }
        let end = min(words.endIndex, words.startIndex + maxWordCount)
        return (words.startIndex + 1...end).contains { match(words[..<$0]) != nil }
    }

    static func badgeSelection(_ words: ArraySlice<String>) -> Command? {
        guard words.count == 1, let word = words.first, let number = numberValues[word] else { return nil }
        return (.window(number), 0, "snap\(number)")
    }

    func badgeCommandAfterChatter(_ words: ArraySlice<String>) -> Int? {
        let lastBadge = words.lastIndex { Self.bareBadgeCommands.contains($0) }
        guard let lastBadge else { return nil }
        for index in words.indices.dropFirst() where index <= lastBadge {
            let following = words[(index + 1)...]
            guard Self.bareBadgeCommands.contains(words[index]),
                  index < lastBadge || following.isEmpty || hasCommandPrefix(following),
                  !words[..<index].suffix(4).contains(where: { ["not", "never", "don", "dont"].contains($0) }),
                  !["the", "these", "those", "my", "your"].contains(words[index - 1]),
                  match(words[(index - 1)...index])?.target != .app("numbers") else { continue }
            return index
        }
        return nil
    }

    func numberCommandAfterChatter(_ words: ArraySlice<String>) -> Int? {
        let earliest = max(words.startIndex + 1, words.endIndex - maxWordCount - 3)
        guard earliest < words.endIndex - 1 else { return nil }
        for index in (earliest..<(words.endIndex - 1)).reversed() {
            let target = words[index + 1]
            guard !words[..<index].suffix(4).contains(where: { ["not", "never", "don", "dont"].contains($0) }) else { continue }
            let first = words[index]
            let canonical = Self.commandSpellings[first] ?? first
            if Self.showWords.contains(first), match(words[index...])?.target == .showWindowNumbers { return index }
            if ["extract", "copy", "read", "get"].contains(canonical) || Self.snapWords.contains(first),
               let command = match(words[index...]),
               case .extractWindowText = command.target { return index }
            if Self.snapWords.contains(first), target != "to", target != "for",
               let command = match(words[index...]), case .window = command.target { return index }
        }
        return nil
    }

    func match(_ transcript: ArraySlice<String>) -> Command? {
        if transcript.count <= customIndex.maxWordCount {
            let raw = transcript.joined(separator: " ")
            if Self.builtInIndex.phrases[raw] == nil, let entry = customIndex.phrases[raw] {
                return (entry.target, 0, entry.trigger)
            }
        }
        var words = transcript
        while let first = words.first, Self.filler.contains(first) { words = words.dropFirst() }
        if words.starts(with: ["can", "you"]) || words.starts(with: ["could", "you"]) ||
            words.starts(with: ["would", "you"]) {
            words = words.dropFirst(2)
            while let first = words.first, Self.filler.contains(first) { words = words.dropFirst() }
        }
        while let last = words.last, Self.filler.contains(last) { words = words.dropLast() }
        guard !words.isEmpty, words.count <= maxWordCount + 3 else { return nil }

        var delay: Double = 0
        if let index = words.lastIndex(of: "in"), index > words.startIndex, index + 1 < words.endIndex,
           let number = Self.numberValues[words[index + 1]],
           index + 2 == words.endIndex ||
               (index + 3 == words.endIndex && Self.seconds.contains(words[index + 2])) {
            delay = Double(number)
            words = words[..<index]
        }

        let phrase = words.joined(separator: " ")
        let exact = Self.builtInIndex.phrases[phrase] ?? customIndex.phrases[phrase]
        let corrected = exact == nil ? Self.correctedPhrase(words) : phrase
        if let entry = exact ?? Self.builtInIndex.phrases[corrected] ?? customIndex.phrases[corrected] {
            if entry.target == .paste && delay > 0 { return nil }
            return (entry.target, entry.target == .showWindowNumbers ? 0 : delay, entry.trigger)
        }

        guard words.count > 1, words.count <= maxWordCount else { return nil }
        let keys = Index.deletionKeys(for: corrected, minimumWordLength: 3)
        let builtIn = Self.builtInIndex.nearMatches(corrected, keys: keys).sorted().compactMap { Self.builtInIndex.phrases[$0] }
        let custom = customIndex.nearMatches(corrected, keys: keys).sorted().compactMap { customIndex.phrases[$0] }
        let matches = builtIn + custom
        guard let entry = matches.first, matches.allSatisfy({ $0.target == entry.target }) else { return nil }
        if entry.target == .paste && delay > 0 { return nil }
        return (entry.target, entry.target == .showWindowNumbers ? 0 : delay, entry.trigger)
    }

    private static func correctedPhrase(_ words: ArraySlice<String>) -> String {
        var corrected = words.map { commandSpellings[$0] ?? $0 }
        let last = corrected.count - 1
        if corrected.count > 1, snapWords.contains(corrected[0]) {
            corrected[0] = "snap"
        }
        if corrected.count > 1, showWords.contains(corrected[0]) {
            corrected[0] = "show"
            if corrected.suffix(2).elementsEqual(splitLabelSoundAlike) {
                corrected.replaceSubrange((last - 1)...last, with: ["labels"])
            } else if let badge = badgeAliases[corrected[last]] {
                corrected[last] = badge
            }
        } else if (corrected.count == 1 || corrected[0] == "window"),
                  let badge = badgeSpellings[corrected[last]] {
            corrected[last] = badge
        } else if corrected.last == "clipboard", pasteSoundAlikes.contains(corrected[0]) {
            corrected[0] = "paste"
        }
        return corrected.joined(separator: " ")
    }

    static func isBadgeSoundAlike(_ words: ArraySlice<String>) -> Bool {
        let phrase = words.reversed().drop(while: { filler.contains($0) })
        return phrase.first.map { badgeSoundAlikes[$0] != nil } == true ||
            phrase.prefix(2).elementsEqual(splitLabelSoundAlike.reversed())
    }

    static func endsWithSeconds(_ word: String?) -> Bool {
        word.map { seconds.contains($0) } ?? false
    }
}
