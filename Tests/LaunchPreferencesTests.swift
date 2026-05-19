import Foundation

@main
enum LaunchPreferencesTests {
    private static let key = "loadModelOnLaunch"
    private static var failures = 0

    static func main() {
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        testRoundTrip()
        testDefaultWhenMissing()
        finish()
    }

    private static func testRoundTrip() {
        for value in [LoadModelOnLaunch.ask, .always, .never] {
            LaunchPreferences.loadModelOnLaunch = value
            expect(LaunchPreferences.loadModelOnLaunch == value, "round-trip \(value.rawValue)")
        }
    }

    private static func testDefaultWhenMissing() {
        UserDefaults.standard.removeObject(forKey: key)
        expect(LaunchPreferences.loadModelOnLaunch == .ask, "default ask")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("LaunchPreferencesTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
