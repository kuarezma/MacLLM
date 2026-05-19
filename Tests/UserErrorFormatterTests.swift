import Foundation

@main
enum UserErrorFormatterTests {
    private static var failures = 0

    static func main() {
        testNetworkOfflineFormatting()
        testDiskFullFormatting()
        testLocalizedErrorFallback()
        testUnknownErrorFallback()
        finish()
    }

    private static func testNetworkOfflineFormatting() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet
        )
        let details = UserErrorFormatter.details(for: error)
        expect(details.message == "Internet baglantisi bulunamadi.", "offline message")
        expect(details.displayText.contains("tekrar deneyin"), "offline recovery")
    }

    private static func testDiskFullFormatting() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteOutOfSpace.rawValue
        )
        let details = UserErrorFormatter.details(for: error)
        expect(details.message == "Diskte yeterli alan yok.", "disk full message")
        expect(details.displayText.contains("Bos alan"), "disk full recovery")
    }

    private static func testLocalizedErrorFallback() {
        struct Localized: LocalizedError {
            var errorDescription: String? { "Ozel hata" }
        }
        let details = UserErrorFormatter.details(for: Localized())
        expect(details.message == "Ozel hata", "localized error message")
    }

    private static func testUnknownErrorFallback() {
        enum PlainError: Error { case failed }
        let details = UserErrorFormatter.details(for: PlainError.failed)
        expect(!details.message.isEmpty, "unknown message not empty")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            failures += 1
            fputs("FAIL: \(label)\n", stderr)
        }
    }

    private static func finish() {
        if failures == 0 {
            print("UserErrorFormatterTests: OK")
        } else {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
    }
}
