import Foundation

/// Üretilen metni stop dizileri ve şablon token'larından arındırır; parçalı UTF-8 güvenli.
struct GenerationOutputFilter {
    private let stopSequences: [String]
    private let maxStopLength: Int

    private var raw = ""
    private var emittedCharacterCount = 0
    private var finished = false

    init(stopSequences: [String]) {
        let merged = stopSequences.filter { !$0.isEmpty }
        self.stopSequences = merged.sorted { $0.count > $1.count }
        self.maxStopLength = merged.map(\.count).max() ?? 0
    }

    /// Yeni parça ekler; arayüze gönderilecek güvenli metin parçasını döndürür (boş olabilir).
    mutating func push(_ chunk: String) -> String {
        guard !finished, !chunk.isEmpty else { return "" }

        raw += chunk

        if let stopRange = firstStopRange(in: raw) {
            raw = String(raw[..<stopRange.lowerBound])
            finished = true
        }

        return drainSafeDelta(holdBackIncompleteStop: !finished)
    }

    /// Akış bittiğinde kalan güvenli metni döndürür.
    mutating func finish() -> String {
        finished = true
        return drainSafeDelta(holdBackIncompleteStop: false)
    }

    // MARK: - Private

    private mutating func drainSafeDelta(holdBackIncompleteStop: Bool) -> String {
        var displayable = ControlTokenSanitizer.clean(raw)

        if holdBackIncompleteStop, maxStopLength > 0 {
            let hold = incompleteStopPrefixLength(in: displayable)
            if hold > 0, displayable.count > hold {
                displayable = String(displayable.dropLast(hold))
            }
        }

        guard displayable.count > emittedCharacterCount else { return "" }

        let start = displayable.index(displayable.startIndex, offsetBy: emittedCharacterCount)
        let delta = String(displayable[start...])
        emittedCharacterCount = displayable.count
        return delta
    }

    private func firstStopRange(in text: String) -> Range<String.Index>? {
        var earliest: Range<String.Index>?
        for stop in stopSequences {
            guard let range = text.range(of: stop) else { continue }
            if let current = earliest {
                if range.lowerBound < current.lowerBound { earliest = range }
            } else {
                earliest = range
            }
        }
        return earliest
    }

    /// "" parça parça gelirken erken yayınlamayı önler.
    private func incompleteStopPrefixLength(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var hold = 0
        for stop in stopSequences {
            let limit = min(stop.count - 1, text.count)
            guard limit > 0 else { continue }
            for length in 1...limit {
                if text.hasSuffix(String(stop.prefix(length))) {
                    hold = max(hold, length)
                }
            }
        }
        return min(hold, text.count)
    }
}

/// Tüm şablonlarda görülen kontrol token'larını temizler.
enum ControlTokenSanitizer {
    private static let literalMarkers: [String] = {
        let imEnd = "<|" + "im_end" + "|>"
        let imStart = "<|" + "im_start" + "|>"
        return [
            imEnd, imStart,
            "<|eot_id|>", "<|endoftext|>", "<|end|>",
            "<|start_header_id|>", "<|end_header_id|>",
            "[INST]", "[/INST]", "</s>",
        ]
    }()

    static func clean(_ text: String) -> String {
        var result = text
        for marker in literalMarkers where !marker.isEmpty {
            while let range = result.range(of: marker) {
                result.removeSubrange(range)
            }
        }
        // Kalan <|...|> kalıpları (ör. <|im_start|>user)
        if !result.isEmpty,
           let regex = try? NSRegularExpression(pattern: #"<\|[^>\n|]{1,48}\|>"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: ""
            )
        }
        result = stripTrailingPartialControlToken(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Yarım kalmış `<|im_start|` gibi kontrol token parçalarını kaldırır.
    private static func stripTrailingPartialControlToken(_ text: String) -> String {
        guard let lastOpen = text.lastIndex(of: "<") else { return text }
        let suffix = text[lastOpen...]
        guard suffix.hasPrefix("<|"), !suffix.hasSuffix("|>") else { return text }
        return String(text[..<lastOpen])
    }

    static func sanitizeForDisplay(_ text: String) -> String {
        clean(text)
    }
}
