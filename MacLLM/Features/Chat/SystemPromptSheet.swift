import SwiftUI

struct SystemPromptSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sistem istemi")
                .font(.headline)

            Text("Model her yanıtta bu talimatları dikkate alır.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 160)
                .padding(8)
                .background(AppTheme.composerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )

            HStack {
                Button("Sıfırla") {
                    draft = ""
                }
                .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                Button("İptal") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Kaydet") {
                    appModel.settings.systemPrompt = draft
                    appModel.saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AccentPrimaryButtonStyle())
                .tint(AppTheme.accent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            draft = appModel.settings.systemPrompt
        }
    }
}
