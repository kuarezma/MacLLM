import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "Genel"
    case model = "Model"
    case sampling = "Örnekleme"
    case chat = "Sohbet"
    case huggingFace = "Hugging Face"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .model: return "cpu"
        case .sampling: return "slider.horizontal.3"
        case .chat: return "bubble.left.and.bubble.right"
        case .huggingFace: return "cloud"
        }
    }
}

@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppUpdateController.self) private var appUpdate
    @State private var tab: SettingsTab = .general
    @State private var stopText = ""

    var body: some View {
        @Bindable var model = appModel

        NavigationSplitView {
            List(selection: $tab) {
                ForEach(SettingsTab.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Form {
                switch tab {
                case .general:
                    generalSection(model: appModel)
                case .model:
                    modelSection(model: appModel)
                case .sampling:
                    samplingSection(model: appModel)
                case .chat:
                    chatSection(model: appModel)
                case .huggingFace:
                    huggingFaceSection()
                }
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle(tab.rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Ollama varsayılanları") {
                        model.settings = InferenceSettings.ollamaDefaults
                        model.settings.threadCount = Int32(
                            max(1, min(8, model.systemProfile.processorCount - 2))
                        )
                        syncStopText(from: model.settings)
                    }
                    Button("Kaydet") {
                        model.settings.stopSequencesText = stopText
                        model.saveSettings()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("Kapatırken de otomatik kaydedilir")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            syncStopText(from: model.settings)
        }
        .onDisappear {
            model.settings.stopSequencesText = stopText
            model.saveSettings()
        }
    }

    @ViewBuilder
    private func generalSection(model: AppModel) -> some View {
        @Bindable var updates = appUpdate
        Section("Uygulama") {
            LabeledContent("Sürüm", value: appUpdate.currentVersion)
            LabeledContent("Bu Mac", value: model.systemProfile.displaySummary)
            LabeledContent("Çıkarım motoru", value: "llama.cpp + Metal")
        }

        Section("Güncellemeler") {
            Toggle("Açılışta güncellemeleri kontrol et", isOn: $updates.autoCheckEnabled)
            if let last = appUpdate.lastCheckDate {
                LabeledContent("Son kontrol", value: last.formatted(date: .abbreviated, time: .shortened))
            }
            HStack {
                Button {
                    Task { await appUpdate.checkForUpdates(userInitiated: true) }
                } label: {
                    if appUpdate.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Güncellemeleri denetle")
                    }
                }
                .disabled(appUpdate.isChecking || appUpdate.isDownloading)

                if appUpdate.availableUpdate != nil {
                    Button("İndir ve kur") {
                        Task { await appUpdate.downloadAndOpenUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appUpdate.isDownloading)
                }
            }
            if let update = appUpdate.availableUpdate {
                Text("Yeni sürüm: \(update.version) (\(update.preferredAssetLabel))")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            if let status = appUpdate.downloadStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("Depolama (Ollama: models dizini)") {
            LabeledContent("Modeller") {
                Text(ModelStore.shared.modelsDirectory.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            LabeledContent("Sohbetler") {
                Text(ModelStore.shared.appSupportURL.appendingPathComponent("chats").path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            LabeledContent("Disk kullanımı", value: model.diskUsageFormatted)
            Button("Klasörü Finder’da aç") {
                NSWorkspace.shared.open(ModelStore.shared.appSupportURL)
            }
        }

        Section {
            Text("Ayarlar penceresine menü çubuğundan **MacLLM → Ayarlar…** (⌘,) ile de ulaşabilirsiniz.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func modelSection(model: AppModel) -> some View {
        let bindable = Bindable(model)
        Section("Bağlam (num_ctx)") {
            Picker("Bağlam uzunluğu", selection: bindable.intBinding(\.contextLength)) {
                Text("2048").tag(2048)
                Text("4096").tag(4096)
                Text("8192").tag(8192)
                Text("16384").tag(16384)
                Text("32768").tag(32768)
            }
            Text("Modelin işleyebileceği maksimum token penceresi. Yüksek değer daha fazla RAM kullanır.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Donanım (num_gpu, num_thread)") {
            Stepper(
                "GPU katmanları: \(model.settings.gpuLayers < 0 ? "tümü (-1)" : "\(model.settings.gpuLayers)")",
                value: bindable.int32Binding(\.gpuLayers),
                in: -1...128
            )
            Stepper(
                "CPU iş parçacığı: \(model.settings.threadCount)",
                value: bindable.int32Binding(\.threadCount),
                in: 1...32
            )
            Text("GPU katmanları -1: tüm katmanlar Metal’de (Ollama’daki varsayılan tam offload).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Text("Bağlam veya GPU ayarı değişince model yeniden yüklenir (Kaydet).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func samplingSection(model: AppModel) -> some View {
        let bindable = Bindable(model)
        Section("Mirostat (Ollama: mirostat)") {
            Picker("Mod", selection: bindable.int32Binding(\.mirostat)) {
                Text("Kapalı (0)").tag(0)
                Text("Mirostat v1 (1)").tag(1)
                Text("Mirostat v2 (2)").tag(2)
            }
            if model.settings.usesMirostat {
                Slider(value: bindable.floatBinding(\.mirostatTau), in: 0...10, step: 0.1) {
                    Text("Tau: \(model.settings.mirostatTau, specifier: "%.1f")")
                }
                Slider(value: bindable.floatBinding(\.mirostatEta), in: 0.01...1, step: 0.01) {
                    Text("Eta: \(model.settings.mirostatEta, specifier: "%.2f")")
                }
            }
        }

        if !model.settings.usesMirostat {
            Section("Sıcaklık ve çekirdek örnekleme") {
                Slider(value: bindable.floatBinding(\.temperature), in: 0...2, step: 0.05) {
                    Text("Sıcaklık: \(model.settings.temperature, specifier: "%.2f")")
                }
                Slider(value: bindable.floatBinding(\.topP), in: 0.05...1, step: 0.05) {
                    Text("Top-p: \(model.settings.topP, specifier: "%.2f")")
                }
                Stepper(
                    "Top-k: \(model.settings.topK == 0 ? "kapalı" : "\(model.settings.topK)")",
                    value: bindable.int32Binding(\.topK),
                    in: 0...200
                )
                Slider(value: bindable.floatBinding(\.minP), in: 0...1, step: 0.01) {
                    Text("Min-p: \(model.settings.minP == 0 ? "kapalı" : String(format: "%.2f", model.settings.minP))")
                }
            }

            Section("Tekrar cezası (repeat_penalty)") {
                Slider(value: bindable.floatBinding(\.repeatPenalty), in: 1...2, step: 0.05) {
                    Text("Cezası: \(model.settings.repeatPenalty, specifier: "%.2f") (1.0 = kapalı)")
                }
                Stepper(
                    "Son N token: \(model.settings.repeatLastN)",
                    value: bindable.int32Binding(\.repeatLastN),
                    in: -1...512
                )
                Text("repeat_last_n: -1 = tüm bağlam, 0 = kapalı")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Tohum (seed)") {
            Stepper(
                "Seed: \(model.settings.seed == 0 ? "rastgele" : "\(model.settings.seed)")",
                value: bindable.uint32Binding(\.seed),
                in: 0...999_999
            )
            Button("Rastgele tohum (0)") {
                model.settings.seed = 0
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func chatSection(model: AppModel) -> some View {
        let bindable = Bindable(model)
        Section("Üretim limiti (num_predict)") {
            Stepper(
                "Maks. üretilecek token: \(model.settings.maxTokens)",
                value: bindable.int32Binding(\.maxTokens),
                in: 64...8192,
                step: 64
            )
        }

        Section("Sistem mesajı (system)") {
            TextEditor(text: bindable.stringBinding(\.systemPrompt))
                .font(.body)
                .frame(minHeight: 80, maxHeight: 140)
            Text("Her sohbete eklenir; model şablonuna göre system rolü olarak iletilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Durdurma dizileri (stop)") {
            TextEditor(text: $stopText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 72, maxHeight: 120)
            Text("Her satır bir stop dizisi (Ollama stop). Örn. </s>")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Varsayılan stop listesi") {
                stopText = InferenceSettings.ollamaDefaults.stopSequencesText
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func huggingFaceSection() -> some View {
        Section("İndirme hızı") {
            Stepper(
                "Paralel bağlantı: \(DownloadPreferences.parallelConnections)",
                value: Binding(
                    get: { DownloadPreferences.parallelConnections },
                    set: { DownloadPreferences.parallelConnections = $0 }
                ),
                in: 1...8
            )
            Text("50 MB üzeri modellerde aynı anda birden fazla HTTP bağlantısı kullanılır (varsayılan 6). 1 = tek bağlantı, duraklat/devam destekli.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Çevrimiçi indirme") {
            SecureField("Access Token (opsiyonel)", text: Binding(
                get: { HuggingFaceCredentials.token ?? "" },
                set: { HuggingFaceCredentials.token = $0.isEmpty ? nil : $0 }
            ))
            Text("Gated modeller için huggingface.co → Settings → Access Tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func syncStopText(from settings: InferenceSettings) {
        stopText = settings.stopSequencesText
    }
}

// MARK: - Bindable helpers (MainActor-safe settings bindings)

@MainActor
private extension Bindable where Value == AppModel {
    func intBinding(_ keyPath: WritableKeyPath<InferenceSettings, UInt32>) -> Binding<Int> {
        Binding(
            get: { Int(wrappedValue.settings[keyPath: keyPath]) },
            set: { wrappedValue.settings[keyPath: keyPath] = UInt32($0) }
        )
    }

    func int32Binding(_ keyPath: WritableKeyPath<InferenceSettings, Int32>) -> Binding<Int> {
        Binding(
            get: { Int(wrappedValue.settings[keyPath: keyPath]) },
            set: { wrappedValue.settings[keyPath: keyPath] = Int32($0) }
        )
    }

    func uint32Binding(_ keyPath: WritableKeyPath<InferenceSettings, UInt32>) -> Binding<Int> {
        Binding(
            get: { Int(wrappedValue.settings[keyPath: keyPath]) },
            set: { wrappedValue.settings[keyPath: keyPath] = UInt32($0) }
        )
    }

    func floatBinding(_ keyPath: WritableKeyPath<InferenceSettings, Float>) -> Binding<Float> {
        Binding(
            get: { wrappedValue.settings[keyPath: keyPath] },
            set: { wrappedValue.settings[keyPath: keyPath] = $0 }
        )
    }

    func stringBinding(_ keyPath: WritableKeyPath<InferenceSettings, String>) -> Binding<String> {
        Binding(
            get: { wrappedValue.settings[keyPath: keyPath] },
            set: { wrappedValue.settings[keyPath: keyPath] = $0 }
        )
    }
}
