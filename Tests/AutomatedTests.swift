import AppKit
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

        // Exercise the production stream processor with cumulative recognition results.
        var stream = SpeechRecognizer.CommandStream()
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
        assertTest(stream.commands(in: "snap", settled: false).isEmpty && stream.settleInterval == 0.35,
                   "Bare snap keeps a longer window for the target")
        assertTest(stream.commands(in: "snup too", settled: false).isEmpty && stream.settleInterval == 0.20,
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

        print("========================================")
        print("📊 Results: \(passed) Passed, \(failed) Failed")
        print("========================================")

        if failed > 0 {
            exit(1)
        }
    }
}
