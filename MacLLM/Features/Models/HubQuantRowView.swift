import SwiftUI

/// Hub tablosu — tek GGUF satırı (Model | Format | Boyut | Bilgi | İndir).
struct HubQuantRowView: View {
    let file: HFGGUFile
    let repo: HFModelSummary
    let profile: MacSystemProfile
    let download: DownloadTaskInfo?
    let gated: Bool
    let isRecommended: Bool
    var installedModel: InstalledModel?
    let onDownload: () -> Void
    var onUse: (() -> Void)?

    @State private var showInfo = false

    private var tokenMissing: Bool {
        gated && (HuggingFaceCredentials.token ?? "").isEmpty
    }

    private var fitNote: String? {
        let entry = catalogEntry
        return ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first?.fitNote
    }

    private var catalogEntry: CatalogEntry {
        CatalogEntry(
            id: "\(repo.repoId)-\(file.filename)",
            name: ModelMetadataParser.repoDisplayName(file.filename),
            description: repo.repoId,
            repoId: repo.repoId,
            filename: file.filename,
            estimatedSizeBytes: max(file.sizeBytes, 1),
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: repo.repoId, filename: file.filename),
            ramHintGB: Int(ceil(Double(file.sizeBytes) / 1_073_741_824.0 * 1.4))
        )
    }

    var body: some View {
        GridRow {
            modelNameCell
            Text("GGUF")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                .font(.subheadline)
                .monospacedDigit()
            infoButton
            downloadCell
        }
        .padding(.vertical, 6)
        .popover(isPresented: $showInfo, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.filename)
                    .font(.caption)
                    .fontWeight(.semibold)
                if let quant = file.quantLabel {
                    Text("Quant: \(quant)")
                        .font(.caption)
                }
                if let note = fitNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("~\(catalogEntry.ramHintGB) GB RAM önerilir")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: 280)
        }
    }

    @ViewBuilder
    private var modelNameCell: some View {
        HStack(spacing: 6) {
            Text(HubFileListLogic.displayName(for: file))
                .font(.subheadline)
                .lineLimit(2)
            if isRecommended {
                AppTheme.badge("Önerilen", color: .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var infoButton: some View {
        Button {
            showInfo = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Model bilgisi")
    }

    @ViewBuilder
    private var downloadCell: some View {
        Group {
            if installedModel != nil {
                Button("Kullan") {
                    onUse?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if let download, download.state == .downloading || download.state == .paused {
                HStack(spacing: 8) {
                    ProgressView(value: download.progress)
                        .frame(width: 72)
                    Text(String(format: "%.0f%%", download.progress * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            } else if download?.state == .completed {
                Label("Yüklü", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if download?.state == .failed {
                Button("Tekrar", action: onDownload)
                    .controlSize(.small)
            } else {
                Button(tokenMissing ? "Token" : "İndir", action: onDownload)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(tokenMissing)
            }
        }
        .frame(width: 120, alignment: .trailing)
    }
}
