import Foundation

/// Uygulama kapanırken yeniden model yükleme / ayar kaydı gibi işlemleri engeller.
enum AppShutdown {
    static var isShuttingDown = false
}
