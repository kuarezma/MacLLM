import Foundation
import UserNotifications

enum WebSearchError: LocalizedError {
    case emptyQuery
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Arama sorgusu boş."
        case .invalidResponse:
            return "Web araması yanıtı işlenemedi."
        case .network:
            return "Web aramasına ulaşılamadı."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .network:
            return "İnternet bağlantınızı kontrol edip tekrar deneyin veya web aramasını kapatın."
        case .emptyQuery, .invalidResponse:
            return nil
        }
    }
}

/// DuckDuckGo Instant Answer — API anahtarı gerektirmez.
enum WebSearchService {
    private static let maxContextChars = 4_000

    private struct InstantAnswer: Decodable {
        let AbstractText: String?
        let AbstractURL: String?
        let Heading: String?
        let RelatedTopics: [Topic]?

        struct Topic: Decodable {
            let Text: String?
            let FirstURL: String?
        }
    }

    static func fetchContext(for query: String) async throws -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WebSearchError.emptyQuery }

        guard var components = URLComponents(string: "https://api.duckduckgo.com/") else {
            throw WebSearchError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = components.url else { throw WebSearchError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("MacLLM/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let data: Data
        do {
            let (payload, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw WebSearchError.invalidResponse
            }
            data = payload
        } catch let error as WebSearchError {
            throw error
        } catch {
            throw WebSearchError.network(error)
        }

        let decoded = try JSONDecoder().decode(InstantAnswer.self, from: data)
        let block = formatContext(query: trimmed, answer: decoded)
        guard !block.isEmpty else {
            return "[Web araması: «\(trimmed)» için özet bulunamadı. Yanıtı genel bilginizle verin.]"
        }
        return block
    }

    private static func formatContext(query: String, answer: InstantAnswer) -> String {
        var lines: [String] = [
            "[Web araması — DuckDuckGo, sorgu: \(query)]",
        ]

        if let heading = answer.Heading?.trimmingCharacters(in: .whitespacesAndNewlines), !heading.isEmpty {
            lines.append("Başlık: \(heading)")
        }

        if let abstract = answer.AbstractText?.trimmingCharacters(in: .whitespacesAndNewlines), !abstract.isEmpty {
            lines.append(abstract)
            if let url = answer.AbstractURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                lines.append("Kaynak: \(url)")
            }
        }

        if let topics = answer.RelatedTopics {
            let snippets = topics.compactMap { topic -> String? in
                guard let text = topic.Text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    return nil
                }
                if let url = topic.FirstURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                    return "• \(text) (\(url))"
                }
                return "• \(text)"
            }
            if !snippets.isEmpty {
                lines.append("İlgili:")
                lines.append(contentsOf: snippets.prefix(5))
            }
        }

        let joined = lines.joined(separator: "\n")
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return String(joined.prefix(maxContextChars))
    }
}

enum WebSearchPreferences {
    private static let enabledKey = "webSearchEnabled"

    /// Globe düğmesi: bir sonraki gönderimde web bağlamı ekle.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

enum GenerationNotificationPreferences {
    private static let notifyKey = "notifyOnGenerationComplete"

    static var notifyOnComplete: Bool {
        get {
            if UserDefaults.standard.object(forKey: notifyKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: notifyKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: notifyKey) }
    }
}

enum GenerationNotificationService {
    static func notifyGenerationComplete(sessionTitle: String) {
        guard GenerationNotificationPreferences.notifyOnComplete else { return }

        let content = UNMutableNotificationContent()
        content.title = "Yanıt hazır"
        content.body = sessionTitle.isEmpty ? "MacLLM sohbeti" : sessionTitle
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "generation-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
