import Foundation

@main
enum MarkdownContentParserTests {
    private static var failures = 0

    static func main() {
        testPlainText()
        testCodeFence()
        testUnclosedFenceStreaming()
        testMultipleBlocks()
        testBulletList()
        testHeading()
        testNumberedList()
        finish()
    }

    private static func testBulletList() {
        let segments = MarkdownContentParser.proseSegments(from: "- bir\n- iki")
        expect(segments.count == 1, "bullet count")
        if case .bulletList(let items) = segments[0] {
            expect(items == ["bir", "iki"], "bullet items")
        } else { fail("bullet type") }
    }

    private static func testHeading() {
        let segments = MarkdownContentParser.proseSegments(from: "## Başlık\nMetin")
        expect(segments.count == 2, "heading count")
        if case .heading(let level, let text) = segments[0] {
            expect(level == 2, "heading level")
            expect(text == "Başlık", "heading text")
        } else { fail("heading type") }
    }

    private static func testNumberedList() {
        let segments = MarkdownContentParser.proseSegments(from: "1. alpha\n2. beta")
        expect(segments.count == 1, "numbered count")
        if case .numberedList(let items) = segments[0] {
            expect(items == ["alpha", "beta"], "numbered items")
        } else { fail("numbered type") }
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
