import Foundation

@main
enum ModelCapabilitiesTests {
    private static var failures = 0

    static func main() {
        testMmprojWarningIsTurkish()
        finish()
    }

    private static func testMmprojWarningIsTurkish() {
        let model = InstalledModel(
            id: "qwen-vl",
            name: "Qwen2-VL",
            repoId: "test/qwen-vl",
            filename: "qwen2-vl.Q4_K_M.gguf",
            localPath: "/tmp/qwen2-vl.Q4_K_M.gguf",
            chatTemplate: "chatml",
            fileSizeBytes: 1,
            downloadedAt: Date()
        )
        let attachment = MessageAttachment(
            kind: .image,
            fileName: "tahta.png",
            storageName: "tahta.png"
        )

        let warning = ModelCapabilities.attachmentWarning(model: model, attachments: [attachment])
        expect(warning?.contains("Görüntü için mmproj") == true, "Turkish mmproj warning")
        expect(warning?.contains("Vision için") == false, "no English vision warning")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("ModelCapabilitiesTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
