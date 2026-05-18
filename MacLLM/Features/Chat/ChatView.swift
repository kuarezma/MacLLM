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
                    Text("Sol panelden bir model seçin veya yeni model indirin.")
                } actions: {
                    Button("Model Kataloğu") { model.showCatalog = true }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(model.currentSession.messages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: model.currentSession.messages.count) { _, _ in
                        if let last = model.currentSession.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                HStack(alignment: .bottom, spacing: 12) {
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
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoadingModel)
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                }
                .padding()
            }
        }
        .navigationTitle(model.selectedModel?.name ?? "Sohbet")
        .navigationSubtitle(model.currentSession.title)
    }

    private func send() {
        let text = inputText
        inputText = ""
        Task {
            await appModel.sendMessage(text)
        }
    }
}
