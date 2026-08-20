import Foundation
import Combine
import OSLog

final class AgentToolExecutor: ObservableObject {
    static let shared = AgentToolExecutor()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacLLM", category: "ToolExecutor")

    @Published var pendingPatches: [PendingCodePatch] = []
    @Published var pendingCommands: [PendingTerminalCommand] = []
    @Published var lastToolResults: [AgentToolResult] = []

    private init() {}

    // MARK: - Tool Call Parsing

    func parseToolCalls(from text: String) -> [AgentToolCall] {
        var calls: [AgentToolCall] = []

        let pattern = #"<tool_call>\s*([\s\S]*?)\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let jsonString = nsString.substring(with: match.range(at: 1))
            let rawBlock = nsString.substring(with: match.range(at: 0))

            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let toolName = json["tool"] as? String,
               let toolType = AgentToolType(rawValue: toolName) {
                
                var stringArgs: [String: String] = [:]
                if let rawArgs = json["arguments"] as? [String: Any] {
                    for (k, v) in rawArgs {
                        stringArgs[k] = "\(v)"
                    }
                }

                calls.append(AgentToolCall(
                    tool: toolType,
                    arguments: stringArgs,
                    rawText: rawBlock
                ))
            }
        }

        return calls
    }

    // MARK: - Safe Automatic Execution (Read, Search, List)

    @discardableResult
    func executeSafeToolCall(_ call: AgentToolCall) -> AgentToolResult {
        switch call.tool {
        case .readFile:
            let path = call.arguments["path"] ?? ""
            let startLine = Int(call.arguments["start_line"] ?? "")
            let endLine = Int(call.arguments["end_line"] ?? "")

            do {
                let (content, totalLines) = try ProjectWorkspaceService.shared.readFile(
                    relativePath: path,
                    startLine: startLine,
                    endLine: endLine
                )
                let output = "Dosya: `\(path)` (Toplam \(totalLines) satır)\n```\n\(content)\n```"
                let toolResult = AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
                lastToolResults.append(toolResult)
                return toolResult
            } catch {
                let errResult = AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", errorMessage: error.localizedDescription)
                lastToolResults.append(errResult)
                return errResult
            }

        case .listDirectory:
            let depth = Int(call.arguments["max_depth"] ?? "2") ?? 2
            let _ = ProjectWorkspaceService.shared.loadDirectoryTree(maxDepth: depth)
            let files = ProjectWorkspaceService.shared.listAllFiles(maxCount: 200)
            let output = "Çalışma Dizinindeki Dosyalar (Dizin Derinliği: \(depth), Toplam: \(files.count) dosya):\n" + files.map { "- \($0)" }.joined(separator: "\n")
            let toolResult = AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
            lastToolResults.append(toolResult)
            return toolResult

        case .searchCode:
            let query = call.arguments["query"] ?? ""
            let ext = call.arguments["extension"]
            let results = CodeSearchService.search(query: query, extensionFilter: ext, maxResults: 20)
            var output = "«\(query)» için \(results.count) sonuç bulundu:\n"
            for res in results {
                output += "• `\(res.relativePath):\(res.lineNumber)`: \(res.lineContent)\n"
            }
            let toolResult = AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
            lastToolResults.append(toolResult)
            return toolResult

        case .writeFile, .patchFile, .runTerminalCommand:
            let output = "Bu eylem kullanıcı onayı gerektirmektedir."
            let res = AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
            lastToolResults.append(res)
            return res
        }
    }

    // MARK: - Staged Action Creation (Patches & Commands)

    func stageModifications(from calls: [AgentToolCall]) {
        for call in calls {
            switch call.tool {
            case .patchFile:
                let path = call.arguments["path"] ?? ""
                let search = call.arguments["search"] ?? ""
                let replace = call.arguments["replace"] ?? ""
                let exp = call.arguments["explanation"] ?? "Kod güncellemesi"

                if let (original, proposed) = try? ProjectWorkspaceService.shared.preparePatch(
                    relativePath: path,
                    searchBlock: search,
                    replaceBlock: replace
                ), let fullPath = ProjectWorkspaceService.shared.resolveFileURL(relativePath: path)?.path {
                    let patch = PendingCodePatch(
                        toolCallId: call.id,
                        relativePath: path,
                        fullPath: fullPath,
                        searchBlock: search,
                        replaceBlock: replace,
                        explanation: exp,
                        originalFileContent: original,
                        proposedFileContent: proposed
                    )
                    DispatchQueue.main.async {
                        self.pendingPatches.append(patch)
                    }
                }

            case .writeFile:
                let path = call.arguments["path"] ?? ""
                let content = call.arguments["content"] ?? ""
                let exp = call.arguments["explanation"] ?? "Yeni dosya oluşturma / üzerine yazma"

                let orig = (try? ProjectWorkspaceService.shared.readFile(relativePath: path).content) ?? ""
                if let fullPath = ProjectWorkspaceService.shared.resolveFileURL(relativePath: path)?.path {
                    let patch = PendingCodePatch(
                        toolCallId: call.id,
                        relativePath: path,
                        fullPath: fullPath,
                        searchBlock: "",
                        replaceBlock: content,
                        explanation: exp,
                        originalFileContent: orig,
                        proposedFileContent: content
                    )
                    DispatchQueue.main.async {
                        self.pendingPatches.append(patch)
                    }
                }

            case .runTerminalCommand:
                let command = call.arguments["command"] ?? ""
                let exp = call.arguments["explanation"] ?? "Terminal komutu çalıştırma"
                let workDir = ProjectWorkspaceService.shared.activeWorkspacePath ?? FileManager.default.currentDirectoryPath

                let pending = PendingTerminalCommand(
                    toolCallId: call.id,
                    command: command,
                    workingDirectory: workDir,
                    explanation: exp
                )
                DispatchQueue.main.async {
                    self.pendingCommands.append(pending)
                }

            case .readFile, .listDirectory, .searchCode:
                break
            }
        }
    }

    // MARK: - User Approval Actions

    func applyPatch(_ patch: PendingCodePatch) {
        do {
            try ProjectWorkspaceService.shared.applyPatch(
                relativePath: patch.relativePath,
                proposedContent: patch.proposedFileContent
            )
            if let idx = pendingPatches.firstIndex(where: { $0.id == patch.id }) {
                pendingPatches[idx].isApplied = true
            }
            logger.info("Yama uygulandı: \(patch.relativePath)")
        } catch {
            logger.error("Yama uygulanamadı: \(error.localizedDescription)")
        }
    }

    func rejectPatch(_ patch: PendingCodePatch) {
        if let idx = pendingPatches.firstIndex(where: { $0.id == patch.id }) {
            pendingPatches[idx].isRejected = true
        }
    }

    func executeTerminalCommand(_ pending: PendingTerminalCommand, completion: @escaping (String, Int32) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", pending.command]
            process.currentDirectoryURL = URL(fileURLWithPath: pending.workingDirectory)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let exitCode = process.terminationStatus

                DispatchQueue.main.async {
                    if let idx = self.pendingCommands.firstIndex(where: { $0.id == pending.id }) {
                        self.pendingCommands[idx].isExecuted = true
                        self.pendingCommands[idx].output = output
                        self.pendingCommands[idx].exitCode = exitCode
                    }
                    completion(output, exitCode)
                }
            } catch {
                DispatchQueue.main.async {
                    if let idx = self.pendingCommands.firstIndex(where: { $0.id == pending.id }) {
                        self.pendingCommands[idx].isExecuted = true
                        self.pendingCommands[idx].output = "Komut çalıştırılamadı: \(error.localizedDescription)"
                        self.pendingCommands[idx].exitCode = 1
                    }
                    completion(error.localizedDescription, 1)
                }
            }
        }
    }
}
