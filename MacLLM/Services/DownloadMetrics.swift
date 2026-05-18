import Foundation

enum DownloadMetrics {
    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formatSpeed(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "—" }
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    static func formatETA(seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0, seconds < 86400 * 7 else {
            return "Hesaplanıyor…"
        }
        if seconds < 60 {
            return String(format: "~%d sn", Int(seconds.rounded()))
        }
        if seconds < 3600 {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return s > 0 ? String(format: "~%d dk %d sn", m, s) : String(format: "~%d dk", m)
        }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return m > 0 ? String(format: "~%d sa %d dk", h, m) : String(format: "~%d sa", h)
    }
}

/// Anlık ve yumuşatılmış indirme hızı + kalan süre tahmini.
final class DownloadSpeedTracker: @unchecked Sendable {
    private var lastBytes: Int64 = 0
    private var lastSampleTime: Date?
    private var emaBytesPerSecond: Double = 0

    func reset() {
        lastBytes = 0
        lastSampleTime = nil
        emaBytesPerSecond = 0
    }

    func sample(bytesReceived: Int64, totalBytes: Int64) -> (speed: Double, eta: TimeInterval?) {
        let now = Date()
        defer {
            if lastSampleTime == nil {
                lastBytes = bytesReceived
                lastSampleTime = now
            }
        }

        guard let lastTime = lastSampleTime else { return (0, nil) }
        let interval = now.timeIntervalSince(lastTime)
        guard interval >= 0.25 else {
            return (emaBytesPerSecond, eta(bytesReceived: bytesReceived, totalBytes: totalBytes))
        }

        let delta = Double(bytesReceived - lastBytes)
        guard delta >= 0 else { return (emaBytesPerSecond, nil) }

        let instant = delta / interval
        if emaBytesPerSecond <= 0 {
            emaBytesPerSecond = instant
        } else {
            emaBytesPerSecond = emaBytesPerSecond * 0.75 + instant * 0.25
        }
        lastBytes = bytesReceived
        lastSampleTime = now
        return (emaBytesPerSecond, eta(bytesReceived: bytesReceived, totalBytes: totalBytes))
    }

    private func eta(bytesReceived: Int64, totalBytes: Int64) -> TimeInterval? {
        guard emaBytesPerSecond > 1, totalBytes > bytesReceived else { return nil }
        return Double(totalBytes - bytesReceived) / emaBytesPerSecond
    }
}
