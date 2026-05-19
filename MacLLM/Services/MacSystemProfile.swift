import Foundation

/// Yüklü Mac'in donanım özeti — model önerileri ve varsayılan çıkarım ayarları için.
struct MacSystemProfile: Equatable, Sendable {
    let chipName: String
    let modelIdentifier: String
    let physicalMemoryBytes: UInt64
    let processorCount: Int
    let isAppleSilicon: Bool

    var physicalMemoryGB: Int {
        max(1, Int(physicalMemoryBytes / 1_073_741_824))
    }

    var performanceTier: PerformanceTier {
        switch physicalMemoryGB {
        case ..<10: return .low
        case 10..<18: return .medium
        case 18..<26: return .high
        default: return .ultra
        }
    }

    var recommendedThreadCount: Int32 {
        Int32(max(1, min(12, processorCount - 2)))
    }

    var displaySummary: String {
        "\(chipName) · \(physicalMemoryGB) GB RAM · \(performanceTier.label)"
    }

    static func current() -> MacSystemProfile {
        let memory = ProcessInfo.processInfo.physicalMemory
        let cores = ProcessInfo.processInfo.processorCount
        let brand = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let modelId = sysctlString("hw.model") ?? "Mac"
        let isArm = sysctlInt("hw.optional.arm64") == 1

        let chip = normalizeChipName(brand)
        return MacSystemProfile(
            chipName: chip,
            modelIdentifier: modelId,
            physicalMemoryBytes: memory,
            processorCount: cores,
            isAppleSilicon: isArm
        )
    }

    private static func normalizeChipName(_ brand: String) -> String {
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Apple Silicon" }
        if trimmed.lowercased().hasPrefix("apple ") { return trimmed }
        if trimmed.contains("Apple") { return trimmed }
        return trimmed
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }
}
