import Foundation

enum DiffLineKind: Sendable, Hashable {
    case unchanged
    case addition
    case deletion
}

struct DiffLine: Identifiable, Sendable, Hashable {
    let id: String
    let kind: DiffLineKind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    init(
        id: String = UUID().uuidString,
        kind: DiffLineKind,
        text: String,
        oldLineNumber: Int?,
        newLineNumber: Int?
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

struct DiffResult: Sendable, Hashable {
    let lines: [DiffLine]
    let additionsCount: Int
    let deletionsCount: Int

    var summaryText: String {
        "+\(additionsCount) / -\(deletionsCount)"
    }
}

enum DiffEngine {
    static func computeDiff(original: String, proposed: String) -> DiffResult {
        let originalLines = original.components(separatedBy: "\n")
        let proposedLines = proposed.components(separatedBy: "\n")

        let n = originalLines.count
        let m = proposedLines.count

        if n == 0 && m == 0 {
            return DiffResult(lines: [], additionsCount: 0, deletionsCount: 0)
        }

        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if originalLines[i] == proposedLines[j] {
                    lcs[i + 1][j + 1] = lcs[i][j] + 1
                } else {
                    lcs[i + 1][j + 1] = max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var tempLines: [DiffLine] = []
        var additions = 0
        var deletions = 0

        var i = n
        var j = m

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && originalLines[i - 1] == proposedLines[j - 1] {
                tempLines.append(DiffLine(
                    kind: .unchanged,
                    text: originalLines[i - 1],
                    oldLineNumber: i,
                    newLineNumber: j
                ))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j]) {
                tempLines.append(DiffLine(
                    kind: .addition,
                    text: proposedLines[j - 1],
                    oldLineNumber: nil,
                    newLineNumber: j
                ))
                additions += 1
                j -= 1
            } else if i > 0 && (j == 0 || lcs[i][j - 1] < lcs[i - 1][j]) {
                tempLines.append(DiffLine(
                    kind: .deletion,
                    text: originalLines[i - 1],
                    oldLineNumber: i,
                    newLineNumber: nil
                ))
                deletions += 1
                i -= 1
            }
        }

        return DiffResult(lines: tempLines.reversed(), additionsCount: additions, deletionsCount: deletions)
    }
}
