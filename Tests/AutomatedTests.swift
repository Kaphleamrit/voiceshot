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
        print("🧪 Running VoiceShot Numbered Window & 'ss1' Test Suite")
        print("========================================")

        // TEST 1: Window Number & SS Tokens Parser
        let testCases: [(spoken: String, expectedTarget: CaptureTarget, desc: String)] = [
            // "screenshot N" -> Window N
            ("screenshot 1", .window(1), "screenshot 1 -> Window 1"),
            ("screenshot 2", .window(2), "screenshot 2 -> Window 2"),
            ("screenshot 3", .window(3), "screenshot 3 -> Window 3"),
            ("screenshot 4", .window(4), "screenshot 4 -> Window 4"),
            ("screenshot 5", .window(5), "screenshot 5 -> Window 5"),
            
            // "ssN" -> Window N
            ("ss1", .window(1), "ss1 -> Window 1"),
            ("ss2", .window(2), "ss2 -> Window 2"),
            ("ss3", .window(3), "ss3 -> Window 3"),
            ("ss4", .window(4), "ss4 -> Window 4"),
            ("ss5", .window(5), "ss5 -> Window 5"),
            
            // Spaced "ss N" -> Window N
            ("ss 1", .window(1), "ss 1 -> Window 1"),
            ("ss 2", .window(2), "ss 2 -> Window 2"),
            ("ss 3", .window(3), "ss 3 -> Window 3"),
            ("s1", .window(1), "s1 -> Window 1"),
            ("s2", .window(2), "s2 -> Window 2"),
            
            // Explicit Display & Window
            ("display 1", .display(1), "display 1 -> Display 1"),
            ("display 2", .display(2), "display 2 -> Display 2"),
            ("window 1", .window(1), "window 1 -> Window 1"),
            
            // Visual Overlay Badges Command
            ("show window numbers", .showWindowNumbers, "show window numbers"),
            ("show numbers", .showWindowNumbers, "show numbers"),
            ("show windows", .showWindowNumbers, "show windows"),
            
            // General
            ("take screenshot", .allDisplays, "take screenshot -> All Displays")
        ]

        for tc in testCases {
            if let result = SpeechRecognizer.parseTarget(spoken: tc.spoken) {
                assertTest(result.target == tc.expectedTarget, tc.desc)
            } else {
                assertTest(false, "\(tc.desc) (failed to match)")
            }
        }

        // TEST 2: Window Manager Numbering
        let windows = WindowManager.shared.getVisibleWindows()
        assertTest(!windows.isEmpty, "WindowManager discovered active windows count: \(windows.count)")
        if let w1 = WindowManager.shared.window(forNumber: 1) {
            assertTest(w1.number == 1, "Window #1 found: \(w1.appName) (ID: \(w1.id))")
        }
        if let w2 = WindowManager.shared.window(forNumber: 2) {
            assertTest(w2.number == 2, "Window #2 found: \(w2.appName) (ID: \(w2.id))")
        }

        // TEST 3: Consecutive "ss1", "ss2", "ss3" Streaming Simulation
        var processedLength: Int = 0
        var firedTargets: [CaptureTarget] = []
        var lastTime = Date.distantPast
        
        func simulateSpeechChunk(_ text: String) {
            if text.count < processedLength {
                processedLength = 0
            }
            let startIdx = text.index(text.startIndex, offsetBy: processedLength, limitedBy: text.endIndex) ?? text.startIndex
            let pending = String(text[startIdx...])
            
            if let match = SpeechRecognizer.parseTarget(spoken: pending) {
                let now = Date()
                if now.timeIntervalSince(lastTime) > 0.05 {
                    lastTime = now
                    processedLength = text.count
                    firedTargets.append(match.target)
                }
            }
        }

        simulateSpeechChunk("ss1")
        assertTest(firedTargets.count == 1 && firedTargets.last == .window(1), "Streaming 1: 'ss1' captured Window 1")

        Thread.sleep(forTimeInterval: 0.1)
        simulateSpeechChunk("ss1 now ss2")
        assertTest(firedTargets.count == 2 && firedTargets.last == .window(2), "Streaming 2: 'ss2' captured Window 2")

        Thread.sleep(forTimeInterval: 0.1)
        simulateSpeechChunk("ss1 now ss2 and ss3")
        assertTest(firedTargets.count == 3 && firedTargets.last == .window(3), "Streaming 3: 'ss3' captured Window 3")

        print("========================================")
        print("📊 Results: \(passed) Passed, \(failed) Failed")
        print("========================================")

        if failed > 0 {
            exit(1)
        }
    }
}
