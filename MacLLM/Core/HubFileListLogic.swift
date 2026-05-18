import Foundation

enum HubQuantSort: String, CaseIterable, Identifiable {
    case recommended
    case sizeAscending
    case sizeDescending
    case quantAscending
    case quantDescending
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: return "Önerilen"
        case .sizeAscending: return "Boyut ↑"
        case .sizeDescending: return "Boyut ↓"
        case .quantAscending: return "Quant ↑"
        case .quantDescending: return "Quant ↓"
        case .name: return "Ad (A–Z)"
        }
    }
}

enum HubQuantFilter: String, CaseIterable, Identifiable {
    case all
    case q2
    case q3
    case q4
    case q5
    case q6
    case q8
    case macFriendly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tümü"
        case .q2: return "Q2"
        case .q3: return "Q3"
        case .q4: return "Q4"
        case .q5: return "Q5"
        case .q6: return "Q6"
        case .q8: return "Q8"
        case .macFriendly: return "Mac'e uygun"
        }
    }
}

enum HubFileListLogic {
    /// Düşük değer = daha yaygın / önerilen quant (Q4_K_M önce).
    static func quantSortRank(filename: String) -> Int {
        let lower = filename.lowercased()
        let ordered = [
            "q4_k_m", "q4_k_s", "q4_0",
            "q5_k_m", "q5_k_s", "q5_0",
            "q3_k_m", "q3_k_l", "q3_k_s", "q3_k",
            "q6_k", "q6_k_l",
            "q2_k", "q2_k_l",
            "q8_0", "q8_k",
            "iq4_xs", "iq3_xxs",
        ]
        for (index, pattern) in ordered.enumerated() {
            if lower.contains(pattern) { return index }
        }
        return 100
    }

    static func matches(filter: HubQuantFilter, file: HFGGUFile) -> Bool {
        switch filter {
        case .all:
            return true
        case .macFriendly:
            return false
        case .q2:
            return matchesQuantPrefix("Q2", file: file)
        case .q3:
            return matchesQuantPrefix("Q3", file: file)
        case .q4:
            return matchesQuantPrefix("Q4", file: file)
        case .q5:
            return matchesQuantPrefix("Q5", file: file)
        case .q6:
            return matchesQuantPrefix("Q6", file: file)
        case .q8:
            return matchesQuantPrefix("Q8", file: file)
        }
    }

    static func filterAndSort(
        files: [HFGGUFile],
        filter: HubQuantFilter,
        sort: HubQuantSort,
        fitLevels: [String: ModelFitLevel]
    ) -> [HFGGUFile] {
        var result = files
        if filter == .macFriendly {
            result = result.filter { fitLevels[$0.id] == .ideal || fitLevels[$0.id] == .workable }
        } else if filter != .all {
            result = result.filter { matches(filter: filter, file: $0) }
        }

        switch sort {
        case .sizeAscending:
            result.sort { $0.sizeBytes < $1.sizeBytes }
        case .sizeDescending:
            result.sort { $0.sizeBytes > $1.sizeBytes }
        case .quantAscending:
            result.sort {
                quantSortRank(filename: $0.filename) < quantSortRank(filename: $1.filename)
            }
        case .quantDescending:
            result.sort {
                quantSortRank(filename: $0.filename) > quantSortRank(filename: $1.filename)
            }
        case .name:
            result.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
        case .recommended:
            result.sort { lhs, rhs in
                let lFit = fitLevels[lhs.id]
                let rFit = fitLevels[rhs.id]
                let lScore = fitScore(lFit)
                let rScore = fitScore(rFit)
                if lScore != rScore { return lScore < rScore }
                return quantSortRank(filename: lhs.filename) < quantSortRank(filename: rhs.filename)
            }
        }
        return result
    }

    private static func matchesQuantPrefix(_ prefix: String, file: HFGGUFile) -> Bool {
        let quant = (file.quantLabel ?? file.filename).uppercased()
        return quant.contains(prefix)
    }

    private static func fitScore(_ fit: ModelFitLevel?) -> Int {
        switch fit {
        case .ideal: return 0
        case .workable: return 1
        case .notRecommended: return 2
        case nil: return 3
        }
    }
}
