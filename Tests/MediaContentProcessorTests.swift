import Foundation

@main
struct MediaContentProcessorTests {
    static func main() {
        testDocumentTextBlock()
        testDocumentTextBlockEmpty()
        print("MediaContentProcessorTests: OK")
    }

    private static func testDocumentTextBlock() {
        let block = MediaContentProcessor.documentTextBlock(fileName: "not.txt", text: "  Merhaba dünya  ")
        assert(block.contains("[Belge: not.txt]"))
        assert(block.contains("Merhaba dünya"))
    }

    private static func testDocumentTextBlockEmpty() {
        let block = MediaContentProcessor.documentTextBlock(fileName: "empty.txt", text: "   \n  ")
        assert(block.isEmpty)
    }
}
