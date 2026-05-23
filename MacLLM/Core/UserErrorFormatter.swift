import Foundation

struct UserFacingError {
    let message: String
    let recovery: String?

    var displayText: String {
        guard let recovery, !recovery.isEmpty else { return message }
        return "\(message) \(recovery)"
    }
}

protocol UserCancellationError {
    var isUserCancellation: Bool { get }
}

enum UserErrorFormatter {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let cancellation = error as? UserCancellationError {
            return cancellation.isUserCancellation
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    static func message(for error: Error) -> String {
        details(for: error).message
    }

    static func details(for error: Error) -> UserFacingError {
        if isCancellation(error) {
            return UserFacingError(message: "İşlem iptal edildi.", recovery: nil)
        }

        if let localized = error as? LocalizedError,
           let recovery = localized.recoverySuggestion,
           !recovery.isEmpty {
            return UserFacingError(
                message: localized.errorDescription ?? error.localizedDescription,
                recovery: recovery
            )
        }

        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return UserFacingError(
                    message: "İnternet bağlantısı bulunamadı.",
                    recovery: "Bağlantınızı kontrol edip tekrar deneyin."
                )
            case NSURLErrorTimedOut:
                return UserFacingError(
                    message: "İstek zaman aşımına uğradı.",
                    recovery: "Biraz sonra yeniden deneyin."
                )
            case NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication:
                return UserFacingError(
                    message: "Kimlik doğrulama gerekiyor.",
                    recovery: "Hugging Face token ayarlarınızı kontrol edin."
                )
            default:
                break
            }
        }

        if nsError.domain == "MacLLM" {
            let raw = nsError.localizedDescription
            if nsError.code == 101 {
                return UserFacingError(
                    message: raw,
                    recovery: "İndirme panelinden ilerlemeyi takip edebilirsiniz."
                )
            }
            if raw.contains("HTTP 401") || raw.contains("HTTP 403") {
                return UserFacingError(
                    message: "Model indirme yetkisi reddedildi.",
                    recovery: "Kilitli model için Hugging Face token ayarını kontrol edin."
                )
            }
            if raw.contains("HTTP 404") {
                return UserFacingError(
                    message: "Model dosyası bulunamadı.",
                    recovery: "Model bağlantısını veya dosya adını doğrulayın."
                )
            }
        }

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case CocoaError.fileNoSuchFile.rawValue:
                return UserFacingError(
                    message: "Dosya bulunamadı.",
                    recovery: "Dosyanın konumunu kontrol edip tekrar deneyin."
                )
            case CocoaError.fileWriteOutOfSpace.rawValue:
                return UserFacingError(
                    message: "Diskte yeterli alan yok.",
                    recovery: "Boş alan açıp işlemi yeniden başlatın."
                )
            case CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue:
                return UserFacingError(
                    message: "Dosya erişim izni yok.",
                    recovery: "Dosya izinlerini kontrol edin."
                )
            default:
                break
            }
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return UserFacingError(message: description, recovery: nil)
        }
        let raw = error.localizedDescription
        if raw.isEmpty {
            return UserFacingError(
                message: "Beklenmeyen bir hata oluştu.",
                recovery: "Lütfen tekrar deneyin."
            )
        }
        let recovery = (error as? LocalizedError)?.recoverySuggestion
        return UserFacingError(message: raw, recovery: recovery)
    }
}
