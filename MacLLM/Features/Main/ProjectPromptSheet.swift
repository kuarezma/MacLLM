import SwiftUI

@MainActor
final class ProjectPromptUIState: ObservableObject {
    @Published var draft = ""
    @Published var folderPath: String?
    @Published var folderBookmark: Data?
}

struct ProjectPromptSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.presentationMode) private var presentationMode
    let projectId: UUID
    @StateObject private var ui = ProjectPromptUIState()
    @FocusState private var focused: Bool

    private var project: ChatProject? {
        appModel.projects.first(where: { $0.id == projectId })
    }

    private var projectName: String {
        project?.name ?? "Proje"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Proje Ayarları & Çalışma Alanı")
                .font(.headline)
            Text("«\(projectName)» projesindeki sohbetlere eklenir; genel ayarlarla birleştirilir.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            // Workspace Folder
            VStack(alignment: .leading, spacing: 4) {
                Text("Bağlı Proje Klasörü")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)

                HStack {
                    if let folderPath = ui.folderPath, !folderPath.isEmpty {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(folderPath)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Kaldır") {
                            ui.folderPath = nil
                            ui.folderBookmark = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(.secondary)
                        Text("Klasör bağlı değil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Klasör Seç…") {
                            if let url = ProjectWorkspaceService.shared.pickWorkspaceDirectory() {
                                ui.folderPath = url.path
                                ui.folderBookmark = ProjectWorkspaceService.shared.createBookmarkData(for: url)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            Text("Proje sistemi istemi & geliştirme kuralları")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)

            TextEditor(text: $ui.draft)
                .font(.body)
                .frame(minHeight: 100)
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
                Button("İptal") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") {
                    appModel.updateProjectDetails(
                        projectId: projectId,
                        prompt: ui.draft,
                        rootDirectoryBookmark: ui.folderBookmark,
                        rootDirectoryPath: ui.folderPath
                    )
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AccentPrimaryButtonStyle())
                .tint(AppTheme.accent)
            }
        }
        .padding(20)
        .frame(width: 480, height: 340)
        .onAppear {
            if let p = project {
                ui.draft = p.systemPrompt
                ui.folderPath = p.rootDirectoryPath
                ui.folderBookmark = p.rootDirectoryBookmark
            }
            focused = true
        }
    }
}
