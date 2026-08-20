import SwiftUI
import AppKit

@MainActor
final class WorkspaceSidebarUIState: ObservableObject {
    @Published var fileFilter = ""
    @Published var treeNodes: [WorkspaceNode] = []
    @Published var isRefreshing = false
}

struct WorkspaceSidebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var ui = WorkspaceSidebarUIState()

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(ProjectWorkspaceService.shared.activeWorkspaceRootURL?.lastPathComponent ?? "Çalışma Alanı")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    
                    if let path = ProjectWorkspaceService.shared.activeWorkspacePath {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Spacer()

                Button {
                    refreshTree()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Dosya ağacını yenile")

                Menu {
                    Button("Finder'da Göster") {
                        if let url = ProjectWorkspaceService.shared.activeWorkspaceRootURL {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                    }
                    Button("Terminal'de Aç") {
                        if let url = ProjectWorkspaceService.shared.activeWorkspaceRootURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider().opacity(0.6)

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                
                TextField("Dosya filtrele…", text: $ui.fileFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !ui.fileFilter.isEmpty {
                    Button {
                        ui.fileFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .padding(8)

            // Tree Content or Empty State
            if ProjectWorkspaceService.shared.activeWorkspaceRootURL == nil {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.accent.opacity(0.7))
                    
                    Text("Çalışma Dizini Bağlı Değil")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("Bu projeye ait dosyaları görüntülemek ve düzenlemek için proje ayarlarından klasör seçin.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    if let id = appModel.selectedProjectId {
                        Button("Klasör Bağla…") {
                            appModel.projectPromptEditId = id
                            appModel.showProjectPromptSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredNodes.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Eşleşen dosya yok")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    OutlineGroup(filteredNodes, children: \.children) { node in
                        nodeRow(node)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear {
            refreshTree()
        }
        .onChange(of: appModel.selectedProjectId) { _, _ in
            refreshTree()
        }
    }

    private var filteredNodes: [WorkspaceNode] {
        let q = ui.fileFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return ui.treeNodes }
        return filterNodes(ui.treeNodes, query: q)
    }

    private func filterNodes(_ nodes: [WorkspaceNode], query: String) -> [WorkspaceNode] {
        var result: [WorkspaceNode] = []
        for node in nodes {
            if node.isDirectory {
                let matchedChildren = filterNodes(node.children ?? [], query: query)
                if !matchedChildren.isEmpty || node.name.lowercased().contains(query) {
                    var copy = node
                    copy.children = matchedChildren
                    result.append(copy)
                }
            } else if node.name.lowercased().contains(query) || node.relativePath.lowercased().contains(query) {
                result.append(node)
            }
        }
        return result
    }

    @ViewBuilder
    private func nodeRow(_ node: WorkspaceNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: node.systemIcon)
                .font(.system(size: 12))
                .foregroundStyle(nodeIconColor(node))

            Text(node.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            if !node.isDirectory {
                Button {
                    insertFileMention(node.relativePath)
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 18, height: 18)
                        .background(AppTheme.accent.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Bu dosyayı sohbete @referans olarak ekle")
            }
        }
        .contextMenu {
            if !node.isDirectory {
                Button("Sohbete @referans ekle") {
                    insertFileMention(node.relativePath)
                }
                Button("Dosya Yolunu Kopyala") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.relativePath, forType: .string)
                }
            }
            Button("Finder'da Göster") {
                NSWorkspace.shared.selectFile(node.fullPath, inFileViewerRootedAtPath: "")
            }
        }
    }

    private func nodeIconColor(_ node: WorkspaceNode) -> Color {
        if node.isDirectory {
            return AppTheme.accent
        }
        switch node.fileExtension.lowercased() {
        case "swift": return Color(red: 0.98, green: 0.44, blue: 0.25)
        case "py": return Color(red: 0.25, green: 0.55, blue: 0.95)
        case "js", "ts", "jsx", "tsx": return Color(red: 0.92, green: 0.75, blue: 0.2)
        case "json", "yaml", "yml", "toml": return Color(red: 0.65, green: 0.45, blue: 0.95)
        case "md", "txt": return Color(red: 0.35, green: 0.78, blue: 0.95)
        case "sh", "zsh", "bash": return Color(red: 0.25, green: 0.8, blue: 0.45)
        default: return Color.secondary
        }
    }

    private func refreshTree() {
        ui.treeNodes = ProjectWorkspaceService.shared.loadDirectoryTree(maxDepth: 4)
    }

    private func insertFileMention(_ relativePath: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertFileMentionToComposer"),
            object: nil,
            userInfo: ["mention": "@\(relativePath) "]
        )
    }
}
