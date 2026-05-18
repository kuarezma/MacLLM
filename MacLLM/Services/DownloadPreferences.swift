import Foundation

/// İndirme hızı tercihleri (UserDefaults).
enum DownloadPreferences {
    private static let connectionsKey = "downloadParallelConnections"

    /// Paralel HTTP bağlantı sayısı. 1 = tek akış (duraklat/devam destekli).
    static var parallelConnections: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: connectionsKey)
            if stored == 0 { return 4 }
            return min(8, max(1, stored))
        }
        set {
            UserDefaults.standard.set(min(8, max(1, newValue)), forKey: connectionsKey)
        }
    }

    /// Paralel indirme için minimum dosya boyutu (50 MB).
    static let parallelMinimumBytes: Int64 = 50_000_000
}
