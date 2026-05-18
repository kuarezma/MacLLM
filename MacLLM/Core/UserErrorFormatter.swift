import Foundation

enum UserErrorFormatter {
    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        let raw = error.localizedDescription
        if raw.isEmpty { return "Beklenmeyen bir hata oluştu." }
        return raw
    }
}
