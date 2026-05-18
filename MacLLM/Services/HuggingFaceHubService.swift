import Foundation

struct HFModelSummary: Identifiable, Hashable {
    let id: String
    let repoId: String
    let downloads: Int
    let pipelineTag: String?
    let tags: [String]
}

struct HFGGUFile: Identifiable, Hashable {
    let id: String
    let filename: String
    let sizeBytes: Int64
}

enum HuggingFaceHubError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Geçersiz Hugging Face adresi."
        case .httpStatus(let code): return "Hugging Face hatası (HTTP \(code))."
        case .decodeFailed: return "Sunucu yanıtı okunamadı."
        }
    }
}

final class HuggingFaceHubService: Sendable {
    static let shared = HuggingFaceHubService()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func searchModels(query: String, limit: Int = 25) async throws -> [HFModelSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTerm = q.isEmpty ? "gguf" : "\(q) gguf"
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: searchTerm),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components.url else { throw HuggingFaceHubError.invalidURL }

        var request = URLRequest(url: url)
        HuggingFaceCredentials.applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response)

        struct Item: Decodable {
            let id: String
            let downloads: Int?
            let pipelineTag: String?
            let tags: [String]?
        }

        let items = try decoder.decode([Item].self, from: data)
        return items
            .filter { $0.id.lowercased().contains("gguf") }
            .map {
                HFModelSummary(
                    id: $0.id,
                    repoId: $0.id,
                    downloads: $0.downloads ?? 0,
                    pipelineTag: $0.pipelineTag,
                    tags: $0.tags ?? []
                )
            }
    }

    func listGGUFFiles(repoId: String) async throws -> [HFGGUFile] {
        let encoded = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        guard let url = URL(string: "https://huggingface.co/api/models/\(encoded)") else {
            throw HuggingFaceHubError.invalidURL
        }

        var request = URLRequest(url: url)
        HuggingFaceCredentials.applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response)

        struct Sibling: Decodable {
            let rfilename: String
            let size: Int64?
        }
        struct ModelInfo: Decodable {
            let siblings: [Sibling]?
        }

        let info = try decoder.decode(ModelInfo.self, from: data)
        return (info.siblings ?? [])
            .filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
            .sorted { lhs, rhs in
                quantSortRank(lhs.rfilename) < quantSortRank(rhs.rfilename)
            }
            .map {
                HFGGUFile(
                    id: "\(repoId)/\($0.rfilename)",
                    filename: $0.rfilename,
                    sizeBytes: $0.size ?? 0
                )
            }
    }

    static func guessChatTemplate(repoId: String, filename: String) -> String {
        let haystack = "\(repoId) \(filename)".lowercased()
        if haystack.contains("llama-3") || haystack.contains("llama3") { return "llama3" }
        if haystack.contains("mistral") || haystack.contains("mixtral") { return "mistral" }
        if haystack.contains("phi-3") || haystack.contains("phi3") { return "phi3" }
        if haystack.contains("gemma") { return "gemma" }
        if haystack.contains("qwen") { return "chatml" }
        return "chatml"
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw HuggingFaceHubError.httpStatus(http.statusCode)
        }
    }

    private func quantSortRank(_ filename: String) -> Int {
        let lower = filename.lowercased()
        if lower.contains("q4_k_m") { return 0 }
        if lower.contains("q4_k_s") { return 1 }
        if lower.contains("q4_0") { return 2 }
        if lower.contains("q5_k_m") { return 3 }
        if lower.contains("q3_k") { return 4 }
        if lower.contains("q6_k") { return 5 }
        if lower.contains("q8_0") { return 6 }
        return 10
    }
}
