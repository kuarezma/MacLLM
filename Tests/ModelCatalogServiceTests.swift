import Foundation

@main
enum ModelCatalogServiceTests {
    private static var failures = 0

    static func main() {
        testResolveDownloadURLKeepsRepoPath()
        testResolveDownloadURLEncoding()
        finish()
    }

    private static func testResolveDownloadURLKeepsRepoPath() {
        let url = ModelCatalogService.shared.resolveDownloadURL(
            repoId: "Qwen/Qwen2.5-7B-Instruct-GGUF",
            filename: "qwen2.5-7b-instruct-q4_k_m.gguf"
        )
        expect(url.absoluteString == "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf?download=true", "standard hf url")
    }

    private static func testResolveDownloadURLEncoding() {
        let url = ModelCatalogService.shared.resolveDownloadURL(
            repoId: "org/model with space",
            filename: "model q4.gguf"
        )
        expect(url.absoluteString.contains("model%20with%20space"), "repo path encodes spaces once")
        expect(url.absoluteString.contains("model%20q4.gguf"), "filename encodes spaces once")
        expect(!url.absoluteString.contains("%2520"), "spaces are not double encoded")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("ModelCatalogServiceTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
