import SwiftUI

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yeni proje")
                .font(.headline)

            Text("Sohbetleri konuya göre gruplayın.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            TextField("Proje adı", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            HStack {
                Spacer()
                Button("İptal") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Oluştur") {
                    appModel.createProject(named: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { nameFocused = true }
    }
}
