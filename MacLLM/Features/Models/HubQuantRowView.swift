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
            Text(ModelMetadataParser.formatFileSize(bytes: file.sizeBytes))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(file.sizeBytes > 0 ? .primary : .secondary)
            infoButton
            downloadCell
        }
        .padding(.vertical, 6)
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
            showInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .appHitTarget(minWidth: 28, minHeight: 28)
        .help("Model bilgisi")
        .popover(isPresented: $showInfo, arrowEdge: .bottom) {
            infoPopoverContent
        }
    }

    @ViewBuilder
    private var infoPopoverContent: some View {
        let assessment = HubQuantAdvisor.assess(file: file, repoId: repo.repoId, profile: profile)
        VStack(alignment: .leading, spacing: 10) {
            Text(file.filename)
                .font(.caption)
                .fontWeight(.semibold)
            AppTheme.fitBadge(assessment.fit)
            Text(assessment.fitTitle)
                .font(.caption.weight(.medium))
            Text(assessment.fitNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            if assessment.quantLabel != nil {
                Text(assessment.quantSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Dosya: \(ModelMetadataParser.formatFileSize(bytes: file.sizeBytes))")
                Text("RAM: ~\(assessment.estimatedRamGB) GB")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: 300)
    }

    @ViewBuilder
    private var downloadCell: some View {
        Group {
            if installedModel != nil {
                Button("Kullan") {
                    onUse?()
                }
                .buttonStyle(AccentPrimaryButtonStyle())
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
                    .buttonStyle(SecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(tokenMissing)
            }
        }
        .frame(width: 120, alignment: .trailing)
    }
}
