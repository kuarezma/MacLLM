import Foundation
import llama

enum LlamaError: Error, LocalizedError {
    case couldNotInitializeContext
    case templateFailed
    case generationCancelled

    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext:
            return "Model yüklenemedi. Dosya bozuk olabilir veya yetersiz bellek."
        case .templateFailed:
            return "Sohbet şablonu uygulanamadı."
        case .generationCancelled:
            return "Üretim iptal edildi."
        }
    }
}

func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) {
    batch.token[Int(batch.n_tokens)] = id
    batch.pos[Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seq_ids[i]
    }
    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
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

    private var cancelled = false

    init(model: OpaquePointer, context: OpaquePointer, settings: InferenceSettings) {
        self.model = model
        self.context = context
        self.tokens_list = []
        self.batch = llama_batch_init(512, 0, 1)
        self.temporary_invalid_cchars = []
        self.n_len = settings.maxTokens
        vocab = llama_model_get_vocab(model)

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
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_model_free(model)
        llama_free(context)
        LlamaBackend.release()
    }

    static func createContext(path: String, settings: InferenceSettings) throws -> LlamaContext {
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
        var ctx_params = llama_context_default_params()
        ctx_params.n_ctx = settings.contextLength
        ctx_params.n_threads = n_threads
        ctx_params.n_threads_batch = n_threads

        guard let context = llama_init_from_model(model, ctx_params) else {
            llama_model_free(model)
            LlamaBackend.release()
            throw LlamaError.couldNotInitializeContext
        }

        return LlamaContext(model: model, context: context, settings: settings)
    }

    func cancel() {
        cancelled = true
    }

    func applyChatTemplate(messages: [ChatMessage], templateName: String) throws -> String {
        let tmpl = templateName.isEmpty ? "chatml" : templateName
        var cMessages: [llama_chat_message] = messages.map { msg in
            llama_chat_message(
                role: (msg.role.rawValue as NSString).utf8String,
                content: (msg.content as NSString).utf8String
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
            if written > bufferSize {
                bufferSize = Int(written) + 256
                continue
            }
            return String(cString: buffer)
        }
        throw LlamaError.templateFailed
    }

    func completionInit(text: String) throws {
        cancelled = false
        is_done = false
        tokens_list = tokenize(text: text, add_bos: true)
        temporary_invalid_cchars = []

        let n_ctx = llama_n_ctx(context)
        let n_kv_req = tokens_list.count + (Int(n_len) - tokens_list.count)
        if n_kv_req > n_ctx {
            throw LlamaError.couldNotInitializeContext
        }

        llama_batch_clear(&batch)
        for i in 0..<tokens_list.count {
            llama_batch_add(&batch, tokens_list[i], Int32(i), [0], false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1

        if llama_decode(context, batch) != 0 {
            throw LlamaError.couldNotInitializeContext
        }
        n_cur = batch.n_tokens
    }

    func completionLoop() throws -> String {
        if cancelled {
            is_done = true
            throw LlamaError.generationCancelled
        }

        let new_token_id = llama_sampler_sample(sampling, context, batch.n_tokens - 1)

        if llama_vocab_is_eog(vocab, new_token_id) || n_cur >= n_len {
            is_done = true
            let tail = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return tail
        }

        let new_token_cchars = tokenToPiece(token: new_token_id)
        temporary_invalid_cchars.append(contentsOf: new_token_cchars)

        let new_token_str: String
        if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else {
            new_token_str = ""
        }

        llama_batch_clear(&batch)
        llama_batch_add(&batch, new_token_id, n_cur, [0], true)
        n_decode += 1
        n_cur += 1

        if llama_decode(context, batch) != 0 {
            throw LlamaError.couldNotInitializeContext
        }

        return new_token_str
    }

    func clear() {
        tokens_list.removeAll()
        temporary_invalid_cchars.removeAll()
        is_done = false
        cancelled = false
        llama_memory_clear(llama_get_memory(context), true)
    }

    func modelDescription() -> String {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        result.initialize(repeating: 0, count: 256)
        defer { result.deallocate() }
        let nChars = llama_model_desc(model, result, 256)
        return String(cString: Array(UnsafeBufferPointer(start: result, count: Int(nChars))) + [0])
    }

    private func tokenize(text: String, add_bos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let n_tokens = utf8Count + (add_bos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: n_tokens)
        defer { tokens.deallocate() }
        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(n_tokens), add_bos, false)
        return (0..<tokenCount).map { tokens[Int($0)] }
    }

    private func tokenToPiece(token: llama_token) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: 0, count: 8)
        defer { result.deallocate() }
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, false)
        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: 0, count: Int(-nTokens))
            defer { newResult.deallocate() }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, -nTokens, 0, false)
            return Array(UnsafeBufferPointer(start: newResult, count: Int(nNewTokens)))
        }
        return Array(UnsafeBufferPointer(start: result, count: Int(nTokens)))
    }
}
