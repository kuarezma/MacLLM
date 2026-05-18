import Foundation

struct HFModelSummary: Identifiable, Hashable {
    let id: String
    let repoId: String
    let downloads: Int
    let likes: Int
    let pipelineTag: String?
    let tags: [String]
    let lastModified: Date?
    let gated: Bool

    var parameterSize: String? {
        ModelMetadataParser.parseParameterSize(from: "\(repoId) \(tags.joined(separator: " "))")
    }

    var displayTags: [String] {
        ModelMetadataParser.displayTags(tags)
    }
}

struct HFRepoDetail: Hashable {
    let repoId: String
    let downloads: Int
    let likes: Int
    let gated: Bool
    let description: String?
    let license: String?
    let pipelineTag: String?
    let tags: [String]
    let files: [HFGGUFile]
}

struct HFGGUFile: Identifiable, Hashable {
    let id: String
    let filename: String
    let sizeBytes: Int64

    var quantLabel: String? { ModelMetadataParser.parseQuant(from: filename) }
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
        decoder.dateDecodingStrategy = .iso8601
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
            let likes: Int?
            let pipelineTag: String?
            let tags: [String]?
            let lastModified: Date?
            let gated: Bool?
        }

        let items = try decoder.decode([Item].self, from: data)
        return items
            .filter { $0.id.lowercased().contains("gguf") }
            .map {
                HFModelSummary(
                    id: $0.id,
                    repoId: $0.id,
                    downloads: $0.downloads ?? 0,
                    likes: $0.likes ?? 0,
                    pipelineTag: $0.pipelineTag,
                    tags: $0.tags ?? [],
                    lastModified: $0.lastModified,
                    gated: $0.gated ?? false
                )
            }
    }

    func fetchRepoDetail(repoId: String) async throws -> HFRepoDetail {
        let encoded = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        guard let url = URL(string: "https://huggingface.co/api/models/\(encoded)") else {
            throw HuggingFaceHubError.invalidURL
        }

        var request = URLRequest(url: url)
        HuggingFaceCredentials.applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response)

        struct CardData: Decodable {
            let license: String?
            let language: [String]?
        }
        struct Sibling: Decodable {
            let rfilename: String
            let size: Int64?
        }
        struct ModelInfo: Decodable {
            let id: String?
            let downloads: Int?
            let likes: Int?
            let gated: Bool?
            let pipelineTag: String?
            let tags: [String]?
            let cardData: CardData?
            let siblings: [Sibling]?
        }

        let info = try decoder.decode(ModelInfo.self, from: data)
        let files = (info.siblings ?? [])
            .filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
            .sorted { quantSortRank($0.rfilename) < quantSortRank($1.rfilename) }
            .map {
                HFGGUFile(
                    id: "\(repoId)/\($0.rfilename)",
                    filename: $0.rfilename,
                    sizeBytes: $0.size ?? 0
                )
            }

        return HFRepoDetail(
            repoId: repoId,
            downloads: info.downloads ?? 0,
            likes: info.likes ?? 0,
            gated: info.gated ?? false,
            description: nil,
            license: info.cardData?.license,
            pipelineTag: info.pipelineTag,
            tags: info.tags ?? [],
            files: files
        )
    }

    func listGGUFFiles(repoId: String) async throws -> [HFGGUFile] {
        try await fetchRepoDetail(repoId: repoId).files
    }

    static func guessChatTemplate(repoId: String, filename: String) -> String {
        let haystack = "\(repoId) \(filename)".lowercased()
        if haystack.contains("llama-3.1") || haystack.contains("llama3.1") { return "llama3" }
        if haystack.contains("llama-3") || haystack.contains("llama3") { return "llama3" }
        if haystack.contains("mistral") || haystack.contains("mixtral") {
            if haystack.contains("v0.3") || haystack.contains("instruct-v0.3") { return "mistral-v3" }
            return "mistral-v1"
        }
        if haystack.contains("phi-3") || haystack.contains("phi3") { return "phi3" }
        if haystack.contains("gemma-2") || haystack.contains("gemma2") { return "gemma" }
        if haystack.contains("gemma") { return "gemma" }
        if haystack.contains("qwen2.5") || haystack.contains("qwen2") || haystack.contains("qwen") { return "chatml" }
        if haystack.contains("deepseek") { return "chatml" }
        if haystack.contains("granite") { return "chatml" }
        return "chatml"
    }

    static func huggingFaceURL(repoId: String) -> URL? {
        URL(string: "https://huggingface.co/\(repoId)")
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
