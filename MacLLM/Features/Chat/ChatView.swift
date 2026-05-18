import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @State private var inputText = ""
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var showFileImporter = false
    @State private var messageSearchText = ""
    @State private var searchMatchIndex = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var model = appModel

        VStack(spacing: 0) {
            ChatHeaderView()

            if model.selectedModel == nil {
                emptyState(
                    title: "Model seçin",
                    description: "Üstten model seçin veya Hub'dan indirin.",
                    actionTitle: "Model Hub",
                    action: { model.showCatalog = true }
                )
            } else if model.isLoadingModel {
                emptyState(
                    title: "Model hazırlanıyor",
                    description: "Çıkarım motoru yükleniyor…",
                    actionTitle: nil,
                    action: nil
                )
            } else if !inferenceService.isModelLoaded {
                emptyState(
                    title: "Model bellekte değil",
                    description: "\(model.selectedModel?.name ?? "Model") sohbet için yüklenmeli.",
                    actionTitle: "Yeniden Yükle",
                    action: {
                        if let selected = model.selectedModel {
                            Task { await model.selectModel(selected) }
                        }
                    }
                )
            } else {
                chatContent(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appCanvasBackground()
        .navigationTitle("")
        .searchable(text: $messageSearchText, prompt: "Bu sohbette ara")
        .toolbar {
            if !matchingMessageIds.isEmpty {
                ToolbarItemGroup(placement: .automatic) {
                    Text("\(searchMatchIndex + 1)/\(matchingMessageIds.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { stepSearchMatch(delta: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    Button { stepSearchMatch(delta: 1) } label: {
                        Image(systemName: "chevron.down")
                    }
                }
            }
        }
        .onAppear { inputFocused = true }
    }

    @ViewBuilder
    private func chatContent(model: AppModel) -> some View {
        Group {
            if model.currentSession.messages.isEmpty {
                emptyChatHero(model: model)
            } else {
                messageScrollView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            janComposer(model: model)
        }
    }

    @ViewBuilder
    private func emptyChatHero(model: AppModel) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .blur(radius: 24)
                Circle()
                    .fill(AppTheme.accentSecondary.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .blur(radius: 16)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppTheme.accentGradient)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 8) {
                Text("Bir şey sorun…")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Text("Yanıtlar cihazınızda yerel olarak üretilir.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            QuickPromptChips(prompts: QuickPromptChips.defaults) { prompt in
                Task { await model.sendMessage(prompt) }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: AppTheme.maxChatContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppTheme.contentPadding)
    }

    @ViewBuilder
    private func messageScrollView(model: AppModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppTheme.messageSpacing) {
                    ForEach(messagesToShow(model: model)) { message in
                        let isLastAssistant = message.role == .assistant
                            && message.id == model.currentSession.messages.last?.id
                        let isGeneratingReply = inferenceService.isGenerating && isLastAssistant
                        MessageRow(
                            message: message,
                            sessionId: model.currentSession.id,
                            showsTypingIndicator: isGeneratingReply && message.content.isEmpty,
                            isStreaming: isGeneratingReply && !message.content.isEmpty,
                            generationStats: stats(for: message, isLastAssistant: isLastAssistant),
                            reserveStatsSpace: isLastAssistant && message.role == .assistant
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, AppTheme.contentPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: AppTheme.maxChatContentWidth)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.currentSession.messages.count) { _, _ in
                model.scheduleContextTokenRefresh()
                guard messageSearchNeedle.isEmpty else { return }
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: model.currentSession.messages.last?.content) { _, _ in
                model.scheduleContextTokenRefresh()
            }
            .onChange(of: messageSearchText) { _, _ in
                searchMatchIndex = 0
                scrollToSearchMatch(proxy: proxy)
            }
            .onChange(of: searchMatchIndex) { _, _ in
                scrollToSearchMatch(proxy: proxy)
            }
            .onChange(of: inferenceService.isGenerating) { _, isGenerating in
                if !isGenerating {
                    model.scheduleContextTokenRefresh()
                }
            }
            .task {
                await model.refreshContextTokenCount()
            }
        }
    }

    @ViewBuilder
    private func janComposer(model: AppModel) -> some View {
        VStack(spacing: 0) {
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            PendingAttachmentChip(attachment: attachment) {
                                pendingAttachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.contentPadding)
                }
                .frame(height: AppTheme.composerAccessoryHeight)
            }

            if let warning = model.visionAttachmentWarning(for: pendingAttachments) {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Hub") {
                        model.showCatalog = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .appHitTarget(minWidth: 44, minHeight: 28)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                }
                .padding(.horizontal, AppTheme.contentPadding)
                .padding(.bottom, 6)
            }

            HStack(alignment: .bottom, spacing: 12) {
                composerField(model: model)
                ContextUsageView(
                    usedTokens: model.contextTokenCount,
                    maxTokens: Int(model.settings.contextLength),
                    isEstimate: model.contextTokenCountIsEstimate
                )
                sendButton(model: model)
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(minHeight: AppTheme.composerMinHeight)
        }
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    AppTheme.chatBackground.opacity(0),
                    AppTheme.chatBackground.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
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

    @ViewBuilder
    private func composerField(model: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                composerIconButton("plus", help: "Dosya ekle") {
                    showFileImporter = true
                }
                .disabled(inferenceService.isGenerating)

                TextField("Bir şey sorun…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...12)
                    .focused($inputFocused)
                    .disabled(inferenceService.isGenerating)
                    .onSubmit {
                        guard !inferenceService.isGenerating else { return }
                        send()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack {
                ComposerToolsView(isDisabled: inferenceService.isGenerating)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .appGlassCard(cornerRadius: AppTheme.composerRadius, material: .regularMaterial)
        .appFloatingShadow(radius: 18, y: 6)
    }

    private func composerIconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(AccentIconButtonStyle())
        .appHitTarget(minWidth: 36, minHeight: 36)
        .help(help)
    }

    @ViewBuilder
    private func sendButton(model: AppModel) -> some View {
        if inferenceService.isGenerating {
            Button {
                Task { await model.stopGenerationAndWait() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(ModernScaleButtonStyle())
            .appHitTarget(minWidth: 40, minHeight: 40)
            .help("Durdur")
            .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button(action: send) {
                ZStack {
                    if canSend {
                        Circle()
                            .fill(AppTheme.accentGradient)
                            .frame(width: 36, height: 36)
                            .shadow(color: AppTheme.glowAccent, radius: 8, y: 2)
                    } else {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 36, height: 36)
                    }
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? .white : AppTheme.secondaryText.opacity(0.4))
                }
            }
            .buttonStyle(ModernScaleButtonStyle())
            .appHitTarget(minWidth: 40, minHeight: 40)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var canSend: Bool {
        let hasContent = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingAttachments.isEmpty
        let visionBlocked = appModel.visionAttachmentWarning(for: pendingAttachments) != nil
            && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pendingAttachments.contains { $0.kind == .image || $0.kind == .video || $0.kind == .audio }
        return hasContent
            && !visionBlocked
            && !appModel.isLoadingModel
            && inferenceService.isModelLoaded
    }

    private func stats(for message: ChatMessage, isLastAssistant: Bool) -> GenerationStats? {
        guard message.role == .assistant, isLastAssistant, !inferenceService.isGenerating else { return nil }
        return inferenceService.lastGenerationStats
    }

    private func emptyState(
        title: String,
        description: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack {
            Spacer()
            ContentUnavailableView {
                Label(title, systemImage: "cpu")
            } description: {
                Text(description)
            } actions: {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                }
            }
            Spacer()
        }
    }

    private var messageSearchNeedle: String {
        messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingMessageIds: [UUID] {
        let needle = messageSearchNeedle
        guard !needle.isEmpty else { return [] }
        return appModel.currentSession.messages
            .filter { $0.content.localizedCaseInsensitiveContains(needle) }
            .map(\.id)
    }

    private func messagesToShow(model: AppModel) -> [ChatMessage] {
        let needle = messageSearchNeedle
        if needle.isEmpty { return model.currentSession.messages }
        return model.currentSession.messages.filter {
            $0.content.localizedCaseInsensitiveContains(needle)
        }
    }

    private func stepSearchMatch(delta: Int) {
        let count = matchingMessageIds.count
        guard count > 0 else { return }
        searchMatchIndex = (searchMatchIndex + delta + count) % count
    }

    private func scrollToSearchMatch(proxy: ScrollViewProxy) {
        let ids = matchingMessageIds
        guard !ids.isEmpty else { return }
        let index = min(max(searchMatchIndex, 0), ids.count - 1)
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(ids[index], anchor: .center)
        }
    }

    private func importFiles(_ result: Result<[URL], Error>, model: AppModel) {
        switch result {
        case .failure(let error):
            model.setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
        case .success(let urls):
            Task { @MainActor in
                for url in urls {
                    guard let kind = ChatAttachmentImporter.kind(for: url) else { continue }
                    do {
                        var attachment = try AttachmentStore.shared.importFile(
                            from: url,
                            sessionId: model.currentSession.id,
                            kind: kind
                        )
                        try await MediaContentProcessor.enrich(
                            &attachment,
                            sessionId: model.currentSession.id
                        )
                        pendingAttachments.append(attachment)
                    } catch {
                        model.setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
                    }
                }
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
