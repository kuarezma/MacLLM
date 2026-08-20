import SwiftUI

@MainActor
final class NewProjectUIState: ObservableObject {
    @Published var name = ""
    @Published var systemPrompt = ""
    @Published var selectedFolderURL: URL?
}

struct NewProjectSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var ui = NewProjectUIState()
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Yeni Proje & Çalışma Alanı")
                .font(.headline)

            Text("Sohbetleri gruplayın veya yerel proje klasörünüzü bağlayarak modelin dosyalarınız üzerinde çalışmasını sağlayın.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            TextField("Proje adı", text: $ui.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            // Workspace Folder Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Proje Klasörü / Workspace (isteğe bağlı)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)

                HStack {
                    if let selectedFolderURL = ui.selectedFolderURL {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(selectedFolderURL.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Button("Kaldır") {
                            ui.selectedFolderURL = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    } else {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(.secondary)
                        Text("Klasör bağlı değil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Klasör Seç…") {
                            if let url = ProjectWorkspaceService.shared.pickWorkspaceDirectory() {
                                ui.selectedFolderURL = url
                                if ui.name.isEmpty {
                                    ui.name = url.lastPathComponent
                                }
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            Text("Proje sistemi istemi (isteğe bağlı)")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
            TextEditor(text: $ui.systemPrompt)
                .font(.body)
                .frame(height: 60)
                .padding(6)
                .background(AppTheme.composerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("İptal") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Oluştur") {
                    var bookmark: Data?
                    var path: String?
                    if let selectedFolderURL = ui.selectedFolderURL {
                        bookmark = ProjectWorkspaceService.shared.createBookmarkData(for: selectedFolderURL)
                        path = selectedFolderURL.path
                    }
                    appModel.createProject(
                        named: ui.name,
                        systemPrompt: ui.systemPrompt,
                        rootDirectoryBookmark: bookmark,
                        rootDirectoryPath: path
                    )
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AccentPrimaryButtonStyle())
                .tint(AppTheme.accent)
                .disabled(ui.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { nameFocused = true }
    }
}
