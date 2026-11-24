import Foundation

@main struct AgentBridgeTests {
    static func require(_ condition: Bool, _ message: String) {
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func request(_ bridge: CodexBridge, prompt: String = "literal $(touch /tmp/should-not-exist) `id` 日本語", executable: URL?, timeout: TimeInterval = 3, cancel: Bool = false) -> Result<String, Error> {
        var result: Result<String, Error>?
        bridge.ask(prompt: prompt, executable: executable, timeout: timeout) { result = $0 }
        if cancel { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { bridge.cancel() } }
        let deadline = Date().addingTimeInterval(140)
        while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        require(result != nil, "Request completes")
        return result!
    }
    static func main() throws {
        let context = ReadingContext(pages: [(3, "The experiment used 24 samples."), (4, String(repeating: "文", count: 13000))])
        let prompt = try context.prompt(question: "How many?", history: [AgentTurn(question: "Earlier?", answer: "24", pages: "3")])
        require(context.label == "3, 4" && context.hasText, "Context retains PDF page numbers")
        require(prompt.contains("\"truncated\":true") && prompt.contains("Earlier?"), "Prompt bounds long pages and includes conversation")
        require(!ReadingContext(pages: [(1, " \n")]).hasText, "Scanned pages require OCR")
        if CommandLine.arguments.contains("--live") {
            let source = ReadingContext(pages: [(7, "In this experiment, researchers tested exactly 24 samples.")])
            let result = request(CodexBridge(), prompt: try source.prompt(question: "How many samples were tested? Cite the page.", history: []), executable: CodexBridge.executable(), timeout: 45)
            switch result {
            case .success(let answer): print("LIVE ANSWER: \(answer)"); require(answer.contains("24") && answer.contains("7"), "Live Codex answers from page context")
            case .failure(let error): fputs("LIVE UNAVAILABLE: \(error.localizedDescription)\n", stderr); exit(2)
            }
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pdfnano-bridge-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("codex")
        func script(_ body: String) throws {
            try ("#!/bin/sh\n" + body).write(to: fake, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        }
        try script("while [ \"$#\" -gt 0 ]; do\n if [ \"$1\" = '--output-last-message' ]; then shift; result_path=\"$1\"; fi\n shift\ndone\ncat > \"$result_path\"\n")
        let bridge = CodexBridge()
        let result = request(bridge, executable: fake)
        require((try? result.get()) == "literal $(touch /tmp/should-not-exist) `id` 日本語", "Prompts use stdin without shell expansion and preserve Unicode")
        try script("while [ \"$#\" -gt 0 ]; do\n case \"$1\" in\n --model) shift; chosen=\"$1\" ;;\n --output-schema) shift; test -f \"$1\" || exit 9 ;;\n --output-last-message) shift; result_path=\"$1\" ;;\n esac\n shift\ndone\nprintf '%s' \"$chosen\" > \"$result_path\"\n")
        var modelResult: Result<String, Error>?
        bridge.ask(prompt: "hello", model: "custom-model", outputSchema: ["type": "object"], executable: fake) { modelResult = $0 }
        while modelResult == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        require((try? modelResult?.get()) == "custom-model", "CLI receives selected model and an existing response schema")
        try script("echo 'authentication required 401' >&2\nexit 1\n")
        let auth = request(bridge, executable: fake)
        if case .failure(let error) = auth { require(error.localizedDescription.contains("codex login"), "Login failure is actionable") }
        else { require(false, "Expected authentication failure") }
        try script("exec /bin/sleep 20\n")
        let timed = request(bridge, executable: fake, timeout: 0.1)
        if case .failure(let error) = timed { require(error.localizedDescription.contains("too long"), "Timeout stops child process") }
        else { require(false, "Expected timeout") }
        let stopped = request(bridge, executable: fake, cancel: true)
        if case .failure(let error) = stopped { require(error.localizedDescription.contains("Stopped"), "Cancel stops child and permits retry") }
        else { require(false, "Expected cancellation") }
        let missing = request(bridge, executable: nil)
        if case .failure(let error) = missing { require(error.localizedDescription.contains("not found"), "Missing Codex has setup guidance") }
        else { require(false, "Expected missing executable") }
    }
}
