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
        String(format: "%.1f%%", fraction * 100)
    }

    var body: some View {
        Button {
            showDetail.toggle()
        } label: {
            ZStack {
                Circle()
                    .stroke(AppTheme.border, lineWidth: 2)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        fraction > 0.85 ? Color.orange : AppTheme.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 28, height: 28)
                Text(percentText)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .minimumScaleFactor(0.5)
            }
        }
        .buttonStyle(.plain)
        .help(isEstimate ? "Bağlam kullanımı (tahmini)" : "Bağlam kullanımı")
        .popover(isPresented: $showDetail, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(percentText)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    ProgressView(value: fraction)
                        .tint(fraction > 0.85 ? .orange : AppTheme.accent)
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
