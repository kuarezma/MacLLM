import Foundation

struct ReasoningContentSplitter {
    struct Split {
        var thought: String?
        var answer: String
        var thoughtSeconds: Int?
    }

    private static let thinkOpen = "<" + "think" + ">"
    private static let thinkClose = "</" + "think" + ">"

    static func split(_ raw: String) -> Split {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Split(thought: nil, answer: "") }

        for pair in [
            (thinkOpen, thinkClose),
            ("<reasoning>", "</reasoning>"),
            ("<thought>", "</thought>"),
        ] {
            if let result = extractTagged(trimmed, open: pair.0, close: pair.1) {
                return result
            }
        }
        return Split(thought: nil, answer: trimmed)
    }

    private static func extractTagged(_ text: String, open: String, close: String) -> Split? {
        guard let openRange = text.range(of: open, options: .caseInsensitive) else { return nil }
        let afterOpen = text[openRange.upperBound...]
        let thoughtBody: String
        let remainder: String
        if let closeRange = afterOpen.range(of: close, options: .caseInsensitive) {
            thoughtBody = String(afterOpen[..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            remainder = String(afterOpen[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            thoughtBody = String(afterOpen).trimmingCharacters(in: .whitespacesAndNewlines)
            remainder = ""
        }
        guard !thoughtBody.isEmpty else { return nil }
        return Split(
            thought: thoughtBody,
            answer: remainder,
            thoughtSeconds: estimateThoughtSeconds(thoughtBody)
        )
    }

    private static func estimateThoughtSeconds(_ thought: String) -> Int? {
        let words = thought.split { $0.isWhitespace }.count
        guard words > 8 else { return nil }
        return max(1, min(120, words / 12))
    }
}
