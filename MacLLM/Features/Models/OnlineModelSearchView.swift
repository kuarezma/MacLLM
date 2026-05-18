import SwiftUI

/// Hugging Face Hub araması — depo listesi; detay için `ModelHubDetailView`.
struct OnlineModelSearchView: View {
    @Environment(AppModel.self) private var appModel

    @State private var searchText = ""
    @State private var results: [HFModelSummary] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            List {
                Section {
                    Text("Popüler GGUF depolarını arayın. Bir depoya tıklayın — tüm quant sürümleri tablo halinde listelenir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Hub") {
                    if results.isEmpty && !isSearching {
                        ContentUnavailableView {
                            Label("Arama yapın", systemImage: "cloud")
                        } description: {
                            Text("Örn. \"llama 3\", \"mistral 7b\", \"opus\"")
                        }
                    }
                    ForEach(filteredResults) { model in
                        NavigationLink(value: model) {
                            OnlineModelRow(model: model, profile: appModel.systemProfile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filteredResults: [HFModelSummary] {
        let local = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard local.count >= 2, !results.isEmpty else { return results }
        return results.filter { model in
            model.repoId.lowercased().contains(local)
                || model.displayTags.joined(separator: " ").lowercased().contains(local)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Hugging Face Hub'ta ara…", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { scheduleSearch() }
                .onChange(of: searchText) { _, _ in scheduleSearch() }
            if isSearching {
                ProgressView().controlSize(.small)
            } else {
                Button("Ara") { scheduleSearch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.searchFieldRadius))
        .padding()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count < 2 {
            results = []
            searchError = nil
            isSearching = false
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            results = try await HuggingFaceHubService.shared.searchModels(query: query)
        } catch {
            searchError = error.localizedDescription
        }
    }
}

// MARK: - Search result row

private struct OnlineModelRow: View {
    let model: HFModelSummary
    let profile: MacSystemProfile

    private var fitLevel: ModelFitLevel? {
        let entry = CatalogEntry(
            id: model.id,
            name: model.repoId,
            description: "",
            repoId: model.repoId,
            filename: "model.Q4_K_M.gguf",
            estimatedSizeBytes: 2_000_000_000,
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: model.repoId, filename: "model.Q4_K_M.gguf"),
            ramHintGB: estimateRamHint()
        )
        return ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first?.fit
    }

    private func estimateRamHint() -> Int {
        if let param = model.parameterSize, param.hasSuffix("B"),
           let num = Double(param.dropLast()) {
            return Int(ceil(num * 0.7))
        }
        return 8
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ModelMetadataParser.repoDisplayName(model.repoId))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if model.gated {
                        AppTheme.badge("Gated", color: .orange)
                    }
                }
                if let author = ModelMetadataParser.repoAuthor(model.repoId) {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label(ModelMetadataParser.formatCount(model.downloads), systemImage: "arrow.down.circle")
                    Label(ModelMetadataParser.formatCount(model.likes), systemImage: "heart")
                    if let updated = ModelMetadataParser.relativeDate(model.lastModified) {
                        Text(updated)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !model.displayTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(model.displayTags.prefix(4), id: \.self) { tag in
                            AppTheme.tagBadge(tag)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let fitLevel {
                    AppTheme.fitBadge(fitLevel)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}
