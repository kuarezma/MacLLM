import Foundation
import llama

@_silgen_name("mtmd_shim_create")
private func mtmd_shim_create(
    _ mmproj: UnsafePointer<CChar>?,
    _ model: OpaquePointer?,
    _ nThreads: Int32,
    _ useGpu: Bool
) -> OpaquePointer?

@_silgen_name("mtmd_shim_free")
private func mtmd_shim_free(_ handle: OpaquePointer?)

@_silgen_name("mtmd_shim_supports_vision")
private func mtmd_shim_supports_vision(_ handle: OpaquePointer?) -> Bool

@_silgen_name("mtmd_shim_supports_audio")
private func mtmd_shim_supports_audio(_ handle: OpaquePointer?) -> Bool

@_silgen_name("mtmd_shim_eval_prompt")
private func mtmd_shim_eval_prompt(
    _ handle: OpaquePointer?,
    _ lctx: OpaquePointer?,
    _ prompt: UnsafePointer<CChar>?,
    _ paths: UnsafePointer<UnsafePointer<CChar>?>?,
    _ nMedia: Int,
    _ nBatch: Int32,
    _ nPastIn: Int32,
    _ nPastOut: UnsafeMutablePointer<Int32>?
) -> Int32

enum MtmdError: Error, LocalizedError {
    case loadFailed
    case evalFailed(Int32)
    case noProjector

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "Görüntü/ses projeksiyon modeli (mmproj) yüklenemedi."
        case .evalFailed(let code):
            return "Çok modlu girdi işlenemedi (kod \(code))."
        case .noProjector:
            return "Bu model için mmproj dosyası gerekli. Aynı klasöre mmproj GGUF ekleyin."
        }
    }
}

final class MtmdShim {
    private var handle: OpaquePointer?

    var supportsVision: Bool {
        guard let handle else { return false }
        return mtmd_shim_supports_vision(handle)
    }

    var supportsAudio: Bool {
        guard let handle else { return false }
        return mtmd_shim_supports_audio(handle)
    }

    func load(mmprojPath: String, model: OpaquePointer, nThreads: Int32) throws {
        unload()
        guard let h = mtmd_shim_create(mmprojPath, model, nThreads, true) else {
            throw MtmdError.loadFailed
        }
        handle = h
    }

    func unload() {
        if let handle {
            mtmd_shim_free(handle)
        }
        handle = nil
    }

    deinit { unload() }

    func evalPrompt(
        prompt: String,
        mediaPaths: [String],
        llamaContext: OpaquePointer,
        nPast: Int32,
        nBatch: Int32
    ) throws -> Int32 {
        guard let handle else { throw MtmdError.noProjector }
        guard !mediaPaths.isEmpty else { return nPast }

        var outPast: llama_pos = nPast
        let code: Int32 = mediaPaths.withCStringArray { cPaths in
            prompt.withCString { cPrompt in
                mtmd_shim_eval_prompt(
                    handle,
                    llamaContext,
                    cPrompt,
                    cPaths,
                    mediaPaths.count,
                    nBatch,
                    nPast,
                    &outPast
                )
            }
        }
        guard code == 0 else { throw MtmdError.evalFailed(code) }
        return outPast
    }
}

private extension Array where Element == String {
    func withCStringArray<R>(_ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var cStrings: [UnsafeMutablePointer<CChar>?] = []
        cStrings.reserveCapacity(count)
        for string in self {
            cStrings.append(strdup(string))
        }
        defer {
            for ptr in cStrings {
                if let ptr { free(ptr) }
            }
        }
        var pointers: [UnsafePointer<CChar>?] = cStrings.map { ptr in
            guard let ptr else { return nil }
            return UnsafePointer(ptr)
        }
        return pointers.withUnsafeBufferPointer { buf in
            body(buf.baseAddress)
        }
    }
}
