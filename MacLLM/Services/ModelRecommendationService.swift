import Foundation

enum ModelFitLevel: String, Sendable {
    case ideal
    case workable
    case notRecommended
}

struct ScoredCatalogEntry: Identifiable, Sendable {
    var id: String { entry.id }
    let entry: CatalogEntry
    let fit: ModelFitLevel
    let fitNote: String
    let sortRank: Int
}

final class ModelRecommendationService: Sendable {
    static let shared = ModelRecommendationService()

    func recommend(catalog: [CatalogEntry], profile: MacSystemProfile) -> [ScoredCatalogEntry] {
        let ram = profile.physicalMemoryGB
        let scored = catalog.map { entry -> ScoredCatalogEntry in
            let (fit, note) = fit(for: entry, physicalRAMGB: ram)
            let rank = sortRank(fit: fit, ramHint: entry.ramHintGB)
            return ScoredCatalogEntry(entry: entry, fit: fit, fitNote: note, sortRank: rank)
        }
        return scored.sorted { lhs, rhs in
            if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
            return lhs.entry.ramHintGB < rhs.entry.ramHintGB
        }
    }

    func sectionTitle(profile: MacSystemProfile) -> String {
        "Sizin Mac'iniz için öneriler (\(profile.displaySummary))"
    }

    func guidanceText(profile: MacSystemProfile) -> String {
        switch profile.physicalMemoryGB {
        case ..<10:
            return "8 GB RAM tespit edildi. 1B–3B modeller rahat çalışır; 7B+ modeller için diğer uygulamaları kapatmanız gerekir."
        case 10..<18:
            return "16 GB civarı RAM — 3B–7B modeller bu Mac için iyi bir denge sunar."
        case 18..<26:
            return "24 GB RAM — 7B–8B modelleri rahatlıkla kullanabilirsiniz."
        default:
            return "\(profile.physicalMemoryGB) GB RAM — büyük modeller ve uzun bağlam için uygunsunuz."
        }
    }

    private func fit(for entry: CatalogEntry, physicalRAMGB: Int) -> (ModelFitLevel, String) {
        let need = entry.ramHintGB
        let ram = physicalRAMGB

        if let minRam = entry.minPhysicalRamGB, ram < minRam {
            return (.notRecommended, "En az \(minRam) GB fiziksel RAM önerilir (sizde \(ram) GB).")
        }

        let idealThreshold = Double(ram) * 0.52
        let workableThreshold = Double(ram) * 0.74

        if Double(need) <= idealThreshold {
            return (.ideal, "Bu Mac'te rahatça çalışması beklenir.")
        }
        if Double(need) <= workableThreshold {
            return (.workable, "Çalışır; sohbet sırasında diğer uygulamaları kapatmanız iyi olur.")
        }
        return (.notRecommended, "Yaklaşık \(need) GB bellek ister; \(ram) GB RAM için genelde uygun değil.")
    }

    private func sortRank(fit: ModelFitLevel, ramHint: Int) -> Int {
        switch fit {
        case .ideal: return 0
        case .workable: return 1
        case .notRecommended: return 2 + ramHint
        }
    }
}
