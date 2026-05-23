import Foundation
import Darwin
import llama

enum LlamaError: Error, LocalizedError, UserCancellationError {
    case couldNotInitializeContext
    case contextOverflow(promptTokens: Int, contextSize: Int)
    case decodeFailed
    case contextShutdown
    case templateFailed
    case tokenizationFailed
    case tokenPieceFailed
    case generationCancelled
    case generationStalled
    case generationEmpty

    var isUserCancellation: Bool {
        if case .generationCancelled = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext:
            return "Model yüklenemedi. Dosya bozuk olabilir veya yetersiz bellek."
        case .contextOverflow(let promptTokens, let contextSize):
            return "Bağlam doldu (\(promptTokens) token, limit \(contextSize)). Ayarlardan num_ctx düşürün veya yeni sohbet açın."
        case .decodeFailed:
            return "Çıkarım hatası. Yeni sohbet açmayı deneyin. Sorun sürerse Ayarlar → Performans'tan Flash Attention'ı kapatın veya farklı bir model seçin."
        case .contextShutdown:
            return "Model bellekte değil. Modeli yeniden yükleyip tekrar deneyin."
        case .templateFailed:
            return "Sohbet şablonu uygulanamadı."
        case .tokenizationFailed:
            return "Mesaj token'lara ayrılamadı. Metni kısaltıp tekrar deneyin."
        case .tokenPieceFailed:
            return "Model çıktısı güvenli metne dönüştürülemedi. Yeni sohbet açıp tekrar deneyin."
        case .generationCancelled:
            return "Üretim iptal edildi."
        case .generationStalled:
            return "Yanıt üretimi zaman aşımına uğradı. Yeni sohbet açın veya «Yanıtı Durdur» kullanın."
        case .generationEmpty:
            return "Model anlamlı yanıt üretmedi. Yeni sohbet açın; Qwopus için Flash Attention kapalı olduğundan emin olun."
        }
    }
}

func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) -> Bool {
    let tokenIndex = Int(batch.n_tokens)
    guard let seqIDPointer = batch.seq_id[tokenIndex] else { return false }
    batch.token[tokenIndex] = id
    batch.pos[tokenIndex] = pos
    batch.n_seq_id[tokenIndex] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        seqIDPointer[Int(i)] = seq_ids[i]
    }
    batch.logits[tokenIndex] = logits ? 1 : 0
    batch.n_tokens += 1
    return true
}

private enum LlamaBackend {
    static var instanceCount = 0
    static let lock = NSLock()

    static func retain() {
        lock.lock()
        defer { lock.unlock() }
        if instanceCount == 0 {
            llama_backend_init()
        }
        instanceCount += 1
    }

    static func release() {
        lock.lock()
        defer { lock.unlock() }
        guard instanceCount > 0 else { return }
        instanceCount -= 1
        if instanceCount == 0 {
            llama_backend_free()
        }
    }
}

