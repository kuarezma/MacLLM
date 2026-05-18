import SwiftUI

/// Seçili quant için Mac uyumluluk özeti (LM Studio tarzı).
struct HubQuantFitCard: View {
    let assessment: HubQuantAssessment
    let profile: MacSystemProfile

    private var fitColor: Color {
        switch assessment.fit {
        case .ideal: return .green
        case .workable: return .orange
        case .notRecommended: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: fitIcon)
                    .font(.title3)
                    .foregroundStyle(fitColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(assessment.fitTitle)
                            .font(.subheadline.weight(.semibold))
                        AppTheme.fitBadge(assessment.fit)
                        if assessment.isRecommendedQuant {
                            AppTheme.badge("Önerilen quant", color: .blue)
                        }
                    }
                    Text(assessment.fitNote)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let quant = assessment.quantLabel {
                HStack(spacing: 8) {
                    AppTheme.badge(quant, color: AppTheme.accent)
                    Text(assessment.quantSummary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ramUsageBar

            statsGrid
        }
        .padding(14)
        .background(fitColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .strokeBorder(fitColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var fitIcon: String {
        switch assessment.fit {
        case .ideal: return "checkmark.circle.fill"
        case .workable: return "exclamationmark.triangle.fill"
        case .notRecommended: return "xmark.octagon.fill"
        }
    }

    private var ramUsageBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tahmini bellek kullanımı")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text("\(assessment.estimatedRamGB) / \(assessment.physicalRamGB) GB")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.border)
                    Capsule()
                        .fill(barGradient)
                        .frame(width: geo.size.width * min(1, assessment.ramUsageRatio))
                }
            }
            .frame(height: 8)

            Text(ramBarCaption)
                .font(.caption2)
                .foregroundStyle(fitColor)
        }
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [fitColor.opacity(0.7), fitColor],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var ramBarCaption: String {
        switch assessment.fit {
        case .ideal:
            return "Yaklaşık \(assessment.ramHeadroomGB) GB boş bellek kalması beklenir."
        case .workable:
            return "Sohbet sırasında diğer uygulamaları kapatmanız iyi olur."
        case .notRecommended:
            return "Model belleğe sığmayabilir veya sistem yavaşlayabilir."
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statCell(
                title: "Dosya",
                value: ModelMetadataParser.formatFileSize(bytes: assessment.fileSizeBytes)
            )
            Divider().frame(height: 32)
            statCell(
                title: "Tahmini RAM",
                value: "~\(assessment.estimatedRamGB) GB"
            )
            Divider().frame(height: 32)
            statCell(
                title: "Bu Mac",
                value: profile.displaySummary
            )
        }
        .padding(.vertical, 8)
        .background(AppTheme.composerBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
