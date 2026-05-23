import Foundation

@main
enum UserErrorFormatterTests {
    private static var failures = 0

    static func main() {
        testNetworkOfflineFormatting()
        testCancelledRequestFormatting()
        testHuggingFaceAuthFormatting()
        testWebSearchNetworkFormatting()
        testDiskFullFormatting()
        testLocalizedErrorFallback()
        testUnknownErrorFallback()
        finish()
    }

    private static func testCancelledRequestFormatting() {
        struct DomainCancellation: Error, UserCancellationError {
            let isUserCancellation = true
        }

        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled
        )
        let details = UserErrorFormatter.details(for: error)
        expect(UserErrorFormatter.isCancellation(error), "cancelled request detected")
        expect(details.message == "İşlem iptal edildi.", "cancelled request message")
        expect(details.recovery == nil, "cancelled request has no recovery")

        let taskError = CancellationError()
        expect(UserErrorFormatter.isCancellation(taskError), "task cancellation detected")
        let taskCancellation = UserErrorFormatter.details(for: taskError)
        expect(taskCancellation.message == "İşlem iptal edildi.", "task cancellation message")

        let domainCancellation = DomainCancellation()
        expect(UserErrorFormatter.isCancellation(domainCancellation), "domain cancellation detected")
        expect(UserErrorFormatter.message(for: domainCancellation) == "İşlem iptal edildi.", "domain cancellation message")
    }

    private static func testHuggingFaceAuthFormatting() {
        let error = NSError(
            domain: "MacLLM",
            code: 103,
            userInfo: [NSLocalizedDescriptionKey: "HTTP 403"]
        )
        let details = UserErrorFormatter.details(for: error)
        expect(details.message == "Model indirme yetkisi reddedildi.", "hf auth message")
        expect(details.displayText.contains("Hugging Face token"), "hf auth recovery")
        expect(details.displayText.contains("Kilitli model"), "hf auth Turkish gated wording")
    }

    private static func testWebSearchNetworkFormatting() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let details = UserErrorFormatter.details(for: WebSearchError.network(underlying))
        expect(details.message == "Web aramasına ulaşılamadı.", "web search network message")
        expect(details.displayText.contains("web aramasını kapatın"), "web search recovery")
    }

    private static func testNetworkOfflineFormatting() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet
        )
        let details = UserErrorFormatter.details(for: error)
        expect(details.message == "İnternet bağlantısı bulunamadı.", "offline message")
        expect(details.displayText.contains("tekrar deneyin"), "offline recovery")
    }

    private static func testDiskFullFormatting() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteOutOfSpace.rawValue
        )
        let details = UserErrorFormatter.details(for: error)
        expect(details.message == "Diskte yeterli alan yok.", "disk full message")
        expect(details.displayText.contains("Boş alan"), "disk full recovery")
    }

    private static func testLocalizedErrorFallback() {
        struct Localized: LocalizedError {
            var errorDescription: String? { "Özel hata" }
        }
        let details = UserErrorFormatter.details(for: Localized())
        expect(details.message == "Özel hata", "localized error message")
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
