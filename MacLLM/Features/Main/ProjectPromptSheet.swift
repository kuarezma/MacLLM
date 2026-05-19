import SwiftUI

struct ProjectPromptSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var projectName: String {
        appModel.projects.first(where: { $0.id == projectId })?.name ?? "Proje"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proje sistemi istemi")
                .font(.headline)
            Text("«\(projectName)» projesindeki sohbetlere eklenir; genel ayarlarla birleştirilir.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(AppTheme.composerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                }
                .focused($focused)

            HStack {
                Spacer()
                Button("İptal") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") {
                    appModel.updateProjectSystemPrompt(projectId: projectId, prompt: draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 280)
        .onAppear {
            draft = appModel.projects.first(where: { $0.id == projectId })?.systemPrompt ?? ""
            focused = true
        }
    }
}
