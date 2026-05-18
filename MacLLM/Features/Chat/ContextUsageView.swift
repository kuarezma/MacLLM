import SwiftUI

struct ContextUsageView: View {
    let usedTokens: Int
    let maxTokens: Int
    var isEstimate: Bool = false
    @State private var showDetail = false

    private var fraction: Double {
        guard maxTokens > 0 else { return 0 }
        return min(1, Double(usedTokens) / Double(maxTokens))
    }

    private var percentText: String {
        String(format: "%.0f%%", fraction * 100)
    }

    private var ringColor: Color {
        if fraction > 0.85 { return .orange }
        if fraction > 0.6 { return AppTheme.accent }
        return AppTheme.accentTertiary
    }

    var body: some View {
        Button {
            showDetail.toggle()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AngularGradient(
                            colors: [ringColor.opacity(0.5), ringColor, AppTheme.accentSecondary],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)
                    .animation(AppTheme.springSoft, value: fraction)
                Text(percentText)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .minimumScaleFactor(0.5)
            }
        }
        .buttonStyle(ModernScaleButtonStyle())
        .help(isEstimate ? "Bağlam kullanımı (tahmini)" : "Bağlam kullanımı")
        .popover(isPresented: $showDetail, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(percentText)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    ProgressView(value: fraction)
                        .tint(ringColor)
                        .frame(width: 80)
                }
                Text("\(formatTokens(usedTokens)) / \(formatTokens(maxTokens))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                LabeledContent("Metin", value: formatTokens(usedTokens))
                LabeledContent("Kalan", value: formatTokens(max(0, maxTokens - usedTokens)))
                if isEstimate {
                    Text("Model yüklendiğinde gerçek token sayımı kullanılır.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(14)
            .frame(width: 220)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1024 {
            return String(format: "%.1fK", Double(count) / 1024)
        }
        return "\(count)"
    }
}
