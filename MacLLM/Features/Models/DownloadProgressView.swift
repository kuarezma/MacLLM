import SwiftUI

struct DownloadProgressView: View {
    let download: DownloadTaskInfo
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    private var isActive: Bool {
        download.state == .downloading || download.state == .paused
    }

    var body: some View {
        if isActive {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: download.progress)

                HStack {
                    Text(String(format: "%.0f%%", download.progress * 100))
                        .fontWeight(.medium)
                    Spacer()
                    Text(DownloadMetrics.formatSpeed(bytesPerSecond: download.bytesPerSecond))
                    Text("·")
                    Text(DownloadMetrics.formatETA(seconds: download.estimatedSecondsRemaining))
                }
                .font(.caption)
                .monospacedDigit()

                Text("\(DownloadMetrics.formatBytes(download.bytesReceived)) / \(DownloadMetrics.formatBytes(download.totalBytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if download.state == .paused {
                    Label("Duraklatıldı", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    if download.state == .paused {
                        Button {
                            onResume()
                        } label: {
                            Label("Devam", systemImage: "play.fill")
                        }
                        .controlSize(.small)
                    } else {
                        Button {
                            onPause()
                        } label: {
                            Label("Durdur", systemImage: "pause.fill")
                        }
                        .controlSize(.small)
                    }

                    Button(role: .destructive) {
                        onCancel()
                    } label: {
                        Label("İptal", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
