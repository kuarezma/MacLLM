import SwiftUI

@MainActor
final class SystemPromptUIState: ObservableObject {
    @Published var draft: String = ""
}

struct SystemPromptSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var ui = SystemPromptUIState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sistem istemi")
                .font(.headline)

            Text("Model her yanıtta bu talimatları dikkate alır.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            TextEditor(text: $ui.draft)
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
                    ui.draft = ""
                }
                .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                Button("İptal") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Kaydet") {
                    appModel.settings.systemPrompt = ui.draft
                    appModel.saveSettings()
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AccentPrimaryButtonStyle())
                .tint(AppTheme.accent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            ui.draft = appModel.settings.systemPrompt
        }
    }
}
