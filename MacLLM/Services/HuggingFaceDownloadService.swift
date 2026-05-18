import Foundation

@MainActor
final class HuggingFaceDownloadService: ObservableObject {
    static let shared = HuggingFaceDownloadService()

    @Published private(set) var activeDownloads: [DownloadTaskInfo] = []

    private final class DownloadContext {
        let entry: CatalogEntry
        let destination: URL
        let session: URLSession
        let delegate: DownloadDelegate
        let task: URLSessionDownloadTask
        var onUpdate: (DownloadTaskInfo) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        var didFinish = false

        init(
            entry: CatalogEntry,
            destination: URL,
            session: URLSession,
            delegate: DownloadDelegate,
            task: URLSessionDownloadTask,
            onUpdate: @escaping (DownloadTaskInfo) -> Void,
            continuation: CheckedContinuation<URL, Error>?
        ) {
            self.entry = entry
            self.destination = destination
            self.session = session
            self.delegate = delegate
            self.task = task
            self.onUpdate = onUpdate
            self.continuation = continuation
        }
    }

    private var contexts: [String: DownloadContext] = [:]

    private init() {}

    func download(
        entry: CatalogEntry,
        onUpdate: @escaping (DownloadTaskInfo) -> Void
    ) async throws -> URL {
        if contexts[entry.id] != nil {
            if activeDownloads.first(where: { $0.id == entry.id })?.state == .paused {
                resumeDownload(id: entry.id)
            }
            throw NSError(
                domain: "MacLLM",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "“\(entry.name)” zaten indiriliyor."]
            )
        }

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
        let initial = makeTaskInfo(
            entry: entry,
            bytesReceived: 0,
            totalBytes: entry.estimatedSizeBytes,
            speed: 0,
            eta: nil,
            state: .downloading
        )
        upsertActive(initial)
        onUpdate(initial)

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(entry: entry, destination: dest)

            delegate.onProgress = { [weak self] updated in
                Task { @MainActor in
                    self?.upsertActive(updated)
                    self?.contexts[entry.id]?.onUpdate(updated)
                }
            }

