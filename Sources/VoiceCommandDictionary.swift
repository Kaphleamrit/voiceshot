import Foundation

struct VoiceCommandDictionary {
    typealias Command = (target: CaptureTarget, delay: Double, trigger: String)

    private struct Entry {
        let target: CaptureTarget
        let trigger: String
    }

    private static let numbers = [
        ["one", "won"], ["two", "to", "too"], ["three", "tree"], ["four", "for", "fore"],
        ["five", "fife"], ["six", "sicks"], ["seven"], ["eight", "ate"], ["nine"], ["ten"]
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
    private static let compactPrefixes = ["snap", "snapp", "snup", "snep", "snaap"]
    private static let seconds: Set<String> = ["second", "seconds", "sec", "secs", "secons", "sekonds"]
    private static let separators = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted

    private static let shortBadgeCommands = ["nums", "tags", "badges", "labels",
                                             "show nums", "show tags", "show badges", "show labels"]

    private static let builtInEntries: [String: Entry] = {
        var entries: [String: Entry] = [:]
        func add(_ phrases: [String], target: CaptureTarget, trigger: String? = nil) {
            for phrase in phrases {
                entries[phrase] = Entry(target: target, trigger: trigger ?? phrase)
            }
        }

        add(["snap"], target: .allDisplays)
        add(["show numbers", "show window numbers", "show me numbers", "show me window numbers",
             "show the numbers", "show me the numbers", "show number", "show window number",
             "window numbers", "number the windows", "show windows", "number windows", "numbers"] + shortBadgeCommands,
            target: .showWindowNumbers)
        add(["screenshot text", "take screenshot text", "take a screenshot text",
             "copy text", "extract text", "read text", "read screen", "snap text"],
            target: .extractText)
        add(["screenshot area", "take screenshot area", "take a screenshot area", "screenshot selection",
             "crop screenshot", "select area", "crop screen", "snap area"],
            target: .interactiveArea)
        for (index, names) in numbers.enumerated() {
            let number = index + 1
            for value in [String(number)] + names {
                add(["snap", "snap window", "screenshot", "screenshot window", "window", "number", "window number",
                     "take screenshot", "take a screenshot"].map { "\($0) \(value)" },
                    target: .window(number), trigger: "snap\(number)")
                for prefix in ["display", "screen", "snap display", "snap screen", "screenshot display", "screenshot screen"] {
                    add(["\(prefix) \(value)"], target: .display(number), trigger: "display \(number)")
                }
            }
        }
        for app in apps {
            add(["snap", "screenshot", "take screenshot", "take a screenshot", "capture"].map { "\($0) \(app)" },
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
            if result.last == "screen", word == "shot" || word == "shoot" {
                result[result.count - 1] = word == "shot" ? "screenshot" : "screenshoot"
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
        let commands = ["numbers", "show numbers", "show windows", "snap text", "snap area", "copy text", "screenshot"] + shortBadgeCommands
        let numbered = numbers.enumerated().flatMap { index, names in
            ["snap \(index + 1)", "snap\(index + 1)", "snap \(names[0])", "number \(names[0])"]
        }
        var seen: Set<String> = []
        return Array((commands + numbered + triggerPhrases + Self.apps.map { "snap \($0)" })
            .filter { seen.insert($0.lowercased()).inserted }.prefix(100))
    }

    var maxWordCount: Int { max(Self.builtInIndex.maxWordCount, customIndex.maxWordCount) }

    func canStartCommand(_ word: String) -> Bool {
        Self.builtInIndex.firstWords.contains(word) || customIndex.firstWords.contains(word) ||
            Self.compactPrefixes.contains(word) || word == "screenshoot"
    }

    func hasCommandPrefix(_ words: ArraySlice<String>) -> Bool {
        let end = min(words.endIndex, words.startIndex + maxWordCount)
        return (words.startIndex + 1...end).contains { match(words[..<$0]) != nil }
    }

    static func badgeSelection(_ words: ArraySlice<String>) -> Command? {
        guard words.count == 1, let word = words.first, let number = numberValues[word] else { return nil }
        return (.window(number), 0, "snap\(number)")
    }

    func numberCommandAfterChatter(_ words: ArraySlice<String>) -> Int? {
        let earliest = max(words.startIndex + 1, words.endIndex - maxWordCount - 3)
        guard earliest < words.endIndex - 1 else { return nil }
        for index in (earliest..<(words.endIndex - 1)).reversed() {
            let target = words[index + 1]
            guard !words[..<index].suffix(4).contains(where: { ["not", "never", "don", "dont"].contains($0) }) else { continue }
            if words[index] == "show", match(words[index...])?.target == .showWindowNumbers { return index }
            if Self.compactPrefixes.contains(words[index]), target != "to", target != "for",
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
        if words.starts(with: ["can", "you"]) || words.starts(with: ["could", "you"]) {
            words = words.dropFirst(2)
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
        if let entry = Self.builtInIndex.phrases[phrase] ?? customIndex.phrases[phrase] {
            return (entry.target, entry.target == .showWindowNumbers ? 0 : delay, entry.trigger)
        }

        guard words.count > 1, words.count <= maxWordCount else { return nil }
        let keys = Index.deletionKeys(for: phrase, minimumWordLength: 3)
        let builtIn = Self.builtInIndex.nearMatches(phrase, keys: keys).sorted().compactMap { Self.builtInIndex.phrases[$0] }
        let custom = customIndex.nearMatches(phrase, keys: keys).sorted().compactMap { customIndex.phrases[$0] }
        let matches = builtIn + custom
        guard let entry = matches.first, matches.allSatisfy({ $0.target == entry.target }) else { return nil }
        return (entry.target, entry.target == .showWindowNumbers ? 0 : delay, entry.trigger)
    }

    static func endsWithSeconds(_ word: String?) -> Bool {
        word.map { seconds.contains($0) } ?? false
    }
}
