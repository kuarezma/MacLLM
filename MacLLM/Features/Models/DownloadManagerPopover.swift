import SwiftUI

/// Hub tarzı indirme yöneticisi — araç çubuğu popover.
struct DownloadManagerPopover: View {
    @ObservedObject var downloadService: HuggingFaceDownloadService

    private var activeDownloads: [DownloadTaskInfo] {
        downloadService.activeDownloads.filter {
            switch $0.state {
            case .downloading, .paused, .queued: return true
            default: return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("İndiriliyor")
                .font(.headline)

            if activeDownloads.isEmpty {
                Text("Aktif indirme yok")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeDownloads) { download in
                    downloadCard(download)
                    if download.id != activeDownloads.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    @ViewBuilder
    private func downloadCard(_ download: DownloadTaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(download.catalogEntry.filename)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    downloadService.cancelDownload(id: download.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("İndirmeyi iptal et")
            }

            ProgressView(value: download.progress)
                .tint(.red)

            HStack {
                Text(String(format: "%.0f%%", download.progress * 100))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Spacer()
                Text(
                    "\(DownloadMetrics.formatBytes(download.bytesReceived)) / \(DownloadMetrics.formatBytes(download.totalBytes))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }
}

/// Araç çubuğu indirme düğmesi + popover.
struct DownloadToolbarButton: View {
    @ObservedObject var downloadService: HuggingFaceDownloadService
    @Binding var isPresented: Bool

    private var inProgressCount: Int {
        downloadService.activeDownloads.filter {
            switch $0.state {
            case .downloading, .paused, .queued: return true
            default: return false
            }
        }.count
    }

    var body: some View {
        if downloadService.hasActiveTransfers || inProgressCount > 0 {
            Button {
                isPresented = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle")
                    if inProgressCount > 0 {
                        Text("\(inProgressCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(.red))
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .help("İndirmeler")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                DownloadManagerPopover(downloadService: downloadService)
            }
        }
    }
}
