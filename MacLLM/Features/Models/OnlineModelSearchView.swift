import SwiftUI

@MainActor
final class OnlineModelSearchUIState: ObservableObject {
    @Published var searchText = ""
    @Published var results: [HFModelSummary] = []
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var searchTask: Task<Void, Never>?
}

/// Hugging Face Hub araması — depo listesi; detay için `ModelHubDetailView`.
struct OnlineModelSearchView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var ui = OnlineModelSearchUIState()

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let searchError = ui.searchError {
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
                    if ui.results.isEmpty && !ui.isSearching {
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
        let local = ui.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard local.count >= 2, !ui.results.isEmpty else { return ui.results }
        return ui.results.filter { model in
            model.repoId.lowercased().contains(local)
                || model.displayTags.joined(separator: " ").lowercased().contains(local)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Hugging Face Hub'ta ara…", text: $ui.searchText)
                .textFieldStyle(.plain)
                .onSubmit { scheduleSearch() }
                .onChange(of: ui.searchText) { _, _ in scheduleSearch() }
            if ui.isSearching {
                ProgressView().controlSize(.small)
            } else {
                Button("Ara") { scheduleSearch() }
                    .buttonStyle(AccentPrimaryButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.searchFieldRadius))
        .padding()
    }

    private func scheduleSearch() {
        ui.searchTask?.cancel()
        ui.searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        let query = ui.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count < 2 {
            ui.results = []
            ui.searchError = nil
            ui.isSearching = false
            return
        }
        ui.isSearching = true
        ui.searchError = nil
        defer { ui.isSearching = false }
        do {
            ui.results = try await HuggingFaceHubService.shared.searchModels(query: query)
        } catch {
            ui.searchError = UserErrorFormatter.details(for: error).displayText
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
            HubModelAvatarView(repoId: model.repoId, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ModelMetadataParser.repoDisplayName(model.repoId))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if let badge = model.parameterSizeBadge {
                        AppTheme.badge(badge, color: AppTheme.accent)
                    }
                    if model.gated {
                        AppTheme.badge("Kilitli", color: .orange)
                    }
                }
                if let author = ModelMetadataParser.repoAuthor(model.repoId) {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let paramDisplay = model.parameterSizeDisplay {
                    Text(paramDisplay)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
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