            delegate.onComplete = { [weak self] result in
                Task { @MainActor in
                    self?.finishDownload(entryId: entry.id, entry: entry, result: result)
                }
            }

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 60 * 60 * 6
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: OperationQueue.main)

            var request = URLRequest(url: url)
            HuggingFaceCredentials.applyAuth(to: &request)
            let task = session.downloadTask(with: request)
            delegate.task = task

            let context = DownloadContext(
                entry: entry,
                destination: dest,
                session: session,
                delegate: delegate,
                task: task,
                onUpdate: onUpdate,
                continuation: continuation
            )
            contexts[entry.id] = context
            task.resume()
        }
    }

    func pauseDownload(id: String) {
        guard let ctx = contexts[id],
              let index = activeDownloads.firstIndex(where: { $0.id == id }),
              activeDownloads[index].state == .downloading else { return }

        ctx.task.suspend()
        var info = activeDownloads[index]
        info.state = .paused
        upsertActive(info)
        ctx.onUpdate(info)
    }

    func resumeDownload(id: String) {
        guard let ctx = contexts[id],
              let index = activeDownloads.firstIndex(where: { $0.id == id }),
              activeDownloads[index].state == .paused else { return }

        ctx.task.resume()
        var info = activeDownloads[index]
        info.state = .downloading
        upsertActive(info)
        ctx.onUpdate(info)
    }

    func cancelDownload(id: String) {
        guard let ctx = contexts[id] else {
            if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
                activeDownloads[index].state = .cancelled
            }
            return
        }

        finishDownload(entryId: id, entry: ctx.entry, result: .failure(CancellationError()))
        ctx.task.cancel()
        ctx.session.invalidateAndCancel()

        if FileManager.default.fileExists(atPath: ctx.destination.path) {
            try? FileManager.default.removeItem(at: ctx.destination)
        }
    }

    private func finishDownload(entryId: String, entry: CatalogEntry, result: Result<URL, Error>) {
        guard let ctx = contexts[entryId], !ctx.didFinish else { return }
        ctx.didFinish = true
        contexts[entryId] = nil

        switch result {
        case .success(let fileURL):
            var done = activeDownloads.first(where: { $0.id == entryId })
                ?? makeTaskInfo(
                    entry: entry,
                    bytesReceived: entry.estimatedSizeBytes,
                    totalBytes: entry.estimatedSizeBytes,
                    speed: 0,
                    eta: nil,
                    state: .completed
                )
            done.state = .completed
            done.progress = 1
            upsertActive(done)
            ctx.continuation?.resume(returning: fileURL)
        case .failure(let error) where error is CancellationError:
            var cancelled = activeDownloads.first(where: { $0.id == entryId })
                ?? makeTaskInfo(
                    entry: entry,
                    bytesReceived: 0,
                    totalBytes: entry.estimatedSizeBytes,
                    speed: 0,
                    eta: nil,
                    state: .cancelled
                )
            cancelled.state = .cancelled
            upsertActive(cancelled)
            ctx.continuation?.resume(throwing: error)
        case .failure(let error as NSError) where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled:
            var cancelled = activeDownloads.first(where: { $0.id == entryId })
                ?? makeTaskInfo(
                    entry: entry,
                    bytesReceived: 0,
                    totalBytes: entry.estimatedSizeBytes,
                    speed: 0,
                    eta: nil,
                    state: .cancelled
                )
            cancelled.state = .cancelled
            upsertActive(cancelled)
            ctx.continuation?.resume(throwing: CancellationError())
        case .failure(let error):
            var failed = activeDownloads.first(where: { $0.id == entryId })
                ?? makeTaskInfo(
                    entry: entry,
                    bytesReceived: 0,
                    totalBytes: entry.estimatedSizeBytes,
                    speed: 0,
                    eta: nil,
                    state: .failed
                )
            failed.state = .failed
            failed.errorMessage = error.localizedDescription
            upsertActive(failed)
            ctx.continuation?.resume(throwing: error)
        }
        ctx.continuation = nil
    }

    private func makeTaskInfo(
        entry: CatalogEntry,
        bytesReceived: Int64,
        totalBytes: Int64,
        speed: Double,
        eta: TimeInterval?,
        state: DownloadState,
        errorMessage: String? = nil
    ) -> DownloadTaskInfo {
        let progress = totalBytes > 0 ? min(1, Double(bytesReceived) / Double(totalBytes)) : 0
        return DownloadTaskInfo(
            id: entry.id,
            catalogEntry: entry,
            progress: progress,
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
            bytesPerSecond: speed,
            estimatedSecondsRemaining: eta,
            state: state,
            errorMessage: errorMessage
        )
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
    var speedTracker = DownloadSpeedTracker()
    var onProgress: (DownloadTaskInfo) -> Void = { _ in }
    var onComplete: (Result<URL, Error>) -> Void = { _ in }
    weak var task: URLSessionDownloadTask?
    private var finished = false
    private let lock = NSLock()

    init(entry: CatalogEntry, destination: URL) {
        self.entry = entry
        self.destination = destination
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        lock.unlock()

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            lock.lock()
            finished = true
            lock.unlock()
            onComplete(.success(destination))
        } catch {
            lock.lock()
            finished = true
            lock.unlock()
            onComplete(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let done = finished
        lock.unlock()
        guard let error, !done else { return }

        lock.lock()
        finished = true
        lock.unlock()
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
        let (speed, eta) = speedTracker.sample(bytesReceived: totalBytesWritten, totalBytes: total)
        let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        let state: DownloadState = downloadTask.state == .suspended ? .paused : .downloading
        onProgress(DownloadTaskInfo(
            id: entry.id,
            catalogEntry: entry,
            progress: min(1, progress),
            bytesReceived: totalBytesWritten,
            totalBytes: total,
            bytesPerSecond: speed,
            estimatedSecondsRemaining: eta,
            state: state,
            errorMessage: nil
        ))
    }
}
