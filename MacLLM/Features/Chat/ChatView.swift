import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @State private var inputText = ""
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var showFileImporter = false
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
            } else if model.isLoadingModel {
                ContentUnavailableView {
                    Label("Model hazırlanıyor", systemImage: "cpu")
                } description: {
                    Text("Çıkarım motoru yükleniyor. Birkaç saniye sürebilir.")
                } actions: {
                    ProgressView().controlSize(.regular)
                }
            } else if !inferenceService.isModelLoaded {
                ContentUnavailableView {
                    Label("Model bellekte değil", systemImage: "eject")
                } description: {
                    Text("\(model.selectedModel?.name ?? "Model") diskte yüklü; sohbet için belleğe alın.")
                } actions: {
                    if let selected = model.selectedModel {
                        Button("Yeniden Yükle") {
                            Task { await model.selectModel(selected) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
                                let isTyping = inferenceService.isGenerating
                                    && message.role == .assistant
                                    && message.id == model.currentSession.messages.last?.id
                                    && message.content.isEmpty
                                MessageRow(
                                    message: message,
                                    sessionId: model.currentSession.id,
                                    showsTypingIndicator: isTyping
                                )
                                .id(message.id)
                            }
                        }
                        .padding(AppTheme.contentPadding)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: model.currentSession.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: model.currentSession.messages.last?.content) { _, _ in
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }

                Divider()

                chatInputBar(model: model)
            }
        }
        .navigationTitle(model.selectedModel?.name ?? "Sohbet")
        .navigationSubtitle(navigationSubtitle)
        .onAppear { inputFocused = true }
    }

    @ViewBuilder
    private func chatInputBar(model: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            PendingAttachmentChip(attachment: attachment) {
                                pendingAttachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 4) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(inferenceService.isGenerating)
                    .help("Dosya ekle (görüntü, ses, video, belge)")

                    TextField("Mesajınızı yazın…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...12)
                        .focused($inputFocused)
                        .disabled(inferenceService.isGenerating)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                        .padding(.vertical, 8)
                        .padding(.trailing, 8)
                        .onSubmit {
                            guard !inferenceService.isGenerating else { return }
                            send()
                        }
                }
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

                Group {
                    if inferenceService.isGenerating {
                        Button("Yanıtı Durdur") {
                            Task { await model.stopGenerationAndWait() }
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                    } else {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Gönder")
                        .help("Gönder (⌘↩)")
                        .disabled(
                            (inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && pendingAttachments.isEmpty)
                                || model.isLoadingModel
                                || !inferenceService.isModelLoaded
                        )
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                }
                .frame(width: 52, height: 44, alignment: .bottom)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.bar)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers, model: model)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: ChatAttachmentImporter.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            importFiles(result, model: model)
        }
    }

    private func importFiles(_ result: Result<[URL], Error>, model: AppModel) {
        let urls: [URL]
        switch result {
        case .failure(let error):
            model.setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
            return
        case .success(let picked):
            urls = picked
        }
        for url in urls {
            guard let kind = ChatAttachmentImporter.kind(for: url) else { continue }
            do {
                var attachment = try AttachmentStore.shared.importFile(
                    from: url,
                    sessionId: model.currentSession.id,
                    kind: kind
                )
                try MediaContentProcessor.enrich(&attachment, sessionId: model.currentSession.id)
                pendingAttachments.append(attachment)
            } catch {
                model.setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], model: AppModel) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object else { return }
                Task { @MainActor in
                    importFiles(.success([url]), model: model)
                }
            }
        }
        return true
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
        guard !inferenceService.isGenerating else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        let attachments = pendingAttachments
        inputText = ""
        pendingAttachments = []
        Task {
            await appModel.sendMessage(text, pendingAttachments: attachments)
        }
    }
}
