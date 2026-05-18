import SwiftUI

/// Tüm aktif ve yakın zamanda biten indirmeleri gösterir.
struct ActiveDownloadsPanel: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject var downloadService: HuggingFaceDownloadService
    var style: Style = .full

    enum Style {
        case compact
        case full
    }

    private var visibleDownloads: [DownloadTaskInfo] {
        downloadService.activeDownloads.filter { info in
            switch info.state {
            case .downloading, .paused, .queued:
                return true
            case .completed, .failed, .cancelled:
                return true
            }
        }
    }

    private var inProgressCount: Int {
        visibleDownloads.filter { $0.state == .downloading || $0.state == .paused || $0.state == .queued }.count
    }

    var body: some View {
        if visibleDownloads.isEmpty {
            EmptyView()
        } else if style == .compact {
            compactBody
        } else {
            fullBody
        }
    }

    @ViewBuilder
    private var compactBody: some View {
        DisclosureGroup {
            downloadList
        } label: {
            Label {
                Text("İndirilen modeller (\(inProgressCount))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var fullBody: some View {
        Section {
            downloadList
        } header: {
            HStack {
                Text("İndirilenler")
                Spacer()
                if inProgressCount > 0 {
                    Text("\(inProgressCount) aktif")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadList: some View {
        ForEach(visibleDownloads) { download in
            ActiveDownloadRow(download: download, onRetry: { entry in
                Task { await appModel.downloadModel(entry) }
            })
        }
    }
}

private struct ActiveDownloadRow: View {
    let download: DownloadTaskInfo
    let onRetry: (CatalogEntry) -> Void
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.catalogEntry.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Text(download.catalogEntry.repoId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                stateBadge
            }

            switch download.state {
            case .downloading, .paused:
                DownloadProgressView(
                    download: download,
                    onPause: { downloadService.pauseDownload(id: download.id) },
                    onResume: { downloadService.resumeDownload(id: download.id) },
                    onCancel: { downloadService.cancelDownload(id: download.id) },
                    supportsPause: downloadService.downloadSupportsPause(id: download.id)
                )
            case .queued:
                ProgressView()
                    .controlSize(.small)
                Text("Kuyrukta…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .completed:
                Label("Tamamlandı — model yükleniyor veya hazır", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Text(download.errorMessage ?? "İndirme başarısız")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Tekrar indir") {
                    onRetry(download.catalogEntry)
                }
                .controlSize(.small)
            case .cancelled:
                Label("İptal edildi", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch download.state {
        case .downloading:
            Text("İndiriliyor")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15))
                .clipShape(Capsule())
        case .paused:
            Text("Duraklatıldı")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15))
                .clipShape(Capsule())
        case .completed:
            EmptyView()
        case .failed:
            EmptyView()
        case .cancelled:
            EmptyView()
        case .queued:
            EmptyView()
        }
    }
}
