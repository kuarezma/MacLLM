import Foundation

@main
enum GenerationOutputFilterTests {
    private static var failures = 0

    static func main() {
        testStopPrefixHoldback()
        testStopTruncatesOutput()
        testFinishDrainsRemainder()
        finish()
    }

    private static func testStopPrefixHoldback() {
        var filter = GenerationOutputFilter(stopSequences: ["###END###"])
        expect(filter.push("Yanıt") == "Yanıt", "first chunk")
        expect(filter.push(" metin###EN") == " metin", "hold back partial stop prefix")
        expect(filter.push("D###") == "", "stop completes on this chunk")
        _ = filter.push("END###tail")
        expect(filter.finish() == "", "stop consumed trailing")
    }

    private static func testStopTruncatesOutput() {
        var filter = GenerationOutputFilter(stopSequences: ["###END###"])
        _ = filter.push("Tam cevap")
        let last = filter.push(" ###END###")
        expect(last == "", "no text after stop")
        expect(filter.finish() == "", "finished filter empty")
    }

    private static func testFinishDrainsRemainder() {
        var filter = GenerationOutputFilter(stopSequences: ["###END###"])
        expect(filter.push("Kısmi") == "Kısmi", "streaming chunk")
        expect(filter.finish() == "", "no stop — finish emits nothing extra after Kısmi")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("GenerationOutputFilterTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
