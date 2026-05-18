import Foundation

struct DownloadResourceMetadata: Sendable {
    let url: URL
    let totalBytes: Int64
    let supportsRanges: Bool
}

enum RangeDownloadEngine {
    private static func makeSession(maxConnections: Int) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.httpMaximumConnectionsPerHost = max(1, maxConnections)
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    /// HF resolve URL → CDN yönlendirmesi + boyut + Range desteği.
    static func resolveMetadata(repoId: String, filename: String) async throws -> DownloadResourceMetadata {
        let resolveURL = ModelCatalogService.shared.resolveDownloadURL(repoId: repoId, filename: filename)
        var request = URLRequest(url: resolveURL)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("MacLLM", forHTTPHeaderField: "User-Agent")
        HuggingFaceCredentials.applyAuth(to: &request)

        let session = makeSession(maxConnections: 2)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw downloadError("Sunucu yanıtı okunamadı.")
        }
        guard (200...299).contains(http.statusCode) || http.statusCode == 206 else {
            throw downloadError("HTTP \(http.statusCode)")
        }

        let finalURL = http.url ?? resolveURL
        let total = parseTotalBytes(from: http)
        let rangeOK = http.statusCode == 206
            || http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") == true

        return DownloadResourceMetadata(
            url: finalURL,
            totalBytes: total,
            supportsRanges: rangeOK && total > 0
        )
    }

    /// Paralel Range istekleri ile dosyayı indirir.
    static func downloadParallel(
        metadata: DownloadResourceMetadata,
        destination: URL,
        connections: Int,
        speedTracker: DownloadSpeedTracker,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable @MainActor (DownloadTaskInfo) -> Void,
        entry: CatalogEntry
    ) async throws {
        let total = metadata.totalBytes
        guard total > 0, connections > 1 else {
            throw downloadError("Paralel indirme için geçersiz boyut.")
        }

        let tempDir = destination.deletingLastPathComponent()
            .appendingPathComponent(".download-\(entry.id)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)

        let chunkCount = connections
        let chunkSize = (total + Int64(chunkCount) - 1) / Int64(chunkCount)
        let aggregator = ParallelProgressTracker(totalBytes: total, chunkCount: chunkCount)
        let session = makeSession(maxConnections: chunkCount)

        let progressPoller = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(200))
                let received = aggregator.sumPartFiles(in: tempDir)
                let (speed, eta) = speedTracker.sample(bytesReceived: received, totalBytes: total)
                await onProgress(DownloadTaskInfo(
                    id: entry.id,
                    catalogEntry: entry,
                    progress: min(1, Double(received) / Double(total)),
                    bytesReceived: received,
                    totalBytes: total,
                    bytesPerSecond: speed,
                    estimatedSecondsRemaining: eta,
                    state: .downloading,
                    errorMessage: nil
                ))
            }
        }
        defer { progressPoller.cancel() }

        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for index in 0..<chunkCount {
                let start = Int64(index) * chunkSize
                let end = min(start + chunkSize - 1, total - 1)
                guard start <= end else { continue }

                group.addTask {
                    if isCancelled() { throw CancellationError() }
                    let partURL = tempDir.appendingPathComponent(String(format: "part-%04d", index))
                    try await downloadRange(
                        session: session,
                        url: metadata.url,
                        start: start,
                        end: end,
                        destination: partURL,
                        isCancelled: isCancelled
                    )
                    return (index, partURL)
                }
            }

            var completedParts: [(Int, URL)] = []
            while let part = try await group.next() {
                if isCancelled() {
                    group.cancelAll()
                    throw CancellationError()
                }
                completedParts.append(part)
            }

            completedParts.sort { $0.0 < $1.0 }
            try mergeParts(completedParts.map(\.1), into: destination)
        }

        session.finishTasksAndInvalidate()
    }

    private static let streamBufferSize = 512 * 1024

    private static func downloadRange(
        session: URLSession,
        url: URL,
        start: Int64,
        end: Int64,
        destination: URL,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("MacLLM", forHTTPHeaderField: "User-Agent")
        HuggingFaceCredentials.applyAuth(to: &request)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw downloadError("Parça yanıtı geçersiz.")
        }
        guard http.statusCode == 206 || http.statusCode == 200 else {
            throw downloadError("Parça indirilemedi (HTTP \(http.statusCode)).")
        }

        var buffer = Data()
        buffer.reserveCapacity(streamBufferSize)
        for try await byte in bytes {
            if isCancelled() { throw CancellationError() }
            buffer.append(byte)
            if buffer.count >= streamBufferSize {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
    }

    private static func mergeParts(_ parts: [URL], into destination: URL) throws {
        let out = try FileHandle(forWritingTo: destination)
        defer { try? out.close() }

        for partURL in parts {
            let input = try FileHandle(forReadingFrom: partURL)
            defer { try? input.close() }
            while true {
                let block = try input.read(upToCount: 4 * 1024 * 1024) ?? Data()
                if block.isEmpty { break }
                try out.write(contentsOf: block)
            }
        }
    }

    private static func parseTotalBytes(from response: HTTPURLResponse) -> Int64 {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let slash = range.lastIndex(of: "/") {
            let totalStr = range[range.index(after: slash)...]
            if let total = Int64(totalStr) { return total }
        }
        if let linked = response.value(forHTTPHeaderField: "X-Linked-Size"),
           let total = Int64(linked) {
            return total
        }
        let length = response.expectedContentLength
        if length > 0 { return length }
        if let header = response.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(header) {
            return length
        }
        return 0
    }

    private static func downloadError(_ message: String) -> NSError {
        NSError(domain: "MacLLM", code: 103, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Paralel parça ilerlemesi — geçici dosya boyutlarını toplar.
private final class ParallelProgressTracker: @unchecked Sendable {
    private let totalBytes: Int64

    init(totalBytes: Int64, chunkCount: Int) {
        self.totalBytes = totalBytes
        _ = chunkCount
    }

    func sumPartFiles(in directory: URL) -> Int64 {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var sum: Int64 = 0
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            sum += size
        }
        return min(totalBytes, sum)
    }
}
