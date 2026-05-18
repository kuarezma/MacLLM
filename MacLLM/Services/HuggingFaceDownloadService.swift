import Foundation

@MainActor
final class HuggingFaceDownloadService: ObservableObject {
    static let shared = HuggingFaceDownloadService()

    @Published private(set) var activeDownloads: [DownloadTaskInfo] = []

    private var sessions: [String: URLSession] = [:]

    private init() {}

    func download(
        entry: CatalogEntry,
        onUpdate: @escaping (DownloadTaskInfo) -> Void
    ) async throws -> URL {
        let available = ModelStore.shared.availableDiskBytes() ?? .max
        if available < entry.estimatedSizeBytes + 500_000_000 {
            throw NSError(
                domain: "MacLLM",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Yetersiz disk alanı. En az \(ByteCountFormatter.string(fromByteCount: entry.estimatedSizeBytes, countStyle: .file)) boş alan gerekir."]
            )
        }

        let dest = ModelStore.shared.destinationURL(repoId: entry.repoId, filename: entry.filename)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }

        let url = ModelCatalogService.shared.resolveDownloadURL(repoId: entry.repoId, filename: entry.filename)

        var info = DownloadTaskInfo(
            id: entry.id,
            catalogEntry: entry,
            progress: 0,
            bytesReceived: 0,
            totalBytes: entry.estimatedSizeBytes,
            state: .downloading,
            errorMessage: nil
        )
        upsertActive(info)
        onUpdate(info)

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                entry: entry,
                destination: dest,
                onProgress: { [weak self] updated in
                    Task { @MainActor in
                        self?.upsertActive(updated)
                        onUpdate(updated)
                    }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in
                        self?.sessions[entry.id] = nil
                        switch result {
                        case .success(let url):
                            var done = info
                            done.state = .completed
                            done.progress = 1
                            self?.upsertActive(done)
                            continuation.resume(returning: url)
                        case .failure(let error):
                            var failed = info
                            failed.state = .failed
                            failed.errorMessage = error.localizedDescription
                            self?.upsertActive(failed)
                            continuation.resume(throwing: error)
                        }
                    }
                }
            )
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 60 * 60 * 6
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: OperationQueue.main)
            sessions[entry.id] = session
            var request = URLRequest(url: url)
            HuggingFaceCredentials.applyAuth(to: &request)
            let task = session.downloadTask(with: request)
            delegate.task = task
            task.resume()
        }
    }

    func cancelDownload(id: String) {
        let session = sessions[id]
        session?.invalidateAndCancel()
        sessions[id] = nil
        if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
            activeDownloads[index].state = .cancelled
        }
    }

    private func upsertActive(_ info: DownloadTaskInfo) {
        if let i = activeDownloads.firstIndex(where: { $0.id == info.id }) {
            activeDownloads[i] = info
        } else {
            activeDownloads.append(info)
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let entry: CatalogEntry
    let destination: URL
    let onProgress: (DownloadTaskInfo) -> Void
    let onComplete: (Result<URL, Error>) -> Void
    weak var task: URLSessionDownloadTask?
    private var finished = false

    init(
        entry: CatalogEntry,
        destination: URL,
        onProgress: @escaping (DownloadTaskInfo) -> Void,
        onComplete: @escaping (Result<URL, Error>) -> Void
    ) {
        self.entry = entry
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !finished else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finished = true
            onComplete(.success(destination))
        } catch {
            finished = true
            onComplete(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, !finished else { return }
        finished = true
        onComplete(.failure(error))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : entry.estimatedSizeBytes
        let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        onProgress(DownloadTaskInfo(
            id: entry.id,
            catalogEntry: entry,
            progress: min(1, progress),
            bytesReceived: totalBytesWritten,
            totalBytes: total,
            state: .downloading,
            errorMessage: nil
        ))
    }
}
