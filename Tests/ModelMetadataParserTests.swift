import Foundation

@main
enum ModelMetadataParserTests {
    private static var failures = 0

    static func main() {
        testCapabilityTagsAreUserFacingTurkish()
        finish()
    }

    private static func testCapabilityTagsAreUserFacingTurkish() {
        let tags = ["text-generation", "function-calling", "reasoning", "vision", "chat"]
        let caps = ModelMetadataParser.capabilityTags(from: tags)

        expect(caps.contains("Araç kullanımı"), "tool use capability")
        expect(caps.contains("Akıl yürütme"), "reasoning capability")
        expect(caps.contains("Görüntü"), "vision capability")
        expect(caps.contains("Sohbet"), "chat capability")
        expect(!caps.contains("Vision"), "no English vision label")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("ModelMetadataParserTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
