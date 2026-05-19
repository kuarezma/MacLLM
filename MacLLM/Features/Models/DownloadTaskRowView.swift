import SwiftUI

/// İndirme satırı — popover, slim bar ve Hub panelinde paylaşılır.
struct DownloadTaskRowView: View {
    let download: DownloadTaskInfo
    var compact: Bool = false
    var onRetry: ((CatalogEntry) -> Void)?

    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.catalogEntry.filename)
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.medium))
                        .lineLimit(compact ? 1 : 2)
                    if !compact {
                        Text(download.catalogEntry.repoId)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if !compact {
                    stateBadge
                }
                Button {
                    downloadService.cancelDownload(id: download.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .appHitTarget(minWidth: 24, minHeight: 24)
                .help("İndirmeyi iptal et")
            }

            switch download.state {
            case .downloading, .paused:
                GradientProgressBar(progress: download.progress, height: compact ? 3 : 5)
                HStack {
                    Text(String(format: "%.0f%%", download.progress * 100))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    if !compact {
                        Text(DownloadMetrics.formatSpeed(bytesPerSecond: download.bytesPerSecond))
                        Text("·")
                        Text(DownloadMetrics.formatETA(seconds: download.estimatedSecondsRemaining))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .font(.caption)
                .monospacedDigit()

                if !compact {
                    Text("\(DownloadMetrics.formatBytes(download.bytesReceived)) / \(DownloadMetrics.formatBytes(download.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)

                    HStack(spacing: 8) {
                        if downloadService.downloadSupportsPause(id: download.id) {
                            if download.state == .paused {
                                Button("Devam") {
                                    downloadService.resumeDownload(id: download.id)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .controlSize(.small)
                            } else {
                                Button("Duraklat") {
                                    downloadService.pauseDownload(id: download.id)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .controlSize(.small)
                            }
                        }
                        Button("İptal") {
                            downloadService.cancelDownload(id: download.id)
                        }
                        .buttonStyle(DestructiveButtonStyle())
                        .controlSize(.small)
                    }
                }
            case .queued:
                GradientProgressBar(progress: 0.05, height: 3)
                Text("Kuyrukta…")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            case .failed:
                Text(download.errorMessage ?? "İndirme başarısız")
                    .font(.caption)
                    .foregroundStyle(.red)
                if let onRetry {
                    Button("Tekrar indir") { onRetry(download.catalogEntry) }
                        .buttonStyle(SecondaryButtonStyle())
                        .controlSize(.small)
                }
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch download.state {
        case .downloading:
            AppTheme.badge("İndiriliyor", color: AppTheme.accentTertiary)
        case .paused:
            AppTheme.badge("Duraklatıldı", color: .orange)
        default:
            EmptyView()
        }
    }
}
