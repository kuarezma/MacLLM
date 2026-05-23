import Foundation

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

    func searchModels(
        query: String,
        limit: Int = 50,
        sort: HubSearchSort = .bestMatch
    ) async throws -> [HFModelSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTerm = q.isEmpty ? "gguf" : "\(q) gguf"
        guard var components = URLComponents(string: "https://huggingface.co/api/models") else {
            throw HuggingFaceHubError.invalidURL
        }
        var items = [
            URLQueryItem(name: "search", value: searchTerm),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let apiSort = sort.apiSort {
            items.append(URLQueryItem(name: "sort", value: apiSort))
            items.append(URLQueryItem(name: "direction", value: "-1"))
        }
        components.queryItems = items
        guard let url = components.url else { throw HuggingFaceHubError.invalidURL }

        var request = URLRequest(url: url)
        HuggingFaceCredentials.applyAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response)

        struct CardData: Decodable {
            let summary: String?
        }
        struct Item: Decodable {
            let id: String
            let downloads: Int?
            let likes: Int?
            let pipelineTag: String?
            let tags: [String]?
            let lastModified: Date?
            let gated: Bool?
            let cardData: CardData?
        }

        let decoded = try decoder.decode([Item].self, from: data)
        return decoded
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
                    gated: $0.gated ?? false,
                    summary: $0.cardData?.summary
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
            let summary: String?
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
        let sizeByFilename = try await fetchGGUFSizeMap(repoId: repoId)

        let siblingGGUF = (info.siblings ?? []).filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
        let files: [HFGGUFile]
        if siblingGGUF.isEmpty {
            files = sizeByFilename
                .sorted { HubFileListLogic.quantSortRank(filename: $0.key) < HubFileListLogic.quantSortRank(filename: $1.key) }
                .map { filename, size in
                    HFGGUFile(
                        id: "\(repoId)/\(filename)",
                        filename: filename,
                        sizeBytes: size
                    )
                }
        } else {
            files = siblingGGUF
                .sorted { HubFileListLogic.quantSortRank(filename: $0.rfilename) < HubFileListLogic.quantSortRank(filename: $1.rfilename) }
                .map { sibling in
                    let size = resolveFileSize(
                        filename: sibling.rfilename,
                        siblingSize: sibling.size,
                        sizeByFilename: sizeByFilename
                    )
                    return HFGGUFile(
                        id: "\(repoId)/\(sibling.rfilename)",
                        filename: sibling.rfilename,
                        sizeBytes: size
                    )
                }
        }

        return HFRepoDetail(
            repoId: repoId,
            downloads: info.downloads ?? 0,
            likes: info.likes ?? 0,
            gated: info.gated ?? false,
            description: info.cardData?.summary,
            license: info.cardData?.license,
            pipelineTag: info.pipelineTag,
            tags: info.tags ?? [],
            files: files
        )
    }

    func listGGUFFiles(repoId: String) async throws -> [HFGGUFile] {
        try await fetchRepoDetail(repoId: repoId).files
    }

    /// Depo README.md (main veya master dalı).
    func fetchReadme(repoId: String) async throws -> String? {
        let encoded = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        for branch in ["main", "master"] {
            guard let url = URL(string: "https://huggingface.co/\(encoded)/raw/\(branch)/README.md") else {
                continue
            }
            var request = URLRequest(url: url)
            HuggingFaceCredentials.applyAuth(to: &request)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                continue
            }
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty { return text }
        }
        return nil
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
        if haystack.contains("phi-2") || haystack.contains("phi2") { return "phi2" }
        if haystack.contains("gemma-2") || haystack.contains("gemma2") { return "gemma" }
        if haystack.contains("gemma") { return "gemma" }
        if haystack.contains("qwen2.5") || haystack.contains("qwen2") || haystack.contains("qwen") { return "chatml" }
        if haystack.contains("qwopus") || haystack.contains("opus") { return "chatml" }
        if haystack.contains("deepseek") { return "chatml" }
        if haystack.contains("granite") { return "chatml" }
        return "chatml"
    }

    static func huggingFaceURL(repoId: String) -> URL? {
        URL(string: "https://huggingface.co/\(repoId)")
    }

  /// HF model API artık siblings.size döndürmeyebilir — tree API'den boyutlar.
    private func fetchGGUFSizeMap(repoId: String) async throws -> [String: Int64] {
        let encoded = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        struct TreeLFS: Decodable { let size: Int64? }
        struct TreeEntry: Decodable {
            let type: String?
            let path: String
            let size: Int64?
            let lfs: TreeLFS?
        }

        for branch in ["main", "master"] {
            guard let url = URL(string: "https://huggingface.co/api/models/\(encoded)/tree/\(branch)?recursive=1") else {
                continue
            }
            var request = URLRequest(url: url)
            HuggingFaceCredentials.applyAuth(to: &request)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                continue
            }
            let entries = try decoder.decode([TreeEntry].self, from: data)
            var map: [String: Int64] = [:]
            for entry in entries where entry.type == "file" {
                let path = entry.path
                guard path.lowercased().hasSuffix(".gguf") else { continue }
                let bytes = entry.lfs?.size ?? entry.size ?? 0
                guard bytes > 0 else { continue }
                map[path] = bytes
                let base = (path as NSString).lastPathComponent
                if map[base] == nil {
                    map[base] = bytes
                }
            }
            if !map.isEmpty { return map }
        }
        return [:]
    }

    private func resolveFileSize(
        filename: String,
        siblingSize: Int64?,
        sizeByFilename: [String: Int64]
    ) -> Int64 {
        if let siblingSize, siblingSize > 0 { return siblingSize }
        if let match = sizeByFilename[filename], match > 0 { return match }
        let base = (filename as NSString).lastPathComponent
        if let match = sizeByFilename[base], match > 0 { return match }
        return 0
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw HuggingFaceHubError.httpStatus(http.statusCode)
        }
    }

}
