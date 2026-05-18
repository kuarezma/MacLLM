import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel

        Form {
            Section("Hugging Face (çevrimiçi indirme)") {
                SecureField("Access Token (opsiyonel)", text: Binding(
                    get: { HuggingFaceCredentials.token ?? "" },
                    set: { HuggingFaceCredentials.token = $0.isEmpty ? nil : $0 }
                ))
                Text("Gated modeller için huggingface.co → Settings → Access Tokens bölümünden token oluşturun.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Üretim") {
                Slider(value: Binding(
                    get: { Double(model.settings.temperature) },
                    set: { model.settings.temperature = Float($0) }
                ), in: 0...2, step: 0.05) {
                    Text("Sıcaklık: \(model.settings.temperature, specifier: "%.2f")")
                }
                Slider(value: Binding(
                    get: { Double(model.settings.topP) },
                    set: { model.settings.topP = Float($0) }
                ), in: 0.05...1, step: 0.05) {
                    Text("Top-p: \(model.settings.topP, specifier: "%.2f")")
                }
                Stepper("Maks. token: \(model.settings.maxTokens)", value: Binding(
                    get: { Int(model.settings.maxTokens) },
                    set: { model.settings.maxTokens = Int32($0) }
                ), in: 64...4096, step: 64)
            }

            Section("Bağlam ve donanım") {
                Picker("Bağlam uzunluğu", selection: Binding(
                    get: { Int(model.settings.contextLength) },
                    set: { model.settings.contextLength = UInt32($0) }
                )) {
                    Text("2048").tag(2048)
                    Text("4096").tag(4096)
                    Text("8192").tag(8192)
                }
                Stepper("GPU katmanları (-1 = tümü): \(model.settings.gpuLayers)", value: Binding(
                    get: { Int(model.settings.gpuLayers) },
                    set: { model.settings.gpuLayers = Int32($0) }
                ), in: -1...99)
                Stepper("CPU iş parçacığı: \(model.settings.threadCount)", value: Binding(
                    get: { Int(model.settings.threadCount) },
                    set: { model.settings.threadCount = Int32($0) }
                ), in: 1...16)
            }

            Section {
                Button("Kaydet ve modeli yeniden yükle") {
                    model.saveSettings()
                }
            }

            Section("Hakkında") {
                LabeledContent("Sürüm", value: "1.0.0")
                LabeledContent("Çıkarım", value: "llama.cpp + Metal")
                LabeledContent("Modeller", value: model.diskUsageFormatted)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440)
    }
}
