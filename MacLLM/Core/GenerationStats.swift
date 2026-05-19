import Foundation

struct GenerationStats: Equatable, Hashable, Codable {
    let outputTokens: Int
    let tokensPerSecond: Double
    let durationSeconds: Double

    var formattedRate: String {
        guard tokensPerSecond > 0 else { return "—" }
        return String(format: "%.0f token/sn", tokensPerSecond)
    }

    var formattedSummary: String {
        guard outputTokens > 0 else { return "" }
        if tokensPerSecond > 0 {
            return "\(formattedRate) (\(outputTokens) token)"
        }
        return "\(outputTokens) token"
    }
}
