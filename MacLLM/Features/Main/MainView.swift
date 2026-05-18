import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = appModel

        NavigationSplitView(columnVisibility: $columnVisibility) {
            ModelSidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            ChatView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if model.isLoadingModel || inferenceService.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    model.showCatalog = true
                } label: {
                    Label("Çevrimiçi Model", systemImage: "cloud.arrow.down")
                }
                Button {
                    model.newChat()
                } label: {
                    Label("Yeni Sohbet", systemImage: "square.and.pencil")
                }
                SettingsLink {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                .help("Ayarlar (⌘,)")
            }
        }
        .sheet(isPresented: $model.showCatalog) {
            ModelCatalogView()
        }
        .safeAreaInset(edge: .bottom) {
            if let status = model.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
        }
    }
}

struct ModelSidebarView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel

        List(selection: $model.selectedModelId) {
            Section("Yüklü Modeller") {
                if model.installedModels.isEmpty {
                    ContentUnavailableView {
                        Label("Model yok", systemImage: "brain")
                    } description: {
                        Text("Katalogdan bir model indirin veya GGUF dosyası içe aktarın.")
                    } actions: {
                        Button("Model Ekle") { model.showCatalog = true }
                    }
                } else {
                    ForEach(model.installedModels) { installed in
                        ModelRowView(model: installed, isSelected: model.selectedModelId == installed.id)
                            .tag(installed.id)
                            .onTapGesture {
                                Task { await model.selectModel(installed) }
                            }
                            .contextMenu {
                                Button("Sil", role: .destructive) {
                                    Task { await model.deleteModel(installed) }
                                }
                            }
                    }
                }
            }

            Section("Sohbetler") {
                ForEach(model.sessions) { session in
                    Button(session.title) {
                        model.loadSession(session)
                    }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                }
            }

            Section {
                LabeledContent("Disk kullanımı", value: model.diskUsageFormatted)
            }

            Section {
                SettingsLink {
                    Label("Ayarlar…", systemImage: "gearshape")
                }
                .help("Çıkarım, örnekleme, sistem mesajı (⌘,)")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MacLLM")
    }
}

struct ModelRowView: View {
    let model: InstalledModel
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}