actor LlamaContext {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private var tokens_list: [llama_token]
    private var temporary_invalid_cchars: [CChar]

    var is_done: Bool = false
    var n_len: Int32 = 1024
    var n_cur: Int32 = 0
    var n_decode: Int32 = 0
    var kvPosition: Int32 { n_cur }
    private(set) var lastPromptTokenCount: Int = 0

    private var cancelled = false
    private var shutDown = false
    private var chatTemplate: String = "chatml"
    private let mtmdShim = MtmdShim()
    private var multimodalPrefill = false
    private var threadCount: Int32 = 4
    private var batchSizeLimit: Int32 = 512

    init(
        model: OpaquePointer,
        context: OpaquePointer,
        settings: InferenceSettings,
        chatTemplateHint: String,
        mmprojPath: String? = nil
    ) throws {
        self.model = model
        self.context = context
        self.chatTemplate = ChatTemplateResolver.templateForModel(model, hint: chatTemplateHint)
        self.tokens_list = []
        self.temporary_invalid_cchars = []
        self.n_len = settings.maxTokens
        self.threadCount = settings.threadCount
        self.batchSizeLimit = Int32(max(128, min(Int(settings.batchSize), 1024)))
        vocab = llama_model_get_vocab(model)

        let batchCap = Int32(max(128, min(Int(settings.batchSize), 1024)))
        self.batch = llama_batch_init(batchCap, 0, 1)

        let sparams = llama_sampler_chain_default_params()
        sampling = llama_sampler_chain_init(sparams)
        Self.configureSamplerChain(sampling, vocab: vocab, settings: settings)

        if let path = mmprojPath, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            do {
                try mtmdShim.load(mmprojPath: path, model: model, nThreads: threadCount)
            } catch {
                shutDown = true
                Self.freeNativeResources(
                    sampling: sampling,
                    batch: batch,
                    context: context,
                    model: model
                )
                throw error
            }
        }
    }

    func updateRuntimeSettings(_ settings: InferenceSettings) {
        guard !shutDown else { return }
        n_len = settings.maxTokens
        threadCount = settings.threadCount
        llama_sampler_free(sampling)
        let sparams = llama_sampler_chain_default_params()
        sampling = llama_sampler_chain_init(sparams)
        Self.configureSamplerChain(sampling, vocab: vocab, settings: settings)
    }

    private static func configureSamplerChain(
        _ chain: UnsafeMutablePointer<llama_sampler>,
        vocab: OpaquePointer,
        settings: InferenceSettings
    ) {
        let seed = settings.seed == 0 ? UInt32.random(in: 1...UInt32.max) : settings.seed

        if settings.mirostat == 2 {
            llama_sampler_chain_add(chain, llama_sampler_init_mirostat_v2(seed, settings.mirostatTau, settings.mirostatEta))
            return
        }
        if settings.mirostat == 1 {
            let n_vocab = llama_vocab_n_tokens(vocab)
            llama_sampler_chain_add(
                chain,
                llama_sampler_init_mirostat(n_vocab, seed, settings.mirostatTau, settings.mirostatEta, 100)
            )
            return
        }

        if settings.repeatPenalty != 1.0 || settings.repeatLastN != 0 {
            llama_sampler_chain_add(
                chain,
                llama_sampler_init_penalties(
                    settings.repeatLastN,
                    settings.repeatPenalty,
                    0,
                    0
                )
            )
        }
        if settings.topK > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(settings.topK))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(settings.topP, 1))
        if settings.minP > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(settings.minP, 1))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_temp(settings.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(seed))
    }

    deinit {
        if !shutDown {
            Self.freeNativeResources(
                sampling: sampling,
                batch: batch,
                context: context,
                model: model
            )
        }
    }

    /// Belleği serbest bırakır; uygulama kapanırken önce bu çağrılmalıdır.
    func shutdown() {
        guard !shutDown else { return }
        cancelled = true
        releaseNativeResources()
    }

    private func releaseNativeResources() {
        guard !shutDown else { return }
        shutDown = true
        Self.freeNativeResources(
            sampling: sampling,
            batch: batch,
            context: context,
            model: model
        )
    }

    private static func freeNativeResources(
        sampling: UnsafeMutablePointer<llama_sampler>,
        batch: llama_batch,
        context: OpaquePointer,
        model: OpaquePointer
    ) {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        LlamaBackend.release()
    }

    private func ensureActive() throws {
        if shutDown {
            throw LlamaError.contextShutdown
        }
    }

    func loadMmproj(path: String?) throws {
        try ensureActive()
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        try mtmdShim.load(mmprojPath: path, model: model, nThreads: threadCount)
    }

    var hasMultimodalEncoder: Bool {
        guard !shutDown else { return false }
        return mtmdShim.supportsVision || mtmdShim.supportsAudio
    }

    func modelMetadata() -> (nCtxTrain: Int, nParams: UInt64, description: String) {
        guard !shutDown else { return (0, 0, "") }
        let nCtxTrain = Int(llama_model_n_ctx_train(model))
        let nParams = llama_model_n_params(model)
        return (nCtxTrain, nParams, modelDescription())
    }

    func runtimeCapabilities() -> (vision: Bool, audio: Bool) {
        guard !shutDown else { return (false, false) }
        return (mtmdShim.supportsVision, mtmdShim.supportsAudio)
    }

    static func createContext(
        path: String,
        settings: InferenceSettings,
        chatTemplateHint: String = "chatml",
        mmprojPath: String? = nil
    ) throws -> LlamaContext {
        LlamaBackend.retain()
        var model_params = llama_model_default_params()

        if settings.gpuLayers < 0 {
            model_params.n_gpu_layers = 999
        } else {
            model_params.n_gpu_layers = settings.gpuLayers
        }

        guard let model = llama_model_load_from_file(path, model_params) else {
            LlamaBackend.release()
            throw LlamaError.couldNotInitializeContext
        }

        let n_threads = settings.threadCount
        let batchSize = UInt32(max(128, min(Int(settings.batchSize), 1024)))
        var ctx_params = llama_context_default_params()
        ctx_params.n_ctx = settings.contextLength
        ctx_params.n_threads = n_threads
        ctx_params.n_threads_batch = n_threads
        ctx_params.n_batch = batchSize
        ctx_params.n_ubatch = batchSize
        ctx_params.flash_attn_type = settings.flashAttention
            ? LLAMA_FLASH_ATTN_TYPE_ENABLED
            : LLAMA_FLASH_ATTN_TYPE_DISABLED

        guard let context = llama_init_from_model(model, ctx_params) else {
            llama_model_free(model)
            LlamaBackend.release()
            throw LlamaError.couldNotInitializeContext
        }

        return try LlamaContext(
            model: model,
            context: context,
            settings: settings,
            chatTemplateHint: chatTemplateHint,
            mmprojPath: mmprojPath
        )
    }

    func resolvedChatTemplate() -> String {
        chatTemplate
    }

    func cancel() {
        cancelled = true
    }

    func applyChatTemplate(messages: [ChatMessage], templateName: String) throws -> String {
        try ensureActive()
        let tmpl = ChatTemplateResolver.resolveBuiltin(
            chatTemplate.isEmpty ? templateName : chatTemplate
        )
        if tmpl == "phi2" {
            return ChatTemplateResolver.applyPhi2Template(messages: messages, addGenerationPrompt: true)
        }

        var rolePointers: [UnsafeMutablePointer<CChar>] = []
        var contentPointers: [UnsafeMutablePointer<CChar>] = []
        rolePointers.reserveCapacity(messages.count)
        contentPointers.reserveCapacity(messages.count)
        defer {
            rolePointers.forEach { free($0) }
            contentPointers.forEach { free($0) }
        }

        for message in messages {
            guard let role = strdup(message.role.rawValue) else {
                throw LlamaError.templateFailed
            }
            guard let content = strdup(message.content) else {
                free(role)
                throw LlamaError.templateFailed
            }
            rolePointers.append(role)
            contentPointers.append(content)
        }

        var cMessages: [llama_chat_message] = messages.indices.map { index in
            llama_chat_message(
                role: UnsafePointer(rolePointers[index]),
                content: UnsafePointer(contentPointers[index])
            )
        }

        var bufferSize = 8192
        while bufferSize <= 131_072 {
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let written = llama_chat_apply_template(
                tmpl,
                &cMessages,
                cMessages.count,
                true,
                &buffer,
                Int32(bufferSize)
            )
            if written < 0 {
                bufferSize *= 2
                continue
            }
            if written >= bufferSize {
                bufferSize = Int(written) + 256
                continue
            }
            return String(cString: buffer)
        }
        throw LlamaError.templateFailed
    }

    func completionInit(text: String, mediaPaths: [String] = [], reuseTokenCount: Int = 0) throws {
        try ensureActive()
        cancelled = false
        is_done = false
        n_decode = 0
        multimodalPrefill = false

        if !mediaPaths.isEmpty, hasMultimodalEncoder {
            multimodalPrefill = true
            tokens_list = []
            temporary_invalid_cchars = []
            llama_batch_clear(&batch)

            let nPast = try mtmdShim.evalPrompt(
                prompt: text,
                mediaPaths: mediaPaths,
                llamaContext: context,
                nPast: 0,
                nBatch: batchSizeLimit
            )
            n_cur = nPast
            n_decode = 0
            return
        }

        let allTokens = try tokenize(text: text, add_bos: true)
        tokens_list = allTokens
        temporary_invalid_cchars = []
        lastPromptTokenCount = allTokens.count

        if reuseTokenCount > 0,
           reuseTokenCount < allTokens.count,
           n_cur > 0,
           Int(n_cur) == reuseTokenCount {
            let suffixTokens = Array(allTokens[reuseTokenCount...])
            try validateContextBudget(adding: suffixTokens.count)
            try decodePrefillChunks(suffixTokens, startPos: n_cur)
            return
        }

        try validateContextBudget(adding: allTokens.count)
        try decodePrefillChunks(allTokens, startPos: 0)
    }

    private func validateContextBudget(adding newTokens: Int) throws {
        let n_ctx = Int(llama_n_ctx(context))
        let total = Int(n_cur) + newTokens
        let reserveForGeneration = max(64, Int(n_len))
        if total + reserveForGeneration > n_ctx {
            throw LlamaError.contextOverflow(promptTokens: total, contextSize: n_ctx)
        }
    }

    private func decodePrefillChunks(_ tokens: [llama_token], startPos: Int32) throws {
        guard !tokens.isEmpty else { return }
        let chunkLimit = Int(batchSizeLimit)
        var offset = 0
        while offset < tokens.count {
            let end = min(offset + chunkLimit, tokens.count)
            llama_batch_clear(&batch)
            for index in offset..<end {
                let isLast = index == tokens.count - 1
                guard llama_batch_add(&batch, tokens[index], startPos + Int32(index), [0], isLast) else {
                    throw LlamaError.decodeFailed
                }
            }
            if llama_decode(context, batch) != 0 {
                throw LlamaError.decodeFailed
            }
            offset = end
        }
        n_cur = startPos + Int32(tokens.count)
    }

    func completionLoop() throws -> String {
        try ensureActive()
        if cancelled {
            is_done = true
            throw LlamaError.generationCancelled
        }

        let logitsIdx: Int32 = batch.n_tokens > 0 ? batch.n_tokens - 1 : -1
        let new_token_id = llama_sampler_sample(sampling, context, logitsIdx)

        if llama_vocab_is_eog(vocab, new_token_id) || n_decode >= n_len {
            is_done = true
            let tail = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return tail
        }

        let new_token_cchars = try tokenToPiece(token: new_token_id)
        temporary_invalid_cchars.append(contentsOf: new_token_cchars)

        let new_token_str: String
        if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else {
            new_token_str = ""
        }

        llama_batch_clear(&batch)
        guard llama_batch_add(&batch, new_token_id, n_cur, [0], true) else {
            throw LlamaError.decodeFailed
        }
        n_decode += 1
        n_cur += 1

        if llama_decode(context, batch) != 0 {
            throw LlamaError.decodeFailed
        }

        return new_token_str
    }

    /// Yeni kullanıcı mesajı öncesi KV önbelleğini ve konum sayacını sıfırlar.
    func generationSnapshot() -> (promptTokens: Int, outputTokens: Int) {
        (lastPromptTokenCount, Int(n_decode))
    }

    func clear() {
        guard !shutDown else { return }
        tokens_list.removeAll()
        temporary_invalid_cchars.removeAll()
        is_done = false
        cancelled = false
        multimodalPrefill = false
        n_cur = 0
        n_decode = 0
        lastPromptTokenCount = 0
        llama_batch_clear(&batch)
        llama_memory_clear(llama_get_memory(context), true)
    }

    func modelDescription() -> String {
        guard !shutDown else { return "" }
        let capacity = 512
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: capacity)
        result.initialize(repeating: 0, count: capacity)
        defer { result.deallocate() }
        let nChars = llama_model_desc(model, result, capacity)
        guard nChars > 0 else { return "" }
        let safeCount = min(Int(nChars), capacity - 1)
        return String(cString: Array(UnsafeBufferPointer(start: result, count: safeCount)) + [0])
    }

    func countTokens(in text: String, addBos: Bool = false) throws -> Int {
        try ensureActive()
        guard !text.isEmpty else { return addBos ? 1 : 0 }
        return try tokenize(text: text, add_bos: addBos).count
    }

    private func tokenize(text: String, add_bos: Bool) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        guard utf8Count <= Int(Int32.max) else {
            throw LlamaError.tokenizationFailed
        }

        let initialCapacity = max(1, utf8Count + (add_bos ? 1 : 0) + 1)
        return try tokenize(text: text, utf8Count: utf8Count, addBos: add_bos, capacity: initialCapacity)
    }

    private func tokenize(
        text: String,
        utf8Count: Int,
        addBos: Bool,
        capacity: Int
    ) throws -> [llama_token] {
        guard capacity > 0, capacity <= Int(Int32.max) else {
            throw LlamaError.tokenizationFailed
        }

        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { tokens.deallocate() }
        let tokenCount = llama_tokenize(
            vocab,
            text,
            Int32(utf8Count),
            tokens,
            Int32(capacity),
            addBos,
            false
        )

        if tokenCount < 0 {
            let requiredCapacity = Int(-tokenCount)
            guard requiredCapacity > capacity else {
                throw LlamaError.tokenizationFailed
            }
            return try tokenize(
                text: text,
                utf8Count: utf8Count,
                addBos: addBos,
                capacity: requiredCapacity
            )
        }

        return (0..<Int(tokenCount)).map { tokens[$0] }
    }

    private func tokenToPiece(token: llama_token) throws -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: 0, count: 8)
        defer { result.deallocate() }
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, false)
        if nTokens < 0 {
            let requiredCapacity = Int(-nTokens)
            guard requiredCapacity > 0 else {
                throw LlamaError.tokenPieceFailed
            }
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: requiredCapacity)
            newResult.initialize(repeating: 0, count: requiredCapacity)
            defer { newResult.deallocate() }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, -nTokens, 0, false)
            guard nNewTokens >= 0 else {
                throw LlamaError.tokenPieceFailed
            }
            return Array(UnsafeBufferPointer(start: newResult, count: Int(nNewTokens)))
        }
        guard nTokens >= 0 else {
            throw LlamaError.tokenPieceFailed
        }
        return Array(UnsafeBufferPointer(start: result, count: Int(nTokens)))
    }
}
