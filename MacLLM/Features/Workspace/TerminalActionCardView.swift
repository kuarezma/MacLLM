import SwiftUI

@MainActor
final class TerminalActionCardUIState: ObservableObject {
    @Published var isRunning = false
}

struct TerminalActionCardView: View {
    let command: PendingTerminalCommand
    @ObservedObject private var executor = AgentToolExecutor.shared
    @StateObject private var ui = TerminalActionCardUIState()

    init(command: PendingTerminalCommand) {
        self.command = command
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Terminal Header with macOS Window Dots
            HStack(spacing: 8) {
                // Window traffic lights
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.34)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.22)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.34)).frame(width: 8, height: 8)
                }
                .padding(.trailing, 4)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.accentSecondary)

                Text("Terminal Komutu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                if command.isExecuted {
                    if command.exitCode == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Tamamlandı (0)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Hata (\(command.exitCode ?? 1))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))

            if !command.explanation.isEmpty {
                Text(command.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            // Command Box (Slate Console Aesthetic)
            HStack(alignment: .top, spacing: 6) {
                Text("$")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.accentTertiary)

                Text(command.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(10)
            .background(AppTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AppTheme.terminalBorder, lineWidth: 0.5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Output Box if executed
            if let output = command.output, !output.isEmpty {
                Divider().opacity(0.6)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Çıktı:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Çıktıyı kopyala")
                    }

                    ScrollView(.horizontal) {
                        Text(output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryText)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxHeight: 160)
                .background(Color.black.opacity(0.05))
            }

            // Action Bar
            if !command.isExecuted {
                Divider().opacity(0.6)
                
                HStack {
                    Spacer()
                    Button {
                        ui.isRunning = true
                        executor.executeTerminalCommand(command) { _, _ in
                            ui.isRunning = false
                        }
                    } label: {
                        if ui.isRunning {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Çalıştırılıyor…")
                                    .font(.system(size: 12))
                            }
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                Text("Komutu Çalıştır")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                    .disabled(ui.isRunning)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.vertical, 4)
    }
}
