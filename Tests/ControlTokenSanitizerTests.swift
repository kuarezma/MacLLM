import Foundation

@main
enum ControlTokenSanitizerTests {
    private static var failures = 0

    static func main() {
        testRemovesImEnd()
        testStripsTrailingPartialToken()
        testRegexControlTokens()
        testPreservesNormalText()
        finish()
    }

    private static func testRemovesImEnd() {
        let imEnd = "<|" + "im_end" + "|>"
        let input = "Merhaba \(imEnd) dünya"
        expect(ControlTokenSanitizer.clean(input) == "Merhaba  dünya", "im_end removed")
    }

    private static func testStripsTrailingPartialToken() {
        let partial = "Yanıt metni <|im_start"
        expect(ControlTokenSanitizer.clean(partial) == "Yanıt metni", "partial im_start stripped")
    }

    private static func testRegexControlTokens() {
        let input = "Önce <|im_start|>user\nSonra"
        expect(ControlTokenSanitizer.clean(input) == "Önce user\nSonra", "regex token removed")
    }

    private static func testPreservesNormalText() {
        let input = "Bugün günlerden ne?"
        expect(ControlTokenSanitizer.clean(input) == input, "plain text unchanged")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("ControlTokenSanitizerTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
