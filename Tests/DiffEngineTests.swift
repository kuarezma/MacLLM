import Foundation
import Darwin

@main
struct DiffEngineTests {
    static func main() {
        testIdenticalStrings()
        testAdditionsAndDeletions()
        testEmptyStrings()
        print("DiffEngineTests: OK")
    }

    private static func testIdenticalStrings() {
        let code = "func hello() {\n    print(\"hi\")\n}"
        let diff = DiffEngine.computeDiff(original: code, proposed: code)
        assert(diff.additionsCount == 0)
        assert(diff.deletionsCount == 0)
        assert(diff.lines.count == 3)
        assert(diff.lines.allSatisfy { $0.kind == .unchanged })
    }

    private static func testAdditionsAndDeletions() {
        let original = "let a = 1\nlet b = 2\nlet c = 3"
        let proposed = "let a = 1\nlet b = 99\nlet d = 4\nlet c = 3"

        let diff = DiffEngine.computeDiff(original: original, proposed: proposed)
        assert(diff.additionsCount > 0)
        assert(diff.deletionsCount > 0)
        assert(diff.lines.contains { $0.kind == .addition && $0.text.contains("99") })
        assert(diff.lines.contains { $0.kind == .deletion && $0.text.contains("let b = 2") })
    }

    private static func testEmptyStrings() {
        let diff = DiffEngine.computeDiff(original: "", proposed: "")
        assert(diff.additionsCount == 0)
        assert(diff.deletionsCount == 0)
    }
}
