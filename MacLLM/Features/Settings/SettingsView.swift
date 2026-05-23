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

    var subtitle: String {
        switch self {
        case .general: return "Sürüm, güncelleme, depolama"
        case .model: return "Bağlam, GPU, CPU"
        case .sampling: return "Sıcaklık, top-p, mirostat"
        case .chat: return "Sistem istemi, stop, limit"
        case .huggingFace: return "İndirme, token"
        }
    }
}

@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppUpdateController.self) private var appUpdate
    @State private var tab: SettingsTab = .general
    @State private var stopText = ""
    @State private var settingsBaseline = InferenceSettings.default

    var body: some View {
        @Bindable var model = appModel

        HStack(spacing: 0) {
            settingsSidebar

            VStack(spacing: 0) {
                settingsHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
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
                    .padding(AppTheme.contentPadding)
                    .frame(maxWidth: 620, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.chatBackground)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(AppTheme.sidebarBackground)
        .onAppear {
            settingsBaseline = model.settings
            syncStopText(from: model.settings)
        }
        .onDisappear {
            guard !AppShutdown.isShuttingDown else { return }
            model.settings.stopSequencesText = stopText
            model.saveSettingsIfNeeded(comparedTo: settingsBaseline)
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ayarlar")
                    .font(.title3.weight(.semibold))
                Text("MacLLM")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)

            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { item in
                    SettingsNavRow(
                        icon: item.icon,
                        title: item.rawValue,
                        isSelected: tab == item
                    ) {
                        tab = item
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 220)
        .background(AppTheme.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.rawValue)
                    .font(.title2.weight(.semibold))
                Text(tab.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Button("Ollama varsayılanları") {
                appModel.settings = InferenceSettings.ollamaDefaults
                appModel.settings.threadCount = Int32(
                    max(1, min(8, appModel.systemProfile.processorCount - 2))
                )
                syncStopText(from: appModel.settings)
            }
            .buttonStyle(SecondaryButtonStyle())
            .foregroundStyle(AppTheme.primaryText)
            Button("Kaydet") {
                appModel.settings.stopSequencesText = stopText
                appModel.saveSettingsIfNeeded(comparedTo: settingsBaseline)
                settingsBaseline = appModel.settings
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(AccentPrimaryButtonStyle())
            .help("Kapatırken de otomatik kaydedilir")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppTheme.chatBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func generalSection(model: AppModel) -> some View {
        @Bindable var updates = appUpdate

        SettingsCard("Uygulama") {
            SettingsInfoRow(label: "Sürüm", value: appUpdate.currentVersion)
            SettingsInfoRow(label: "Bu Mac", value: model.systemProfile.displaySummary)
            SettingsInfoRow(label: "Çıkarım motoru", value: "llama.cpp + Metal")
        }

        SettingsCard("Açılış") {
            Picker("Model yükleme", selection: Binding(
                get: { LaunchPreferences.loadModelOnLaunch },
                set: { LaunchPreferences.loadModelOnLaunch = $0 }
            )) {
                ForEach(LoadModelOnLaunch.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            SettingsCaption(text: "Otomatik yükle: uygulama açılışında son model belleğe alınır. Sor: her seferinde onay istenir.")
        }

        SettingsCard("Bildirimler") {
            Toggle("Yanıt hazır olunca bildir", isOn: Binding(
                get: { GenerationNotificationPreferences.notifyOnComplete },
                set: { GenerationNotificationPreferences.notifyOnComplete = $0 }
            ))
            SettingsCaption(text: "Uzun üretimlerde uygulama arka plandayken macOS bildirimi gösterilir.")
        }

        SettingsCard("Güncellemeler") {
            Toggle("Açılışta güncellemeleri kontrol et", isOn: $updates.autoCheckEnabled)
            if let last = appUpdate.lastCheckDate {
                SettingsInfoRow(
                    label: "Son kontrol",
                    value: last.formatted(date: .abbreviated, time: .shortened)
                )
            }
            HStack(spacing: 10) {
                Button {
                    Task { await appUpdate.checkForUpdates(userInitiated: true) }
                } label: {
                    if appUpdate.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Güncellemeleri denetle")
                    }
                }
                if appUpdate.availableUpdate != nil {
                    Button("İndir ve kur") {
                        Task { await appUpdate.downloadAndOpenUpdate() }
                    }
                    .buttonStyle(AccentPrimaryButtonStyle())
                    .tint(AppTheme.accent)
                    .disabled(appUpdate.isDownloading)
                }
            }
            if let update = appUpdate.availableUpdate {
                SettingsCaption(text: "Yeni sürüm: \(update.version) (\(update.preferredAssetLabel))")
            }
            if let status = appUpdate.downloadStatus {
                SettingsCaption(text: status)
            }
        }

        SettingsCard("Depolama", subtitle: "Ollama: models dizini") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Modeller")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(ModelStore.shared.modelsDirectory.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(AppTheme.primaryText)
                Text("Sohbetler")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 4)
                Text(ModelStore.shared.appSupportURL.appendingPathComponent("chats").path)
                    .font(.caption)
                    .textSelection(.enabled)
                SettingsInfoRow(label: "Disk kullanımı", value: model.diskUsageFormatted)
                Button("Klasörü Finder’da aç") {
                    NSWorkspace.shared.open(ModelStore.shared.appSupportURL)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
            }
        }

        SettingsCaption(
            text: "Değişiklikler pencere kapanırken veya Kaydet (⌘S) ile uygulanır; model ayarları değişince seçili model yeniden yüklenir."
        )
    }

    @ViewBuilder
    private func modelSection(model: AppModel) -> some View {
        let bindable = Bindable(model)

        if let profile = model.activeProfile {
            SettingsCard("Yüklü model", subtitle: profile.displayName) {
                SettingsInfoRow(
                    label: "Şablon",
                    value: profile.resolvedChatTemplate
                )
                SettingsInfoRow(label: "Mod", value: profile.modality.label)
                if let nCtx = profile.nCtxTrain {
                    SettingsInfoRow(label: "Eğitim bağlamı", value: "\(nCtx) token")
                }
                if let params = profile.parameterLabel {
                    SettingsInfoRow(label: "Parametre", value: params)
                }
                SettingsInfoRow(
                    label: "Görüntü",
                    value: profile.supportsVision
                        ? (profile.runtimeMultimodal ? "Hazır" : "mmproj gerekli")
                        : "Desteklenmiyor"
                )
                SettingsInfoRow(
                    label: "Etkin bağlam",
                    value: "\(model.effectiveContextLength) token"
                )
                SettingsCaption(
                    text: "Global num_ctx ayarınız \(model.settings.contextLength) olarak kalır; etkin üst sınır modele göre \(model.effectiveContextLength) token."
                )
            }
        }

        SettingsCard("Performans", subtitle: "Donanım kademesi: \(model.systemProfile.performanceTier.label)") {
            Picker("Profil", selection: Binding(
                get: { model.settings.performancePreset },
                set: { model.settings.apply(preset: $0, tier: model.systemProfile.performanceTier) }
            )) {
                ForEach(InferenceSettings.PerformancePreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Flash Attention", isOn: bindable.boolBinding(\.flashAttention))
            Toggle("Prompt önbelleği (KV reuse)", isOn: bindable.boolBinding(\.usePromptCache))

            Picker("Batch boyutu", selection: Binding(
                get: { model.settings.batchSize },
                set: { model.settings.batchSize = $0 }
            )) {
                Text("256").tag(UInt32(256))
                Text("512").tag(UInt32(512))
                Text("1024").tag(UInt32(1024))
            }
            .pickerStyle(.segmented)

            SettingsCaption(
                text: "Batch / Flash Attention değişince model yeniden yüklenir. Örnekleme ayarları anında uygulanır."
            )
        }

        SettingsCard("Bağlam", subtitle: "num_ctx — maksimum token penceresi") {
            Picker("Bağlam uzunluğu", selection: bindable.intBinding(\.contextLength)) {
                Text("2048").tag(2048)
                Text("4096").tag(4096)
                Text("8192").tag(8192)
                Text("16384").tag(16384)
                Text("32768").tag(32768)
            }
            .pickerStyle(.segmented)
            SettingsCaption(text: "Yüksek değer daha fazla RAM kullanır.")
        }

        SettingsCard("Donanım", subtitle: "num_gpu, num_thread") {
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
            SettingsCaption(text: "GPU katmanları -1: tüm katmanlar Metal’de.")
        }
    }

    @ViewBuilder
    private func samplingSection(model: AppModel) -> some View {
        let bindable = Bindable(model)

        SettingsCard("Mirostat") {
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
            SettingsCard("Sıcaklık ve çekirdek örnekleme") {
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

            SettingsCard("Tekrar cezası", subtitle: "repeat_penalty") {
                Slider(value: bindable.floatBinding(\.repeatPenalty), in: 1...2, step: 0.05) {
                    Text("Cezası: \(model.settings.repeatPenalty, specifier: "%.2f") (1.0 = kapalı)")
                }
                Stepper(
                    "Son N token: \(model.settings.repeatLastN)",
                    value: bindable.int32Binding(\.repeatLastN),
                    in: -1...512
                )
                SettingsCaption(text: "repeat_last_n: -1 = tüm bağlam, 0 = kapalı")
            }
        }

        SettingsCard("Tohum", subtitle: "seed") {
            Stepper(
                "Seed: \(model.settings.seed == 0 ? "rastgele" : "\(model.settings.seed)")",
                value: bindable.uint32Binding(\.seed),
                in: 0...999_999
            )
            Button("Rastgele tohum (0)") { model.settings.seed = 0 }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func chatSection(model: AppModel) -> some View {
        let bindable = Bindable(model)

        SettingsCard("Üretim limiti", subtitle: "num_predict") {
            Stepper(
                "Maks. üretilecek token: \(model.settings.maxTokens)",
                value: bindable.int32Binding(\.maxTokens),
                in: 64...8192,
                step: 64
            )
        }

        SettingsCard("Sistem mesajı", subtitle: "system") {
            SettingsTextEditor(text: bindable.stringBinding(\.systemPrompt), minHeight: 100)
            SettingsCaption(text: "Her sohbete eklenir; model şablonuna göre system rolü olarak iletilir.")
        }

        SettingsCard("Durdurma dizileri", subtitle: "stop") {
            SettingsTextEditor(text: $stopText, minHeight: 88, monospaced: true)
            SettingsCaption(text: "Her satır bir stop dizisi. Örn. </s>")
            Button("Varsayılan stop listesi") {
                stopText = InferenceSettings.ollamaDefaults.stopSequencesText
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .font(.caption)
        }
    }

    @ViewBuilder
    private func huggingFaceSection() -> some View {
        SettingsCard("İndirme hızı") {
            Stepper(
                "Paralel bağlantı: \(DownloadPreferences.parallelConnections)",
                value: Binding(
                    get: { DownloadPreferences.parallelConnections },
                    set: { DownloadPreferences.parallelConnections = $0 }
                ),
                in: 1...8
            )
            SettingsCaption(
                text: "50 MB üzeri modellerde birden fazla HTTP bağlantısı kullanılır (varsayılan 6)."
            )
        }

        SettingsCard("Çevrimiçi indirme") {
            SecureField("Erişim tokenı (opsiyonel)", text: Binding(
                get: { HuggingFaceCredentials.token ?? "" },
                set: { HuggingFaceCredentials.token = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            SettingsCaption(text: "Kilitli modeller için huggingface.co → Ayarlar → Access Tokens bölümünden token oluşturun.")
        }
    }

    private func syncStopText(from settings: InferenceSettings) {
        stopText = settings.stopSequencesText
    }
}

// MARK: - Bindable helpers

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

    func boolBinding(_ keyPath: WritableKeyPath<InferenceSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { wrappedValue.settings[keyPath: keyPath] },
            set: { wrappedValue.settings[keyPath: keyPath] = $0 }
        )
    }
}
