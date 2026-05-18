import Foundation

@main
enum MarkdownContentParserTests {
    private static var failures = 0

    static func main() {
        testPlainText()
        testCodeFence()
        testUnclosedFenceStreaming()
        testMultipleBlocks()
        finish()
    }

    private static func testPlainText() {
        let blocks = MarkdownContentParser.blocks(from: "Merhaba")
        expect(blocks.count == 1, "plain count")
        if case .text(let s) = blocks[0] {
            expect(s == "Merhaba", "plain text")
        } else {
            fail("plain type")
        }
    }

    private static func testCodeFence() {
        let input = "Önce\n```swift\nlet x = 1\n```\nSonra"
        let blocks = MarkdownContentParser.blocks(from: input)
        expect(blocks.count == 3, "fence count")
        if case .text(let a) = blocks[0] { expect(a == "Önce\n", "before") } else { fail("block0") }
        if case .code(let lang, let code) = blocks[1] {
            expect(lang == "swift", "lang")
            expect(code == "let x = 1", "code body")
        } else { fail("block1") }
        if case .text(let b) = blocks[2] { expect(b == "\nSonra", "after") } else { fail("block2") }
    }

    private static func testUnclosedFenceStreaming() {
        let input = "```python\nprint('hi')\nprint(x"
        let blocks = MarkdownContentParser.blocks(from: input)
        expect(blocks.count == 1, "streaming count")
        if case .code(let lang, let code) = blocks[0] {
            expect(lang == "python", "streaming lang")
            expect(code.contains("print('hi')"), "streaming code")
        } else { fail("streaming type") }
    }

    private static func testMultipleBlocks() {
        let input = "```\na\n```\n\n```\nb\n```"
        let blocks = MarkdownContentParser.blocks(from: input)
        expect(blocks.count == 3, "multi count")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func fail(_ label: String) {
        failures += 1
        fputs("FAIL: \(label)\n", stderr)
    }

    private static func finish() {
        if failures == 0 {
            print("MarkdownContentParserTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
