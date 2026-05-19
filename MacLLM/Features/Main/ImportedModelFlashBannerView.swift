import SwiftUI

struct ImportedModelFlashBannerView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.showImportedFlashBanner {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("İçe aktarılmış modeller için Flash Attention kapatıldı")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "Bazı GGUF dosyalarında (ör. Qwopus) çıkarım hatasını önlemek için. "
                            + "Ayarlar → Performans'tan tekrar açabilirsiniz."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    appModel.dismissImportedFlashBanner()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Kapat")
            }
            .padding(12)
            .background(.orange.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                    .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}
