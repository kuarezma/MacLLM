import Foundation
import AppKit
import OSLog

struct WorkspaceNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let fullPath: String
    let relativePath: String
    let isDirectory: Bool
    var children: [WorkspaceNode]?
    let fileExtension: String
    let sizeBytes: Int64

    init(
        name: String,
        fullPath: String,
        relativePath: String,
        isDirectory: Bool,
        children: [WorkspaceNode]? = nil,
        fileExtension: String = "",
        sizeBytes: Int64 = 0
    ) {
        self.id = relativePath.isEmpty ? fullPath : relativePath
        self.name = name
        self.fullPath = fullPath
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.children = children
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
    }

    var systemIcon: String {
        if isDirectory { return "folder.fill" }
        switch fileExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json", "yaml", "yml", "toml": return "doc.text"
        case "md", "txt", "rtf": return "doc.plaintext"
        case "pdf": return "doc.viewfinder"
        case "png", "jpg", "jpeg", "webp", "gif": return "photo"
        case "sh", "zsh", "bash": return "terminal"
        default: return "doc"
        }
    }
}

final class ProjectWorkspaceService: @unchecked Sendable {
    static let shared = ProjectWorkspaceService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacLLM", category: "Workspace")
    private let fileManager = FileManager.default

    private var activeSecurityScopedURL: URL?
    private var isAccessingSecurityScoped = false

