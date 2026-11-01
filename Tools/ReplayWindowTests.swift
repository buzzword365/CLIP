import Foundation

@main struct ReplayWindowTests {
    static func main() {
        let clean = (0..<12).map { n in
            ReplaySegmentInfo(startedAt: 1000.0 + Double(n) * 3.0,
                              endedAt: 1002.95 + Double(n) * 3.0,
                              mediaDuration: 2.95)
        }
        func check(_ label: String, _ items: [ReplaySegmentInfo],
                   _ requestedAt: Double, expected: Bool) {
            let actual = ReplayWindowPolicy.choose(items, seconds: 30,
                                                   requestedAt: requestedAt) != nil
            guard actual == expected else {
                fatalError("\(label): expected \(expected), got \(actual)")
            }
            print("PASS \(label)")
        }
        check("continuous fresh 30-second buffer", clean, 1036.0, expected: true)
        check("same file selection several minutes later rejected", clean, 1300.0, expected: false)
        check("only 3 seconds after recovery rejected", Array(clean.suffix(1)), 1036.0, expected: false)
        check("initial partial buffer rejected", Array(clean.prefix(5)), 1015.0, expected: false)
        var missing = clean
        missing[6] = ReplaySegmentInfo(startedAt: 1024, endedAt: 1026.95, mediaDuration: 2.95)
        check("multi-second capture dropout rejected", missing, 1036.0, expected: false)
        check("small frame variations tolerated", clean, 1038.0, expected: true)
        if case .warmingUp(let available, let required) = ReplayWindowPolicy.evaluate(
            Array(clean.prefix(5)), seconds: 30, requestedAt: 1015.0) {
            guard available > 0 && available < required else { fatalError("Invalid progress") }
            print("PASS partial buffer reports progress: \(available)/\(required)")
        } else { fatalError("Expected warming-up result") }
        if case .stalled(let age) = ReplayWindowPolicy.evaluate(clean, seconds: 30,
                                                                requestedAt: 1100.0) {
            guard age > 4 else { fatalError("Invalid stall age") }
            print("PASS old buffer reports a stalled capture")
        } else { fatalError("Expected stalled result") }
        print("ALL REPLAY FRESHNESS TESTS PASSED")
    }
}
