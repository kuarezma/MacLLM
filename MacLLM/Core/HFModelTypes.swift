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

extension HFModelSummary {
    static func hubEntry(repoId: String, tags: [String] = [], gated: Bool = false) -> HFModelSummary {
        HFModelSummary(
            id: repoId,
            repoId: repoId,
            downloads: 0,
            likes: 0,
            pipelineTag: nil,
            tags: tags,
            lastModified: nil,
            gated: gated
        )
    }
}
