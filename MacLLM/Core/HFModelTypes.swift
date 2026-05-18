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
    let summary: String?

    var parameterSize: String? {
        ModelMetadataParser.parseParameterSize(from: "\(repoId) \(tags.joined(separator: " "))")
    }

    var parameterSizeDisplay: String? {
        ModelMetadataParser.parameterSizeDisplay(from: "\(repoId) \(tags.joined(separator: " "))")
    }

    var parameterSizeBadge: String? {
        parameterSize
    }

    var displayTags: [String] {
        ModelMetadataParser.displayTags(tags)
    }

    var architecture: String? {
        ModelMetadataParser.parseArchitecture(from: "\(repoId) \(tags.joined(separator: " "))")
    }

    var displayName: String {
        ModelMetadataParser.repoDisplayName(repoId)
    }

    var author: String? {
        ModelMetadataParser.repoAuthor(repoId)
    }

    var shortBlurb: String {
        if let summary, !summary.isEmpty { return summary }
        if let pipelineTag { return pipelineTag.capitalized }
        if let param = parameterSizeDisplay { return param }
        return displayTags.prefix(2).joined(separator: " · ")
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

    var parameterSizeDisplay: String? {
        ModelMetadataParser.parameterSizeDisplay(from: "\(repoId) \(tags.joined(separator: " "))")
    }

    var parameterSizeBadge: String? {
        ModelMetadataParser.parameterSizeBadge(from: "\(repoId) \(tags.joined(separator: " "))")
    }
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
            gated: gated,
            summary: nil
        )
    }
}
