import Foundation

@main
struct ChatExporterTests {
    static func main() {
        testMarkdownExport()
        testChatImporterRoundTrip()
        print("ChatExporterTests: OK")
    }

    private static func testMarkdownExport() {
        let session = ChatSession(
            title: "Test",
            messages: [
                ChatMessage(role: .user, content: "Merhaba"),
                ChatMessage(role: .assistant, content: "Selam"),
            ]
        )
        let md = ChatExporter.markdown(for: session, modelName: "Demo")
        assert(md.contains("# Test"))
        assert(md.contains("## Kullanıcı"))
        assert(md.contains("Merhaba"))
        assert(md.contains("Model: Demo"))
    }

    private static func testChatImporterRoundTrip() {
        let original = ChatSession(
            title: "İçe aktarma",
            messages: [
                ChatMessage(role: .user, content: "Soru"),
                ChatMessage(role: .assistant, content: "Cevap"),
            ]
        )
        let md = ChatExporter.markdown(for: original, modelName: nil)
        guard let imported = ChatImporter.session(fromMarkdown: md) else {
            fatalError("import failed")
        }
        assert(imported.title == "İçe aktarma")
        assert(imported.messages.count == 2)
        assert(imported.messages[0].content == "Soru")
        assert(imported.messages[1].content == "Cevap")
    }
}
