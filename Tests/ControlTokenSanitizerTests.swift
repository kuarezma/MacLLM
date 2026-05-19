import Foundation

@main
enum ControlTokenSanitizerTests {
    private static var failures = 0

    static func main() {
        testRemovesImEnd()
        testRemovesRedactedImEnd()
        testStripsTrailingPartialToken()
        testStripsLoneLessThan()
        testStreamingSafeDelta()
        testRegexControlTokens()
        testPreservesNormalText()
        testHasMeaningfulText()
        finish()
    }

    private static func testRemovesImEnd() {
        let imEnd = "<|" + "im_end" + "|>"
        let input = "Merhaba \(imEnd) dünya"
        expect(ControlTokenSanitizer.clean(input) == "Merhaba  dünya", "im_end removed")
    }

    private static func testRemovesRedactedImEnd() {
        let token = "<|" + "redacted_im_end" + "|>"
        let input = "Cevap \(token)"
        expect(ControlTokenSanitizer.clean(input) == "Cevap", "redacted_im_end removed")
    }

    private static func testStripsTrailingPartialToken() {
        let partial = "Yanıt metni <|im_start"
        expect(ControlTokenSanitizer.clean(partial) == "Yanıt metni", "partial im_start stripped")
    }

    private static func testStripsLoneLessThan() {
        expect(ControlTokenSanitizer.clean("Merhaba <") == "Merhaba", "lone < stripped")
    }

    private static func testStreamingSafeDelta() {
        expect(ControlTokenSanitizer.streamingSafeDelta("<") == "", "delta < filtered")
        expect(ControlTokenSanitizer.streamingSafeDelta("evet") == "evet", "normal delta kept")
    }

    private static func testRegexControlTokens() {
        let input = "Önce <|im_start|>user\nSonra"
        expect(ControlTokenSanitizer.clean(input) == "Önce user\nSonra", "regex token removed")
    }

    private static func testPreservesNormalText() {
        let input = "Bugün günlerden ne?"
        expect(ControlTokenSanitizer.clean(input) == input, "plain text unchanged")
    }

    private static func testHasMeaningfulText() {
        expect(!ControlTokenSanitizer.hasMeaningfulText("<"), "lone < not meaningful")
        expect(ControlTokenSanitizer.hasMeaningfulText("Merhaba"), "text meaningful")
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
