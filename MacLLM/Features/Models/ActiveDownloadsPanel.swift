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
            case .downloading, .paused, .queued, .failed:
                return true
            case .completed, .cancelled:
                return style == .full
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(AppTheme.accentTertiary)
                Text("Aktif indirmeler (\(inProgressCount))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            downloadList
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 0.5)
        }
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
                } else if !visibleDownloads.isEmpty {
                    Text("\(visibleDownloads.count) kayıt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadList: some View {
        ForEach(visibleDownloads) { download in
            DownloadTaskRowView(download: download) { entry in
                Task { await appModel.downloadModel(entry) }
            }
            .padding(.vertical, 4)
        }
    }
}
