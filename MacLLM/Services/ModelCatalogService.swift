import Foundation

final class ModelCatalogService: Sendable {
    static let shared = ModelCatalogService()

    func loadDefaultCatalog() throws -> [CatalogEntry] {
        guard let url = Bundle.main.url(forResource: "default-catalog", withExtension: "json") else {
            throw NSError(domain: "MacLLM", code: 1, userInfo: [NSLocalizedDescriptionKey: "default-catalog.json bulunamadı"])
        }
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(DefaultCatalog.self, from: data)
        return catalog.models
    }

    func resolveDownloadURL(repoId: String, filename: String) -> URL {
        let encodedRepo = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        let encodedFile = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(encodedRepo)/resolve/main/\(encodedFile)"
        components.queryItems = [URLQueryItem(name: "download", value: "true")]
        guard let url = components.url else {
            fatalError("Invalid HF URL for \(repoId)/\(filename)")
        }
        return url
    }

    func catalogEntryNotInstalled(_ entry: CatalogEntry, installed: [InstalledModel]) -> Bool {
        !installed.contains { $0.id == entry.id || ($0.repoId == entry.repoId && $0.filename == entry.filename) }
    }
}
