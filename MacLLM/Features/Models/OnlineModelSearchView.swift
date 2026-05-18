import SwiftUI

struct OnlineModelSearchView: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    @State private var searchText = ""
    @State private var results: [HFModelSummary] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selectedRepo: HFModelSummary?
    @State private var repoFiles: [HFGGUFile] = []
    @State private var isLoadingFiles = false
    @State private var filesError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Hugging Face'te model ara (ör. llama 3.2, mistral)", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await runSearch() } }
                if isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Ara") { Task { await runSearch() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            List {
                Section {
                    Text("Popüler GGUF depolarını arayın. İndirmeler Hugging Face CDN üzerinden yapılır.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sonuçlar") {
                    if results.isEmpty && !isSearching {
                        ContentUnavailableView {
                            Label("Arama yapın", systemImage: "cloud")
                        } description: {
                            Text("Örn. \"llama 3\", \"phi-3\", \"mistral 7b\"")
                        }
                    }
                    ForEach(results) { model in
                        Button {
                            Task { await openRepo(model) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.repoId)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        Label(formatDownloads(model.downloads), systemImage: "arrow.down.circle")
                                        if let tag = model.pipelineTag {
                                            Text(tag)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedRepo) { repo in
            RepoFilesSheet(
                repo: repo,
                files: repoFiles,
                isLoading: isLoadingFiles,
                error: filesError,
                downloadService: downloadService,
                onDownload: { file in
                    Task { await downloadFile(repo: repo, file: file) }
                },
                onRefresh: { Task { await loadFiles(for: repo) } }
            )
        }
        .task {
            if results.isEmpty {
                await runSearch()
            }
        }
    }

    private func runSearch() async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            results = try await HuggingFaceHubService.shared.searchModels(query: searchText)
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func openRepo(_ model: HFModelSummary) async {
        selectedRepo = model
        repoFiles = []
        filesError = nil
        await loadFiles(for: model)
    }

    private func loadFiles(for model: HFModelSummary) async {
        isLoadingFiles = true
        filesError = nil
        defer { isLoadingFiles = false }
        do {
            repoFiles = try await HuggingFaceHubService.shared.listGGUFFiles(repoId: model.repoId)
            if repoFiles.isEmpty {
                filesError = "Bu depoda .gguf dosyası bulunamadı."
            }
        } catch {
            filesError = error.localizedDescription
        }
    }

    private func downloadFile(repo: HFModelSummary, file: HFGGUFile) async {
        let entry = CatalogEntry(
            id: "\(repo.repoId)-\(file.filename)",
            name: file.filename,
            description: repo.repoId,
            repoId: repo.repoId,
            filename: file.filename,
            estimatedSizeBytes: max(file.sizeBytes, 1),
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: repo.repoId, filename: file.filename),
            ramHintGB: ramHint(for: file.sizeBytes)
        )
        await appModel.downloadModel(entry)
    }

    private func ramHint(for bytes: Int64) -> Int {
        let gb = Double(bytes) / 1_073_741_824.0
        return Int(ceil(gb * 1.4))
    }

    private func formatDownloads(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

private struct RepoFilesSheet: View {
    let repo: HFModelSummary
    let files: [HFGGUFile]
    let isLoading: Bool
    let error: String?
    @ObservedObject var downloadService: HuggingFaceDownloadService
    let onDownload: (HFGGUFile) -> Void
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Dosyalar yükleniyor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Hata", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Tekrar dene", action: onRefresh)
                    }
                } else {
                    List(files) { file in
                        GGUFFileRow(
                            file: file,
                            download: downloadService.activeDownloads.first {
                                $0.catalogEntry.filename == file.filename &&
                                $0.catalogEntry.repoId == repo.repoId
                            },
                            onDownload: { onDownload(file) }
                        )
                    }
                }
            }
            .navigationTitle(repo.repoId.split(separator: "/").last.map(String.init) ?? repo.repoId)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}

private struct GGUFFileRow: View {
    let file: HFGGUFile
    let download: DownloadTaskInfo?
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.filename)
                .font(.subheadline)
                .lineLimit(2)
            Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let download, download.state == .downloading {
                ProgressView(value: download.progress)
                Text(String(format: "%.0f%% indiriliyor", download.progress * 100))
                    .font(.caption2)
            } else if download?.state == .completed {
                Label("İndirildi", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if download?.state == .failed {
                Text(download?.errorMessage ?? "Hata")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Tekrar indir", action: onDownload)
                    .controlSize(.small)
            } else {
                Button("İndir", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
