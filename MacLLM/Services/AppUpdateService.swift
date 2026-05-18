import AppKit
import Foundation
import UserNotifications

struct AppReleaseInfo: Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let tagName: String
    let title: String
    let releaseNotes: String
    let htmlURL: URL
    let dmgURL: URL?
    let pkgURL: URL?
    let zipURL: URL?

    var preferredDownloadURL: URL? {
        dmgURL ?? pkgURL ?? zipURL
    }

    var preferredAssetLabel: String {
        if dmgURL != nil { return "DMG" }
        if pkgURL != nil { return "PKG" }
        if zipURL != nil { return "ZIP" }
        return "—"
    }
}

@MainActor
@Observable
final class AppUpdateController {
    static let shared = AppUpdateController()

    private static let repo = "kuarezma/MacLLM"
    private static let dismissedVersionKey = "dismissedAppUpdateVersion"
    private static let autoCheckKey = "appUpdateAutoCheck"
    private static let lastCheckKey = "appUpdateLastCheckDate"

    var availableUpdate: AppReleaseInfo?
    var isChecking = false
    var isDownloading = false
    var downloadProgress: Double = 0
    var downloadStatus: String?
    var lastCheckDate: Date?
    var autoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey) }
    }

    private init() {
        lastCheckDate = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    var currentVersion: String { AppVersion.current }

    func checkForUpdates(userInitiated: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        lastCheckDate = .now
        UserDefaults.standard.set(lastCheckDate, forKey: Self.lastCheckKey)

        do {
            let release = try await fetchLatestRelease()
            let dismissed = UserDefaults.standard.string(forKey: Self.dismissedVersionKey)

            if AppVersion.isVersion(release.version, newerThan: currentVersion),
               dismissed != release.version {
                let wasNil = availableUpdate == nil
                availableUpdate = release
                if wasNil || userInitiated {
                    await postUpdateNotification(release: release)
                }
            } else if userInitiated, availableUpdate == nil {
                downloadStatus = "MacLLM güncel (sürüm \(currentVersion))."
            }
        } catch {
            if userInitiated {
                downloadStatus = "Güncelleme kontrolü başarısız: \(error.localizedDescription)"
            }
        }
    }

    func dismissUpdateForNow() {
        guard let update = availableUpdate else { return }
        UserDefaults.standard.set(update.version, forKey: Self.dismissedVersionKey)
        availableUpdate = nil
    }

    func downloadAndOpenUpdate() async {
        guard let update = availableUpdate, let url = update.preferredDownloadURL else {
            downloadStatus = "İndirilebilir paket bulunamadı."
            return
        }

        isDownloading = true
        downloadProgress = 0
        downloadStatus = "İndiriliyor…"
        defer {
            isDownloading = false
        }

        do {
            let localFile = try await downloadAsset(from: url, suggestedName: url.lastPathComponent)
            downloadProgress = 1
            downloadStatus = "İndirme tamamlandı. Kurulum penceresi açılıyor…"
            NSWorkspace.shared.open(localFile)
            await showInstallInstructions(version: update.version, fileURL: localFile)
        } catch {
            downloadStatus = "İndirme hatası: \(error.localizedDescription)"
        }
    }

    func openReleasePage() {
        guard let url = availableUpdate?.htmlURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func fetchLatestRelease() async throws -> AppReleaseInfo {
        let apiURL = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacLLM-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = decoded.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        var dmg: URL?
        var pkg: URL?
        var zip: URL?
        for asset in decoded.assets ?? [] {
            guard let assetURL = URL(string: asset.browser_download_url) else { continue }
            if asset.name.hasSuffix(".dmg") { dmg = assetURL }
            else if asset.name.hasSuffix(".pkg") { pkg = assetURL }
            else if asset.name.hasSuffix(".zip") { zip = assetURL }
        }

        guard let pageURL = URL(string: decoded.html_url) else {
            throw URLError(.badURL)
        }

        return AppReleaseInfo(
            id: decoded.tag_name,
            version: version,
            tagName: decoded.tag_name,
            title: decoded.name ?? decoded.tag_name,
            releaseNotes: decoded.body ?? "",
            htmlURL: pageURL,
            dmgURL: dmg,
            pkgURL: pkg,
            zipURL: zip
        )
    }

    private func downloadAsset(from url: URL, suggestedName: String) async throws -> URL {
        let updatesDir = ModelStore.shared.appSupportURL.appendingPathComponent("updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
        let destination = updatesDir.appendingPathComponent(suggestedName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = AppUpdateDownloadDelegate(
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                },
                onComplete: { result in
                    switch result {
                    case .success(let tempURL):
                        do {
                            try FileManager.default.moveItem(at: tempURL, to: destination)
                            continuation.resume(returning: destination)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            delegate.task = task
            task.resume()
        }
    }

    private func postUpdateNotification(release: AppReleaseInfo) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "MacLLM güncellemesi mevcut"
        content.body = "Sürüm \(release.version) indirilebilir. Uygulama içinden yükleyebilirsiniz."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "macllm-app-update-\(release.version)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func showInstallInstructions(version: String, fileURL: URL) async {
        let alert = NSAlert()
        alert.messageText = "MacLLM \(version) indirildi"
        if fileURL.pathExtension == "dmg" {
            alert.informativeText = """
            DMG penceresi açıldı. MacLLM simgesini Uygulamalar klasörüne sürükleyin.
            Mevcut sürümü değiştirmek için eski uygulamayı değiştirmeyi onaylayın.
            Kurulumdan sonra MacLLM’i yeniden başlatın.
            """
        } else if fileURL.pathExtension == "pkg" {
            alert.informativeText = "Kurulum sihirbazındaki adımları izleyin, ardından MacLLM’i yeniden başlatın."
        } else {
            alert.informativeText = "Arşivi açın, MacLLM.app dosyasını Uygulamalar klasörüne taşıyın ve uygulamayı yeniden başlatın."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }
}

// MARK: - GitHub API

private struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let assets: [GitHubAsset]?
}

private struct GitHubAsset: Decodable {
    let name: String
    let browser_download_url: String
}

// MARK: - Download delegate

private final class AppUpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void
    let onComplete: (Result<URL, Error>) -> Void
    weak var task: URLSessionDownloadTask?
    private var finished = false
    private let lock = NSLock()

    init(onProgress: @escaping (Double) -> Void, onComplete: @escaping (Result<URL, Error>) -> Void) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        onComplete(.success(location))
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let done = finished
        lock.unlock()
        guard let error, !done else { return }
        lock.lock()
        finished = true
        lock.unlock()
        onComplete(.failure(error))
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }
}
