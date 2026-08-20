import Foundation
import Darwin

@main
struct AgentToolExecutorTests {
    static func main() {
        Task { @MainActor in
            testToolParsing()
            testWorkspaceContextAssembler()
            print("AgentToolExecutorTests: OK")
            Darwin.exit(0)
        }
        dispatchMain()
    }

    @MainActor
    private static func testToolParsing() {
        let sampleLLMOutput = """
        Projeyi inceledim. Şimdi dosyayı okuyalım:

        <tool_call>
        {"tool": "read_file", "arguments": {"path": "Sources/Main.swift", "start_line": "1", "end_line": "50"}}
        </tool_call>

        Ve ardından testleri çalıştıralım:
        <tool_call>
        {"tool": "run_terminal_command", "arguments": {"command": "swift test", "explanation": "Testleri koştur"}}
        </tool_call>
        """

        let calls = AgentToolExecutor.shared.parseToolCalls(from: sampleLLMOutput)
        assert(calls.count == 2, "2 araç çağrısı bulunmalı")
        assert(calls[0].tool == .readFile)
        assert(calls[0].arguments["path"] == "Sources/Main.swift")
        assert(calls[0].arguments["start_line"] == "1")

        assert(calls[1].tool == .runTerminalCommand)
        assert(calls[1].arguments["command"] == "swift test")
        assert(calls[1].arguments["explanation"] == "Testleri koştur")
    }

    private static func testWorkspaceContextAssembler() {
        let summary = WorkspaceContextAssembler.buildWorkspaceTreeSummary()
        assert(!summary.isEmpty)
    }
}
