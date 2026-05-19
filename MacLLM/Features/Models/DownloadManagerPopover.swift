import SwiftUI

/// Toolbar indirme mini menüsü.
struct DownloadManagerPopover: View {
    @ObservedObject var downloadService: HuggingFaceDownloadService
    @Environment(AppModel.self) private var appModel
    @Binding var showAllDownloadsSheet: Bool

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
            Text("İndirmeler")
                .font(.headline)

            if activeDownloads.isEmpty {
                Text("Aktif indirme yok")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(activeDownloads) { download in
                    DownloadTaskRowView(download: download) { entry in
                        Task { await appModel.downloadModel(entry) }
                    }
                    if download.id != activeDownloads.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }

            Button("Tüm indirmeler…") {
                showAllDownloadsSheet = true
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 360)
        .appGlassCard(cornerRadius: AppTheme.panelRadius, material: .thinMaterial)
    }
}

/// Araç çubuğu indirme düğmesi + popover.
struct DownloadToolbarButton: View {
    @ObservedObject var downloadService: HuggingFaceDownloadService
    @Binding var isPresented: Bool
    @Binding var showAllDownloadsSheet: Bool

    private var inProgressCount: Int {
        downloadService.activeDownloads.filter {
            switch $0.state {
            case .downloading, .paused, .queued: return true
            default: return false
            }
        }.count
    }

    private var shouldShowButton: Bool {
        downloadService.hasActiveTransfers || inProgressCount > 0 || isPresented
    }

    var body: some View {
        if shouldShowButton {
            Button {
                isPresented.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18))
                    if inProgressCount > 0 {
                        Text("\(inProgressCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(AppTheme.accent))
                            .offset(x: 6, y: -6)
                            .allowsHitTesting(false)
                    }
                }
                .padding(4)
            }
            .buttonStyle(AccentIconButtonStyle())
            .appHitTarget(minWidth: 32, minHeight: 32)
            .help("İndirmeler")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                DownloadManagerPopover(
                    downloadService: downloadService,
                    showAllDownloadsSheet: $showAllDownloadsSheet
                )
            }
        }
    }
}
