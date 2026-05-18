import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var model = appModel

        VStack(spacing: 0) {
            if model.selectedModel == nil {
                ContentUnavailableView {
                    Label("Model seçilmedi", systemImage: "cpu")
                } description: {
                    Text("Sol panelden bir model seçin veya katalogdan yeni model ekleyin.")
                } actions: {
                    Button("Model Ekle…") { model.showCatalog = true }
                }
            } else if model.isLoadingModel || !inferenceService.isModelLoaded {
                ContentUnavailableView {
                    Label("Model hazırlanıyor", systemImage: "cpu")
                } description: {
                    Text("Çıkarım motoru yükleniyor. Birkaç saniye sürebilir.")
                } actions: {
                    ProgressView().controlSize(.regular)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.messageSpacing) {
                            if model.currentSession.messages.isEmpty {
                                ContentUnavailableView {
                                    Label("Sohbet başlatın", systemImage: "bubble.left.and.bubble.right")
                                } description: {
                                    Text("Aşağıya mesaj yazın. Yanıtlar yerel olarak üretilir.")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            }
                            ForEach(model.currentSession.messages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(AppTheme.contentPadding)
                    }
                    .onChange(of: model.currentSession.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: model.currentSession.messages.last?.content) { _, _ in
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }

                Divider()

                HStack(alignment: .bottom, spacing: AppTheme.rowSpacing) {
                    TextField("Mesajınızı yazın…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...8)
                        .focused($inputFocused)
                        .onSubmit { send() }

                    if inferenceService.isGenerating {
                        Button("Durdur") {
                            model.stopGeneration()
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                    } else {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel("Gönder")
                        .help("Gönder (⌘↩)")
                        .disabled(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || model.isLoadingModel
                                || !inferenceService.isModelLoaded
                        )
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                }
                .padding(AppTheme.contentPadding)
            }
        }
        .navigationTitle(model.selectedModel?.name ?? "Sohbet")
        .navigationSubtitle(navigationSubtitle)
        .onAppear { inputFocused = true }
    }

    private var navigationSubtitle: String {
        if inferenceService.isGenerating {
            return "Yanıt üretiliyor…"
        }
        return appModel.currentSession.title
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = appModel.currentSession.messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await appModel.sendMessage(text)
        }
    }
}
