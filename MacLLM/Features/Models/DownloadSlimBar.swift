import SwiftUI

/// Sohbet üstünde ince indirme ilerleme şeridi.
struct DownloadSlimBar: View {
    @ObservedObject var downloadService: HuggingFaceDownloadService
    @Binding var showDownloadsPopover: Bool

    private var primaryDownload: DownloadTaskInfo? {
        let active = downloadService.activeDownloads.filter {
            switch $0.state {
            case .downloading, .paused, .queued: return true
            default: return false
            }
        }
        return active.sorted { lhs, rhs in
            priority(lhs.state) > priority(rhs.state)
        }.first
    }

    private var extraCount: Int {
        let active = downloadService.activeDownloads.filter {
            switch $0.state {
            case .downloading, .paused, .queued: return true
            default: return false
            }
        }
        return max(0, active.count - 1)
    }

    var body: some View {
        if let download = primaryDownload {
            Button {
                showDownloadsPopover = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentTertiary)
                    Text(download.catalogEntry.filename)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.primaryText)
                    GradientProgressBar(progress: download.progress, height: 3)
                        .frame(maxWidth: 120)
                    Text(String(format: "%.0f%%", download.progress * 100))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.accentTertiary)
                    if extraCount > 0 {
                        Text("+\(extraCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppTheme.contentPadding)
                .padding(.vertical, 6)
                .frame(height: AppTheme.downloadSlimBarHeight)
                .appGlassCard(cornerRadius: 0, material: .thinMaterial)
            }
            .buttonStyle(.plain)
        }
    }

    private func priority(_ state: DownloadState) -> Int {
        switch state {
        case .downloading: return 3
        case .paused: return 2
        case .queued: return 1
        default: return 0
        }
    }
}
