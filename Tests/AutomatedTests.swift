import AppKit
import CoreGraphics
import Foundation

@main
struct VoiceShotTests {
    static var passed = 0
    static var failed = 0

    static func assertTest(_ condition: Bool, _ testName: String) {
        if condition {
            print("  ✅ [PASS] \(testName)")
            passed += 1
        } else {
            print("  ❌ [FAIL] \(testName)")
            failed += 1
        }
    }

    static func main() {
        print("========================================")
        print("🧪 Running VoiceShot Numbered Window & 'snap1' Test Suite")
        print("========================================")

        let suite = "VoiceShotTests." + UUID().uuidString
        let isolatedDefaults = UserDefaults(suiteName: suite)!
        defer { isolatedDefaults.removePersistentDomain(forName: suite) }
        let prefs = PreferencesManager(defaults: isolatedDefaults)
        assertTest(!prefs.saveLocally && prefs.copyToClipboard, "New installs capture to clipboard only")
        prefs.copyToClipboard = false
        assertTest(prefs.copyToClipboard, "A previous copy preference cannot discard clipboard-only captures")
        prefs.saveLocally = true
        assertTest(PreferencesManager(defaults: isolatedDefaults).saveLocally && !prefs.copyToClipboard, "Save-only opt-in persists")
        prefs.saveLocally = false
        assertTest(prefs.copyToClipboard, "Turning local saving off restores clipboard capture")
        assertTest(prefs.automaticListeningBreaks, "Automatic listening breaks are enabled by default")
        prefs.automaticListeningBreaks = false
        assertTest(!PreferencesManager(defaults: isolatedDefaults).automaticListeningBreaks,
                   "Disabling automatic breaks persists")
        assertTest(SpeechRecognizer.containsWakePhrase("Wake up!"), "Wake phrase accepts case and punctuation")
        assertTest(SpeechRecognizer.containsWakePhrase("Background speech. Wake up."),
                   "A separate wake utterance can follow other speech")
        assertTest(!SpeechRecognizer.containsWakePhrase("snap one") &&
                   !SpeechRecognizer.containsWakePhrase("I wake up early"),
                   "Capture commands and conversation are ignored during a break")

        // TEST 1: Window Number & Snap Tokens Parser
        let testCases: [(spoken: String, expectedTarget: CaptureTarget, desc: String)] = [
            // "screenshot N" -> Window N
            ("screenshot 1", .window(1), "screenshot 1 -> Window 1"),
            ("screenshot 2", .window(2), "screenshot 2 -> Window 2"),
            ("screenshot 3", .window(3), "screenshot 3 -> Window 3"),
            ("screenshot 4", .window(4), "screenshot 4 -> Window 4"),
            ("screenshot 5", .window(5), "screenshot 5 -> Window 5"),
            
            // "snapN" -> Window N
            ("snap1", .window(1), "snap1 -> Window 1"),
            ("snap2", .window(2), "snap2 -> Window 2"),
            ("snap3", .window(3), "snap3 -> Window 3"),
            ("snap4", .window(4), "snap4 -> Window 4"),
            ("snap5", .window(5), "snap5 -> Window 5"),
            ("snap10", .window(10), "snap10 -> Window 10"),
            
            // Spaced "snap N" -> Window N
            ("snap 1", .window(1), "snap 1 -> Window 1"),
            ("snap 2", .window(2), "snap 2 -> Window 2"),
            ("snap 3", .window(3), "snap 3 -> Window 3"),
            ("Snap TWO!", .window(2), "Snap TWO! -> Window 2"),
            ("SNAP-3", .window(3), "SNAP-3 -> Window 3"),
            ("snap\tten", .window(10), "snap followed by a tab and ten -> Window 10"),
            ("snap window six", .window(6), "snap window six -> Window 6"),
            ("screen shot seven", .window(7), "screen shot seven -> Window 7"),
            
            // Explicit Display & Window
            ("display 1", .display(1), "display 1 -> Display 1"),
            ("display 2", .display(2), "display 2 -> Display 2"),
            ("window 1", .window(1), "window 1 -> Window 1"),
            
            // Visual Overlay Badges Command
            ("show window numbers", .showWindowNumbers, "show window numbers"),
            ("show numbers", .showWindowNumbers, "show numbers"),
            ("show windows", .showWindowNumbers, "show windows"),
            
            // General
            ("take screenshot", .allDisplays, "take screenshot -> All Displays"),
            ("snap", .allDisplays, "snap -> All Displays"),
            ("snap Safari", .app("safari"), "snap Safari -> Safari"),
            ("snap Numbers", .app("numbers"), "snap Numbers -> Numbers"),
            ("snap text", .extractText, "snap text -> OCR"),
            ("extract text", .extractText, "extract text -> OCR"),
            ("extract text from 1", .extractWindowText(1), "extract text from 1 -> Window 1 OCR"),
            ("extract text two", .extractWindowText(2), "extract text two -> Window 2 OCR"),
            ("extract test from two", .extractWindowText(2), "Transcribed extract test -> Window 2 OCR"),
            ("extract text from window ten", .extractWindowText(10), "extract text from window ten -> Window 10 OCR"),
            ("paste", .paste, "paste -> Paste Clipboard"),
            ("snap area", .interactiveArea, "snap area -> Selection Area")
        ]

        for tc in testCases {
            if let result = SpeechRecognizer.parseTarget(spoken: tc.spoken) {
                assertTest(result.target == tc.expectedTarget, tc.desc)
                if case .window(let number) = tc.expectedTarget {
                    assertTest(result.trigger == "snap\(number)", "\(tc.spoken) displays as snap\(number)")
                }
            } else {
                assertTest(false, "\(tc.desc) (failed to match)")
            }
        }

        for phrase in ["ss1", "ss 2", "s3", "snap0", "snap 0", "snap11", "snap 11", "snapshot"] {
            assertTest(SpeechRecognizer.parseTarget(spoken: phrase) == nil, "\(phrase) is ignored")
        }

        for n in 1...10 {
            var selection = SpeechRecognizer.CommandStream()
            assertTest(selection.commands(in: "\(n)", settled: true).isEmpty, "Ignore standalone \(n) outside selection")
            assertTest(selection.commands(in: "\(n)", settled: true, badgesActive: true).map(\.target) == [.window(n)], "Select badge \(n)")
        }
        for phrase in ["show numbers three", "show me the numbers. Tree.", "show numbers then three"] {
            var selection = SpeechRecognizer.CommandStream()
            assertTest(selection.commands(in: phrase, settled: true).map(\.target) == [.showWindowNumbers, .window(3)], phrase)
        }
        let hints = VoiceCommandDictionary.recognitionHints(triggerPhrases: [])
        assertTest(hints.contains("paste") && hints.contains("please paste"), "Speech recognition receives paste hints")
        for phrase in ["Past.", "passed", "paced", "pace", "pest", "piste", "baste", "based",
                       "taste", "pastes", "paist", "payst", "payste", "pased", "paysed", "payced"] {
            let command = SpeechRecognizer.parseTarget(spoken: phrase)
            assertTest(command?.target == .paste && command?.trigger == "paste", "Paste sound-alike: \(phrase)")
        }
        for phrase in ["do not paste", "paste it here", "paste in two seconds", "do not baste",
                       "in the past", "based on this", "taste the soup", "passed in two seconds"] {
            assertTest(SpeechRecognizer.parseTarget(spoken: phrase) == nil, "Does not send a paste shortcut for: \(phrase)")
        }
        assertTest(hints.contains("extract text from one") && hints.contains("extract text from ten"),
                   "Speech recognition receives numbered text extraction hints")
        assertTest(SpeechRecognizer.parseTarget(spoken: "extract text from eleven") == nil,
                   "An unsupported OCR window number does not fall back to full-screen OCR")
        for word in ["numbers", "nums", "tags", "badges", "labels"] {
            for alias in [word, "show " + word] {
                var stream = SpeechRecognizer.CommandStream()
                assertTest(hints.contains(alias), "Recognition hint for \(alias)")
                assertTest(stream.commands(in: alias, settled: false).map(\.target) == [.showWindowNumbers], "Show badges immediately for \(alias)")
                assertTest(stream.commands(in: alias + " two", settled: true, badgesActive: true).map(\.target) == [.window(2)], "Select two after \(alias) without repeating badges")
            }
        }
        for alias in ["nums", "numbers"] {
            var stream = SpeechRecognizer.CommandStream()
            let show = stream.commands(in: alias, settled: false)
            let repeatShow = stream.commands(in: "\(alias) two \(alias)", settled: false, badgesActive: true)
            assertTest((show + repeatShow).map(\.target) == [.showWindowNumbers, .window(2), .showWindowNumbers],
                       "A badge selection followed by \(alias) reopens the badges in one transcript")
            assertTest(stream.commands(in: "\(alias) two \(alias).", settled: true, badgesActive: true).isEmpty,
                       "A final transcription does not repeat the commands")
            assertTest(stream.commands(in: "\(alias) two \(alias). \(alias).", settled: false).map(\.target) == [.showWindowNumbers],
                       "Repeating \(alias) after the badges expire shows them again")
        }
        for alias in ["numbers", "nums", "tags", "badges", "labels", "show numbers", "show tags"] {
            var stream = SpeechRecognizer.CommandStream()
            var emitted = 0
            for index in 0..<20 {
                let start = Double(index)
                _ = stream.beginFreshUtterance(alias, start: start, end: start + 0.4)
                emitted += stream.commands(in: alias, settled: false).count
                _ = stream.beginFreshUtterance(alias, start: start, end: start + 0.5)
                emitted += stream.commands(in: alias, settled: true).count
            }
            assertTest(emitted == 20, "Twenty distinct utterances of \(alias) each trigger once")

            stream = SpeechRecognizer.CommandStream()
            let burst = Array(repeating: alias, count: 20).joined(separator: " ")
            assertTest(stream.commands(in: burst, settled: false).map(\.target) ==
                       Array(repeating: .showWindowNumbers, count: 20), "Recognize every \(alias) in a single burst")
        }
        for phrase in ["the price tags fell", "read the labels", "those badges are blue"] {
            var stream = SpeechRecognizer.CommandStream()
            assertTest(stream.commands(in: phrase, settled: true).isEmpty, "Ignore ordinary speech: \(phrase)")
        }
        var chatter = SpeechRecognizer.CommandStream()
        assertTest(chatter.commands(in: "okay show the numbers", settled: true).map(\.target) == [.showWindowNumbers], "Recover badge command after chatter")
        let reportedTranscript = "Tags snap1 text text nums text numbers numbers numbers numbers tags numbers tags badges numb nums"
        let expectedCommands: [CaptureTarget] = [.showWindowNumbers, .window(1)] +
            Array(repeating: .showWindowNumbers, count: 10)
        var reportedStream = SpeechRecognizer.CommandStream()
        assertTest(reportedStream.commands(in: reportedTranscript, settled: false).map(\.target) == expectedCommands,
                   "Unpunctuated live transcript recovers every badge command and the snap")
        assertTest(reportedStream.commands(in: reportedTranscript + ".", settled: true).isEmpty,
                   "Finalizing the live transcript does not rerun handled commands")
        reportedStream = SpeechRecognizer.CommandStream()
        var partial = ""
        let liveCommands = reportedTranscript.split(separator: " ").flatMap { word in
            partial += " " + word
            return reportedStream.commands(in: partial, settled: false).map(\.target)
        }
        assertTest(liveCommands == expectedCommands, "Growing partial transcripts keep responding after unrecognized words")
        reportedStream = SpeechRecognizer.CommandStream()
        assertTest(reportedStream.commands(in: "text nums snap1", settled: true).map(\.target) ==
                   [.showWindowNumbers, .window(1)], "A badge after chatter still runs before the next snap")

        let pronunciationCases: [(String, CaptureTarget)] = [
            ("snup won", .window(1)), ("snap too", .window(2)), ("snapp tree", .window(3)),
            ("snap for", .window(4)), ("snap fife", .window(5)), ("snap sicks", .window(6)),
            ("snapp8", .window(8)), ("take a screenshot ten", .window(10)),
            ("snap Safary", .app("safari")), ("screenshot Safrai", .app("safari")),
            ("screenshoot Text", .extractText), ("snap aera", .interactiveArea),
            ("show numbrs", .showWindowNumbers), ("display tree", .display(3)),
            ("take screenshoot", .allDisplays)
        ]
        for (spoken, target) in pronunciationCases {
            assertTest(SpeechRecognizer.parseTarget(spoken: spoken)?.target == target,
                       "Pronunciation match: \(spoken) -> \(target)")
        }
        for spoken in ["snap to it", "the snap tree fell", "snap something", "snup", "display eleven",
                       "screenshot unknown", "take a screenshot of the report"] {
            assertTest(SpeechRecognizer.parseTarget(spoken: spoken) == nil, "Unclear phrase is ignored: \(spoken)")
        }
        assertTest(SpeechRecognizer.parseTarget(spoken: "grab the frmae", triggerPhrases: ["grab the frame"])?.target
                   == .allDisplays, "Multiword custom triggers support conservative corrections")
        assertTest(SpeechRecognizer.parseTarget(spoken: "snap aera", triggerPhrases: ["snap aeta"]) == nil,
                   "Conflicting nearby commands are ignored")
        assertTest(SpeechRecognizer.parseTarget(spoken: "snap area", triggerPhrases: ["snap aera"])?.target
                   == .interactiveArea, "An exact command wins over a nearby custom trigger")

        // TEST 2: Window Manager Numbering
        let windows = WindowManager.shared.getVisibleWindows()
        assertTest(!windows.isEmpty, "WindowManager discovered active windows count: \(windows.count)")
        if let w1 = WindowManager.shared.window(forNumber: 1) {
            assertTest(w1.number == 1, "Window #1 found: \(w1.appName) (ID: \(w1.id))")
        }
        if let w2 = WindowManager.shared.window(forNumber: 2) {
            assertTest(w2.number == 2, "Window #2 found: \(w2.appName) (ID: \(w2.id))")
        }

        func window(_ id: CGWindowID, _ bounds: CGRect, alpha: Double = 1, pid: pid_t = 22) -> [String: Any] {
            [
                kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
                kCGWindowLayer as String: 0, kCGWindowAlpha as String: alpha,
                kCGWindowBounds as String: bounds.dictionaryRepresentation
            ]
        }
        let primary = CGRect(x: 0, y: 0, width: 400, height: 300)
        let secondary = CGRect(x: -350, y: 50, width: 300, height: 200)
        let visibleWindows = WindowManager.numberVisibleWindows([
            window(1, CGRect(x: 0, y: 0, width: 100, height: 100)),
            window(2, CGRect(x: 100, y: 0, width: 100, height: 100)),
            window(3, CGRect(x: 40, y: 20, width: 120, height: 60)),
            window(4, CGRect(x: 180, y: 20, width: 40, height: 50)),
            window(5, CGRect(x: 410, y: 40, width: 100, height: 100)),
            window(6, CGRect(x: -110, y: 30, width: 100, height: 80)),
            window(7, CGRect(x: 240, y: 0, width: 120, height: 90), alpha: 0),
            window(8, CGRect(x: 240, y: 0, width: 60, height: 90), alpha: 0.5),
            window(9, CGRect(x: 245, y: 5, width: 40, height: 75)),
            window(10, CGRect(x: 320, y: 0, width: 80, height: 90), pid: 99),
            window(11, CGRect(x: 330, y: 5, width: 50, height: 75))
        ], displays: [primary, secondary], excluding: 99, limit: 10)
        assertTest(visibleWindows.map(\.id) == [1, 2, 4, 6, 8, 9], "Only exposed windows on active displays get numbers")
        assertTest(visibleWindows.map(\.number) == Array(1...6), "Visible window numbers have no gaps")
        assertTest(visibleWindows.first(where: { $0.id == 4 })?.visibleBounds ==
                   CGRect(x: 200, y: 20, width: 20, height: 50), "Badges use exposed bounds of small windows")
        assertTest(visibleWindows.first(where: { $0.id == 6 })?.visibleBounds ==
                   CGRect(x: -110, y: 50, width: 60, height: 60), "Bounds clip to the secondary display")

        // Exercise the production stream processor with cumulative recognition results.
        var stream = SpeechRecognizer.CommandStream()
        _ = stream.beginFreshUtterance("past", start: 0, end: 0.4)
        assertTest(stream.commands(in: "past", settled: false).isEmpty && stream.settleInterval == 0.45,
                   "A partial paste sound-alike waits briefly for the utterance to settle")
        assertTest(stream.flush().map(\.target) == [.paste], "The paste command sends one action")
        assertTest(!stream.beginFreshUtterance("Paste.", start: 0, end: 0.4) &&
                   stream.commands(in: "Paste.", settled: true).isEmpty, "A revised transcription does not paste twice")
        assertTest(stream.beginFreshUtterance("Paced.", start: 0.7, end: 1.1) &&
                   stream.commands(in: "Paced.", settled: true).map(\.target) == [.paste],
                   "A second spoken paste sends another action after a different transcription")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "paste screenshot", settled: true).isEmpty,
                   "A phrase beginning with paste does not trigger paste")
        assertTest(stream.commands(in: "extract text from two then paste", settled: true)
                    .map(\.target) == [.extractWindowText(2), .paste],
                   "An explicitly chained paste follows OCR")
        stream = SpeechRecognizer.CommandStream()
        assertTest(!stream.commands(in: "snap one past the deadline", settled: true).contains { $0.target == .paste },
                   "A sound-alike after another command requires a command boundary")
        assertTest(stream.commands(in: "extract text from two then past", settled: true)
                    .map(\.target) == [.extractWindowText(2), .paste],
                   "An explicitly chained paste accepts a sound-alike")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "extract text", settled: false).isEmpty && stream.settleInterval == 0.65,
                   "Bare OCR waits briefly for a window number")
        assertTest(stream.commands(in: "extract text from", settled: false).isEmpty && stream.flush().isEmpty,
                   "An incomplete window OCR command does not extract from the full screen")
        assertTest(stream.commands(in: "extract text from one", settled: true, badgesActive: true)
                    .map(\.target) == [.extractWindowText(1)],
                   "A cumulative OCR command takes the target from numbered windows")
        assertTest(stream.commands(in: "extract text from one. extract test two", settled: true)
                    .map(\.target) == [.extractWindowText(2)],
                   "The next numbered OCR command does not repeat the first")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "there was some background speech extract text from two", settled: true)
                    .map(\.target) == [.extractWindowText(2)],
                   "Numbered OCR recovers after background speech")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "snap", settled: false).isEmpty,
                   "A partial snap does not capture all displays")
        assertTest(stream.commands(in: "snap one", settled: true).map(\.target) == [.window(1)],
                   "A settled snap one captures Window 1")
        assertTest(stream.commands(in: "Snap1.", settled: false).isEmpty,
                   "A compact rewrite does not repeat an already captured window")
        assertTest(stream.commands(in: "Snap1, snap", settled: false).isEmpty,
                   "A trailing partial snap is held")
        assertTest(stream.commands(in: "Snap 1, snap two. snap3 in five", settled: false)
                    .map(\.target) == [.window(2)],
                   "A following command commits Window 2 and holds the countdown")
        let countdown = stream.commands(in: "snap1 snap2 Snap 3 in 5 seconds.", settled: false)
        assertTest(countdown.count == 1 && countdown.first?.target == .window(3) && countdown.first?.delay == 5,
                   "The last command preserves its own countdown")
        assertTest(stream.commands(in: "snap1 snap2 snap3 in five seconds", settled: true).isEmpty,
                   "A final rewrite does not repeat captures")

        stream = SpeechRecognizer.CommandStream()
        let burst = stream.commands(in: "snap1 snap 2 snap three snap 3", settled: true)
        assertTest(burst.map(\.target) == [.window(1), .window(2), .window(3), .window(3)],
                   "One result emits each snap in order, including repeated windows")

        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "snap 1", settled: false).isEmpty,
                   "The trailing number can still be revised")
        assertTest(stream.commands(in: "snap ten", settled: true).map(\.target) == [.window(10)],
                   "A revised number captures Window 10")

        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "snap", settled: false).isEmpty && stream.settleInterval == 0.25,
                   "Bare snap keeps a longer window for the target")
        assertTest(stream.commands(in: "snup too", settled: false).isEmpty && stream.settleInterval == 0.10,
                   "A complete corrected target uses a shorter hold")
        assertTest(stream.flush().map(\.target) == [.window(2)] && stream.flush().isEmpty,
                   "Flushing a dictionary match emits it exactly once")
        assertTest(stream.commands(in: "snap2", settled: true).isEmpty,
                   "A correction from approximate to exact does not repeat a capture")
        stream = SpeechRecognizer.CommandStream()
        let mixed = stream.commands(in: "show numbrs then snapp tree then screenshott text", settled: true)
        assertTest(mixed.map(\.target) == [.showWindowNumbers, .window(3), .extractText],
                   "Mixed exact and corrected commands execute in spoken order")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "snap to and fro", settled: true).isEmpty,
                   "An ordinary phrase containing a number homophone does not fire")
        assertTest(stream.commands(in: "snap to show changes", settled: true).isEmpty,
                   "A command keyword inside an ordinary phrase is not treated as a second command")
        assertTest(stream.commands(in: "snap window 11", settled: true).isEmpty,
                   "An invalid target does not fall back to an untargeted capture")
        let correctedDelay = SpeechRecognizer.parseTarget(spoken: "snup tree in fife sekonds")
        assertTest(correctedDelay?.target == .window(3) && correctedDelay?.delay == 5,
                   "The dictionary also recognizes countdown homophones")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "that was some unrelated speech", settled: false).isEmpty,
                   "Unrelated speech alone does not capture")
        assertTest(stream.commands(in: "that was some unrelated speech snap2", settled: false).isEmpty &&
                   stream.flush().map(\.target) == [.window(2)], "A numbered snap recovers after unrelated speech")
        assertTest(stream.commands(in: "that was some unrelated speech snap two. Copy text.", settled: true)
                    .map(\.target) == [.extractText], "A subsequent sentence executes without repeating the snap")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "we were talking. Display one.", settled: true).map(\.target) == [.display(1)],
                   "A new sentence recovers any command after unrelated speech")
        stream = SpeechRecognizer.CommandStream()
        assertTest(stream.commands(in: "I said do not snap one", settled: true).isEmpty,
                   "Recovery ignores a negated request")

        print("========================================")
        print("📊 Results: \(passed) Passed, \(failed) Failed")
        print("========================================")

        if failed > 0 {
            exit(1)
        }
    }
}
