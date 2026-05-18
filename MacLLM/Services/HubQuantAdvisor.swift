import Foundation

struct HubQuantAssessment: Sendable {
    let fit: ModelFitLevel
    let fitNote: String
    let fitTitle: String
    let quantLabel: String?
    let quantSummary: String
    let fileSizeBytes: Int64
    let estimatedRamGB: Int
    let physicalRamGB: Int
    let ramUsageRatio: Double
    let isRecommendedQuant: Bool

    var ramHeadroomGB: Int {
        max(0, physicalRamGB - estimatedRamGB)
    }
}

enum HubQuantAdvisor {
    static func assess(
        file: HFGGUFile,
        repoId: String,
        profile: MacSystemProfile
    ) -> HubQuantAssessment {
        let entry = catalogEntry(for: file, repoId: repoId)
        let scored = ModelRecommendationService.shared
            .recommend(catalog: [entry], profile: profile)
            .first
        let fit = scored?.fit ?? .workable
        let note = scored?.fitNote ?? "Bu quant için bellek tahmini yapılamadı."
        let quant = file.quantLabel
        let estimatedRam = entry.ramHintGB
        let physical = profile.physicalMemoryGB
        let ratio = physical > 0 ? min(1.15, Double(estimatedRam) / Double(physical)) : 1

        return HubQuantAssessment(
            fit: fit,
            fitNote: note,
            fitTitle: fitTitle(for: fit),
            quantLabel: quant,
            quantSummary: quantDescription(for: quant),
            fileSizeBytes: file.sizeBytes,
            estimatedRamGB: estimatedRam,
            physicalRamGB: physical,
            ramUsageRatio: ratio,
            isRecommendedQuant: HubFileListLogic.quantSortRank(filename: file.filename) <= 2 && fit != .notRecommended
        )
    }

    static func fitTitle(for fit: ModelFitLevel) -> String {
        switch fit {
        case .ideal: return "Bu Mac için uygun"
        case .workable: return "Çalışır — bellek sınırında"
        case .notRecommended: return "Bu Mac için muhtemelen ağır"
        }
    }

    static func quantDescription(for quant: String?) -> String {
        guard let quant else {
            return "Quant etiketi dosya adından okunamadı; boyuta göre değerlendirin."
        }
        let q = quant.uppercased()
        if q.contains("Q2") {
            return "En küçük boyut. Hızlıdır ancak yanıt kalitesi düşük olabilir; zayıf RAM'li Mac'ler için son çare."
        }
        if q.contains("Q3") {
            return "Küçük boyut, orta-düşük kalite. Sınırlı RAM'de denenebilir; uzun sohbetlerde zayıflayabilir."
        }
        if q.contains("Q4_K_M") {
            return "En popüler denge: kalite ve boyut arasında iyi orta nokta. Çoğu Mac'te günlük sohbet için önerilir."
        }
        if q.contains("Q4") {
            return "İyi kalite/boyut dengesi. Q4_K_M genelde daha iyi sonuç verir; yine de birçok Mac'te rahat çalışır."
        }
        if q.contains("Q5_K_M") {
            return "Q4'ten daha yüksek kalite, daha fazla RAM ister. 16 GB+ Mac'lerde mantıklı tercih."
        }
        if q.contains("Q5") {
            return "Yüksek kaliteye yakın quant. Daha büyük dosya ve bellek kullanımı bekleyin."
        }
        if q.contains("Q6") {
            return "Yüksek kalite quant. Güçlü Mac ve bol RAM gerektirir."
        }
        if q.contains("Q8") {
            return "En yüksek kalite, en ağır seçenek. Yalnızca çok güçlü Mac'lerde ve kısa bağlamda mantıklı."
        }
        return "\(quant) — dosya boyutuna göre bellek ihtiyacını kontrol edin."
    }

    private static func catalogEntry(for file: HFGGUFile, repoId: String) -> CatalogEntry {
        CatalogEntry(
            id: "\(repoId)-\(file.filename)",
            name: ModelMetadataParser.repoDisplayName(file.filename),
            description: repoId,
            repoId: repoId,
            filename: file.filename,
            estimatedSizeBytes: max(file.sizeBytes, 1),
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: repoId, filename: file.filename),
            ramHintGB: estimatedRamGB(for: file)
        )
    }

    /// GGUF dosya boyutu + Metal/KV overhead (~%40).
    static func estimatedRamGB(for file: HFGGUFile) -> Int {
        max(1, Int(ceil(Double(file.sizeBytes) / 1_073_741_824.0 * 1.4)))
    }
}
