import SwiftUI

@MainActor
final class DiffViewerCardUIState: ObservableObject {
    @Published var isExpanded = true
}

struct DiffViewerCardView: View {
    let patch: PendingCodePatch
    @ObservedObject private var executor = AgentToolExecutor.shared
    @StateObject private var ui = DiffViewerCardUIState()

    private var diffResult: DiffResult {
        DiffEngine.computeDiff(
            original: patch.originalFileContent,
            proposed: patch.proposedFileContent
        )
    }

    init(patch: PendingCodePatch) {
        self.patch = patch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                fileIconView
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(patch.relativePath)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    
                    if !patch.explanation.isEmpty {
                        Text(patch.explanation)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Diff stats badge (+N / -N)
                HStack(spacing: 4) {
                    if diffResult.additionsCount > 0 {
                        Text("+\(diffResult.additionsCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.diffAdditionText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.diffAdditionBg, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if diffResult.deletionsCount > 0 {
                        Text("-\(diffResult.deletionsCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.diffDeletionText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.diffDeletionBg, in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                Button {
                    withAnimation(AppTheme.springSnappy) {
                        ui.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(ui.isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.035))

            if ui.isExpanded {
                Divider()
                    .opacity(0.6)

                // Diff Editor Content
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(diffResult.lines) { line in
                            diffLineRow(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.04))

                Divider()
                    .opacity(0.6)

                // Action Bar
                HStack(spacing: 12) {
                    if patch.isApplied {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Dosyaya uygulandı")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    } else if patch.isRejected {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                            Text("Reddedildi")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Button(role: .destructive) {
                            withAnimation(AppTheme.springSnappy) {
                                executor.rejectPatch(patch)
                            }
                        } label: {
                            Text("Reddet")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button {
                            withAnimation(AppTheme.springSnappy) {
                                executor.applyPatch(patch)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Değişikliği Uygula")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.02))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var fileIconView: some View {
        let ext = (patch.relativePath as NSString).pathExtension.lowercased()
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fileColor(for: ext).opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: fileIconName(for: ext))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(fileColor(for: ext))
        }
    }

    @ViewBuilder
    private func diffLineRow(_ line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Line accent bar
            Rectangle()
                .fill(lineAccentColor(for: line.kind))
                .frame(width: 3)

            // Line numbers (Old / New)
            HStack(spacing: 4) {
                Text(line.oldLineNumber != nil ? "\(line.oldLineNumber!)" : "")
                    .frame(width: 28, alignment: .trailing)
                Text(line.newLineNumber != nil ? "\(line.newLineNumber!)" : "")
                    .frame(width: 28, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary.opacity(0.5))
            .padding(.horizontal, 6)
            .background(AppTheme.codeGutterBackground)

            // Prefix symbol (+ / -)
            Text(prefixSymbol(for: line.kind))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(prefixColor(for: line.kind))
                .frame(width: 14)
                .padding(.leading, 4)

            // Code line
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor(for: line.kind))
                .textSelection(.enabled)

            Spacer(minLength: 16)
        }
        .background(rowBackgroundColor(for: line.kind))
    }

    private func prefixSymbol(for kind: DiffLineKind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .unchanged: return " "
        }
    }

    private func lineAccentColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .unchanged: return .clear
        }
    }

    private func prefixColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return AppTheme.diffAdditionText
        case .deletion: return AppTheme.diffDeletionText
        case .unchanged: return .clear
        }
    }

    private func textColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return .primary
        case .deletion: return .secondary.opacity(0.8)
        case .unchanged: return .primary
        }
    }

    private func rowBackgroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return AppTheme.diffAdditionBg
        case .deletion: return AppTheme.diffDeletionBg
        case .unchanged: return Color.clear
        }
    }

    private func fileIconName(for ext: String) -> String {
        switch ext {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json", "yaml", "yml", "toml": return "doc.text"
        case "md", "txt": return "doc.plaintext"
        case "sh", "zsh", "bash": return "terminal"
        default: return "doc"
        }
    }

    private func fileColor(for ext: String) -> Color {
        switch ext {
        case "swift": return Color(red: 0.98, green: 0.44, blue: 0.25)
        case "py": return Color(red: 0.25, green: 0.55, blue: 0.95)
        case "js", "ts", "jsx", "tsx": return Color(red: 0.92, green: 0.75, blue: 0.2)
        case "json", "yaml", "yml", "toml": return Color(red: 0.65, green: 0.45, blue: 0.95)
        case "md", "txt": return Color(red: 0.35, green: 0.78, blue: 0.95)
        case "sh", "zsh", "bash": return Color(red: 0.25, green: 0.8, blue: 0.45)
        default: return Color.secondary
        }
    }
}
