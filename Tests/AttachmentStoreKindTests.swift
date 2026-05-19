import Foundation
import UniformTypeIdentifiers

@main
struct AttachmentStoreKindTests {
    static func main() {
        testDocxKind()
        testPdfKind()
        print("AttachmentStoreKindTests: OK")
    }

    private static func testDocxKind() {
        let type = UTType(filenameExtension: "docx")!
        assert(AttachmentStore.kind(for: type) == .document)
    }

    private static func testPdfKind() {
        assert(AttachmentStore.kind(for: .pdf) == .document)
    }
}
