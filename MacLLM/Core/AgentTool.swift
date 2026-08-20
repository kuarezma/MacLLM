import Foundation

// MARK: - Agent Tool Definitions

enum AgentToolType: String, Codable, CaseIterable, Sendable {
    case readFile = "read_file"
    case writeFile = "write_file"
    case patchFile = "patch_file"
    case listDirectory = "list_directory"
    case searchCode = "search_code"
    case runTerminalCommand = "run_terminal_command"

    var displayName: String {
        switch self {
        case .readFile: return "Dosya Oku"
        case .writeFile: return "Dosya Yaz"
        case .patchFile: return "Kodu Güncelle (Diff)"
        case .listDirectory: return "Dizin Listele"
        case .searchCode: return "Kod Ara"
        case .runTerminalCommand: return "Terminal Komutu"
        }
    }

    var systemIcon: String {
        switch self {
        case .readFile: return "doc.text"
        case .writeFile: return "doc.badge.plus"
        case .patchFile: return "wand.and.stars"
        case .listDirectory: return "folder"
        case .searchCode: return "magnifyingglass"
        case .runTerminalCommand: return "terminal"
        }
    }

    var isReadOnly: Bool {
        switch self {
        case .readFile, .listDirectory, .searchCode:
            return true
        case .writeFile, .patchFile, .runTerminalCommand:
            return false
        }
    }
}

// MARK: - Tool Call Representation

struct AgentToolCall: Identifiable, Hashable, Sendable {
    let id: String
    let tool: AgentToolType
    let arguments: [String: String]
    let rawText: String

    init(
        id: String = UUID().uuidString,
        tool: AgentToolType,
        arguments: [String: String],
        rawText: String = ""
    ) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
        self.rawText = rawText
    }
}

// MARK: - Tool Result Representation

struct AgentToolResult: Identifiable, Hashable, Sendable {
    let id: String
    let callId: String
    let tool: AgentToolType
    let success: Bool
    let output: String
    let errorMessage: String?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        callId: String,
        tool: AgentToolType,
        success: Bool,
        output: String,
        errorMessage: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.callId = callId
        self.tool = tool
        self.success = success
        self.output = output
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

// MARK: - Pending Actions (Requiring User Review & Approval)

struct PendingCodePatch: Identifiable, Hashable, Sendable {
    let id: UUID
    let toolCallId: String
    let relativePath: String
    let fullPath: String
    let searchBlock: String
    let replaceBlock: String
    let explanation: String
    let originalFileContent: String
    let proposedFileContent: String
    var isApplied: Bool
    var isRejected: Bool

    init(
        id: UUID = UUID(),
        toolCallId: String,
        relativePath: String,
        fullPath: String,
        searchBlock: String,
        replaceBlock: String,
        explanation: String,
        originalFileContent: String,
        proposedFileContent: String,
        isApplied: Bool = false,
        isRejected: Bool = false
    ) {
        self.id = id
        self.toolCallId = toolCallId
        self.relativePath = relativePath
        self.fullPath = fullPath
        self.searchBlock = searchBlock
        self.replaceBlock = replaceBlock
        self.explanation = explanation
        self.originalFileContent = originalFileContent
        self.proposedFileContent = proposedFileContent
        self.isApplied = isApplied
        self.isRejected = isRejected
    }
}

struct PendingTerminalCommand: Identifiable, Hashable, Sendable {
    let id: UUID
    let toolCallId: String
    let command: String
    let workingDirectory: String
    let explanation: String
    var isExecuted: Bool
    var output: String?
    var exitCode: Int32?

    init(
        id: UUID = UUID(),
        toolCallId: String,
        command: String,
        workingDirectory: String,
        explanation: String,
        isExecuted: Bool = false,
        output: String? = nil,
        exitCode: Int32? = nil
    ) {
        self.id = id
        self.toolCallId = toolCallId
        self.command = command
        self.workingDirectory = workingDirectory
        self.explanation = explanation
        self.isExecuted = isExecuted
        self.output = output
        self.exitCode = exitCode
    }
}

// MARK: - Tool System Prompt Instructions

enum AgentToolPrompt {
    static func systemInstructions(workspacePath: String, workspaceRules: String? = nil) -> String {
        var prompt = """
        Sen bu projenin yerel kodlama ve geliştirme asistanısın.
        Çalışma dizini: `\(workspacePath)`
        
        Kullanıcının isteklerini yerine getirmek için aşağıdaki yerel araçları kullanabilirsin.
        Bir araç çağırmak istediğinde, çıktına tam olarak şu formatta bir `<tool_call>` bloğu ekle:

        <tool_call>
        {"tool": "read_file", "arguments": {"path": "Klasor/Dosya.swift", "start_line": "1", "end_line": "100"}}
        </tool_call>

        <tool_call>
        {"tool": "search_code", "arguments": {"query": "arananMetin", "extension": "swift"}}
        </tool_call>

        <tool_call>
        {"tool": "list_directory", "arguments": {"path": "", "max_depth": "2"}}
        </tool_call>

        <tool_call>
        {"tool": "patch_file", "arguments": {"path": "Klasor/Dosya.swift", "search": "eski_kod_blogu", "replace": "yeni_kod_blogu", "explanation": "Değişiklik açıklaması"}}
        </tool_call>

        <tool_call>
        {"tool": "write_file", "arguments": {"path": "Klasor/YeniDosya.swift", "content": "tum_dosya_icerigi"}}
        </tool_call>

        <tool_call>
        {"tool": "run_terminal_command", "arguments": {"command": "swift test", "explanation": "Testleri çalıştırma"}}
        </tool_call>

        Kurallar:
        1. Kod değiştirmeden önce ilgili dosyayı `read_file` ile oku veya `search_code` ile doğrula.
        2. `patch_file` yaparken `search` bloğu orijinal dosyadaki satırlarla birebir aynı karakter ve boşluklara sahip olmalıdır.
        3. Dosya yollarını her zaman çalışma dizinine göre göreceli (relative path) ver.
        """

        if let rules = workspaceRules?.trimmingCharacters(in: .whitespacesAndNewlines), !rules.isEmpty {
            prompt += "\n\nProje Özel Kuralları:\n\(rules)"
        }

        return prompt
    }
}
