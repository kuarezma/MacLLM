import Foundation

@main
enum HubFileListLogicTests {
    private static var failures = 0

    static func main() {
        testQuantRank()
        testQ4Filter()
        testSizeSort()
        finish()
    }

    private static func testQuantRank() {
        let q4 = HubFileListLogic.quantSortRank(filename: "model.Q4_K_M.gguf")
        let q8 = HubFileListLogic.quantSortRank(filename: "model.Q8_0.gguf")
        expect(q4 < q8, "q4 before q8")
    }

    private static func testQ4Filter() {
        let files = [
            HFGGUFile(id: "1", filename: "a.Q4_K_M.gguf", sizeBytes: 5_000_000_000),
            HFGGUFile(id: "2", filename: "b.Q8_0.gguf", sizeBytes: 9_000_000_000),
        ]
        let result = HubFileListLogic.filterAndSort(
            files: files,
            filter: .q4,
            sort: .name,
            fitLevels: [:]
        )
        expect(result.count == 1, "q4 filter count")
    }

    private static func testSizeSort() {
        let files = [
            HFGGUFile(id: "1", filename: "big.Q8_0.gguf", sizeBytes: 9_000),
            HFGGUFile(id: "2", filename: "small.Q4_K_M.gguf", sizeBytes: 4_000),
        ]
        let result = HubFileListLogic.filterAndSort(
            files: files,
            filter: .all,
            sort: .sizeAscending,
            fitLevels: [:]
        )
        expect(result.first?.id == "2", "smallest first")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("HubFileListLogicTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
