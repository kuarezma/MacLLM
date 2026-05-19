import Foundation

struct UserFacingError {
    let message: String
    let recovery: String?

    var displayText: String {
        guard let recovery, !recovery.isEmpty else { return message }
        return "\(message) \(recovery)"
    }
}

enum UserErrorFormatter {
    static func message(for error: Error) -> String {
        details(for: error).message
    }

    static func details(for error: Error) -> UserFacingError {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return UserFacingError(
                    message: "Internet baglantisi bulunamadi.",
                    recovery: "Baglantinizi kontrol edip tekrar deneyin."
                )
            case NSURLErrorTimedOut:
                return UserFacingError(
                    message: "Istek zaman asimina ugradi.",
                    recovery: "Biraz sonra yeniden deneyin."
                )
            case NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication:
                return UserFacingError(
                    message: "Kimlik dogrulama gerekiyor.",
                    recovery: "Hugging Face token ayarlarinizi kontrol edin."
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
                    recovery: "Gated model için Hugging Face token ayarını kontrol edin."
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
                    message: "Dosya bulunamadi.",
                    recovery: "Dosyanin konumunu kontrol edip tekrar deneyin."
                )
            case CocoaError.fileWriteOutOfSpace.rawValue:
                return UserFacingError(
                    message: "Diskte yeterli alan yok.",
                    recovery: "Bos alan acip islemi yeniden baslatin."
                )
            case CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue:
                return UserFacingError(
                    message: "Dosya erisim izni yok.",
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
                message: "Beklenmeyen bir hata olustu.",
                recovery: "Lutfen tekrar deneyin."
            )
        }
        return UserFacingError(message: raw, recovery: nil)
    }
}