    private let defaultIgnoredDirectories: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", "build", ".build",
        "DerivedData", ".DS_Store", "Pods", "Carthage", ".idea",
        ".vscode", "__pycache__", ".venv", "venv", "dist", ".next"
    ]

    private let defaultIgnoredExtensions: Set<String> = [
        "o", "a", "dylib", "so", "dll", "exe", "bin", "pyc", "class",
        "jar", "war", "zip", "tar", "gz", "7z", "dmg", "pkg", "png", "jpg", "jpeg", "webp", "mp4", "mov", "mp3", "wav"
    ]

    private init() {}

    deinit {
        stopAccessingCurrentWorkspace()
    }

    var activeWorkspaceRootURL: URL? {
        activeSecurityScopedURL
    }

    var activeWorkspacePath: String? {
        activeSecurityScopedURL?.path
    }

    // MARK: - Security-Scoped Bookmark Management

    @MainActor
    func pickWorkspaceDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Projeyi Seç"
        panel.title = "Proje Çalışma Dizinini Seçin"

        if panel.runModal() == .OK, let selectedURL = panel.url {
            return selectedURL
        }
        return nil
    }

    func createBookmarkData(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.error("Bookmark oluşturulamadı url=\(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    func activateWorkspace(bookmarkData: Data?, fallbackPath: String?) -> URL? {
        stopAccessingCurrentWorkspace()

        if let bookmarkData {
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if resolvedURL.startAccessingSecurityScopedResource() {
                    activeSecurityScopedURL = resolvedURL
                    isAccessingSecurityScoped = true
                    logger.info("Security-scoped workspace aktif: \(resolvedURL.path)")
                    return resolvedURL
                }
            } catch {
                logger.error("Bookmark çözülemedi: \(error.localizedDescription)")
            }
        }

        if let fallbackPath, fileManager.fileExists(atPath: fallbackPath) {
            let url = URL(fileURLWithPath: fallbackPath)
            activeSecurityScopedURL = url
            isAccessingSecurityScoped = false
            logger.info("Fallback workspace aktif: \(fallbackPath)")
            return url
        }

        return nil
    }

    func stopAccessingCurrentWorkspace() {
        if isAccessingSecurityScoped, let url = activeSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURL = nil
        isAccessingSecurityScoped = false
    }

    // MARK: - Directory Tree

    func loadDirectoryTree(maxDepth: Int = 4) -> [WorkspaceNode] {
        guard let rootURL = activeSecurityScopedURL else { return [] }
        return scanDirectory(url: rootURL, relativeTo: rootURL, currentDepth: 0, maxDepth: maxDepth)
    }

    private func scanDirectory(
        url: URL,
        relativeTo rootURL: URL,
        currentDepth: Int,
        maxDepth: Int
    ) -> [WorkspaceNode] {
        guard currentDepth <= maxDepth else { return [] }
        do {
            let items = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .nameKey],
                options: [.skipsHiddenFiles]
            )

            var nodes: [WorkspaceNode] = []
            for item in items.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let name = item.lastPathComponent
                if defaultIgnoredDirectories.contains(name) { continue }

                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let relPath = makeRelativePath(of: item, relativeTo: rootURL)

                if isDirectory {
                    let children = scanDirectory(
                        url: item,
                        relativeTo: rootURL,
                        currentDepth: currentDepth + 1,
                        maxDepth: maxDepth
                    )
                    nodes.append(WorkspaceNode(
                        name: name,
                        fullPath: item.path,
                        relativePath: relPath,
                        isDirectory: true,
                        children: children
                    ))
                } else {
                    let ext = item.pathExtension
                    if defaultIgnoredExtensions.contains(ext.lowercased()) { continue }
                    let fileSize = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    nodes.append(WorkspaceNode(
                        name: name,
                        fullPath: item.path,
                        relativePath: relPath,
                        isDirectory: false,
                        fileExtension: ext,
                        sizeBytes: Int64(fileSize)
                    ))
                }
            }
            return nodes
        } catch {
            logger.error("Dizin taranamadı url=\(url.path): \(error.localizedDescription)")
            return []
        }
    }

    func listAllFiles(maxCount: Int = 500) -> [String] {
        guard let rootURL = activeSecurityScopedURL else { return [] }
        var result: [String] = []
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if defaultIgnoredDirectories.contains(filename) {
                enumerator.skipDescendants()
                continue
            }
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir {
                let ext = fileURL.pathExtension.lowercased()
                if !defaultIgnoredExtensions.contains(ext) {
                    result.append(makeRelativePath(of: fileURL, relativeTo: rootURL))
                    if result.count >= maxCount { break }
                }
            }
        }
        return result.sorted()
    }

    // MARK: - File Operations

    func resolveFileURL(relativePath: String) -> URL? {
        guard let rootURL = activeSecurityScopedURL else { return nil }
        let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rootURL.appendingPathComponent(clean)
    }

    func readFile(
        relativePath: String,
        startLine: Int? = nil,
        endLine: Int? = nil
    ) throws -> (content: String, totalLines: Int) {
        guard let targetURL = resolveFileURL(relativePath: relativePath) else {
            throw NSError(domain: "MacLLM.Workspace", code: 404, userInfo: [NSLocalizedDescriptionKey: "Proje dizini aktif değil."])
        }
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw NSError(domain: "MacLLM.Workspace", code: 404, userInfo: [NSLocalizedDescriptionKey: "Dosya bulunamadı: \(relativePath)"])
        }

        let fullText = try String(contentsOf: targetURL, encoding: .utf8)
        let lines = fullText.components(separatedBy: "\n")
        let totalLines = lines.count

        let start = max(1, min(startLine ?? 1, totalLines))
        let end = max(start, min(endLine ?? totalLines, totalLines))

        let selected = lines[(start - 1)..<end]
        return (selected.joined(separator: "\n"), totalLines)
    }

    func writeFile(relativePath: String, content: String) throws {
        guard let targetURL = resolveFileURL(relativePath: relativePath) else {
            throw NSError(domain: "MacLLM.Workspace", code: 400, userInfo: [NSLocalizedDescriptionKey: "Proje dizini aktif değil."])
        }

        let parentDir = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try createBackup(for: targetURL)
        try content.write(to: targetURL, atomically: true, encoding: .utf8)
        logger.info("Dosya yazıldı: \(relativePath)")
    }

    func preparePatch(
        relativePath: String,
        searchBlock: String,
        replaceBlock: String
    ) throws -> (original: String, proposed: String) {
        guard let targetURL = resolveFileURL(relativePath: relativePath) else {
            throw NSError(domain: "MacLLM.Workspace", code: 400, userInfo: [NSLocalizedDescriptionKey: "Proje dizini aktif değil."])
        }
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw NSError(domain: "MacLLM.Workspace", code: 404, userInfo: [NSLocalizedDescriptionKey: "Dosya bulunamadı: \(relativePath)"])
        }

        let originalContent = try String(contentsOf: targetURL, encoding: .utf8)
        guard originalContent.contains(searchBlock) else {
            throw NSError(
                domain: "MacLLM.Workspace",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Değiştirilecek kod bloğu dosyada birebir eşleşmedi."]
            )
        }

        let proposedContent = originalContent.replacingOccurrences(of: searchBlock, with: replaceBlock)
        return (originalContent, proposedContent)
    }

    func applyPatch(relativePath: String, proposedContent: String) throws {
        try writeFile(relativePath: relativePath, content: proposedContent)
    }

    func createBackup(for fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        guard let rootURL = activeSecurityScopedURL else { return }

        let backupsDir = rootURL.appendingPathComponent(".macllm/backups", isDirectory: true)
        if !fileManager.fileExists(atPath: backupsDir.path) {
            try fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = fileURL.lastPathComponent
        let backupURL = backupsDir.appendingPathComponent("\(filename).\(timestamp).bak")
        try fileManager.copyItem(at: fileURL, to: backupURL)
    }

    private func makeRelativePath(of fileURL: URL, relativeTo rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            var rel = String(filePath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        }
        return fileURL.lastPathComponent
    }
}
