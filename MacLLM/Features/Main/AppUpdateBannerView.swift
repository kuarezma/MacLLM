import SwiftUI

struct AppUpdateBannerView: View {
    @Environment(AppUpdateController.self) private var appUpdate

    var body: some View {
        if let update = appUpdate.availableUpdate {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Güncelleme mevcut: MacLLM \(update.version)")
                            .font(.headline)
                        Text("Şu anki sürüm: \(appUpdate.currentVersion) → yeni: \(update.version) (\(update.preferredAssetLabel))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        appUpdate.dismissUpdateForNow()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Daha sonra hatırlat")
                }

                if appUpdate.isDownloading {
                    ProgressView(value: appUpdate.downloadProgress)
                    Text(appUpdate.downloadStatus ?? "İndiriliyor…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            Task { await appUpdate.downloadAndOpenUpdate() }
                        } label: {
                            Label("İndir ve kur", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(AccentPrimaryButtonStyle())

                        Button("Sürüm notları") {
                            appUpdate.openReleasePage()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                if let status = appUpdate.downloadStatus, !appUpdate.isDownloading {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.blue.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                    .strokeBorder(.blue.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}
