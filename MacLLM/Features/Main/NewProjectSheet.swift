import SwiftUI

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var systemPrompt = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yeni proje")
                .font(.headline)

            Text("Sohbetleri konuya göre gruplayın. İsteğe bağlı proje sistemi istemi tüm sohbetlere eklenir.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            TextField("Proje adı", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            Text("Proje sistemi istemi (isteğe bağlı)")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
            TextEditor(text: $systemPrompt)
                .font(.body)
                .frame(height: 72)
                .padding(6)
                .background(AppTheme.composerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("İptal") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Oluştur") {
                    appModel.createProject(named: name, systemPrompt: systemPrompt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AccentPrimaryButtonStyle())
                .tint(AppTheme.accent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { nameFocused = true }
    }
}
