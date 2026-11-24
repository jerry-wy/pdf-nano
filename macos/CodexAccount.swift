import Foundation
import Darwin

// A local stdio connection to the official Codex app-server. No tokens or raw
// protocol messages are logged or stored by PDF Nano.
final class CodexAccountTransport {
    typealias Reply = (Result<[String: Any], Error>) -> Void
    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: (() -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var pending: [Int: Reply] = [:]
    private var nextID = 0
    private var generation = UUID()
    private let timeout: TimeInterval
    init(timeout: TimeInterval = 30) { self.timeout = timeout }

    func start(executable: URL?, completion: @escaping Reply) {
        stop()
        guard let executable else { completion(.failure(AgentFailure.missing)); return }
        let task = Process(), stdin = Pipe(), stdout = Pipe()
        let token = generation
        task.executableURL = executable
        task.arguments = ["--no-daemon", "app-server", "--listen", "stdio://", "-c", "model_provider=\"openai\"",
                          "-c", "features.apps=false", "-c", "features.plugins=false"]
        task.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        task.environment = environment
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.disconnected(); return }
                self.receive(data)
            }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.disconnected()
            }
        }
        do {
            try task.run(); process = task
            request("initialize", params: ["clientInfo": ["name": "pdf_nano", "title": "PDF Nano", "version": "1.2.8"]]) { [weak self] result in
                if case .success = result { self?.send(["method": "initialized"]) }
                completion(result)
            }
        } catch {
            stop(); completion(.failure(AgentFailure.failed("Could not start Codex. Install or update Codex, then retry.")))
        }
    }
    func request(_ method: String, params: [String: Any] = [:], completion: @escaping Reply) {
        guard process?.isRunning == true else {
            completion(.failure(AgentFailure.failed("Codex is not connected. Retry the connection."))); return
        }
        nextID += 1; let id = nextID, token = generation
        pending[id] = completion
        send(["id": id, "method": method, "params": params])
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.generation == token, self.pending[id] != nil else { return }
            self.disconnected()
        }
    }
    private func send(_ value: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: value); data.append(10)
            try input?.write(contentsOf: data)
        } catch { disconnected() }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 4_000_000 else { disconnected(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if let method = object["method"] as? String {
                // This connection handles account/model metadata only, never tool requests.
                if let id = object["id"] {
                    send(["id": id, "error": ["code": -32601, "message": "Unsupported request"]])
                } else { onNotification?(method, object["params"] as? [String: Any] ?? [:]) }
            } else if let id = object["id"] as? Int, let completion = pending.removeValue(forKey: id) {
                if let result = object["result"] as? [String: Any] { completion(.success(result)) }
                else { completion(.failure(AgentFailure.failed("Codex could not complete this action. Update Codex or retry."))) }
            }
        }
    }
    private func disconnected() {
        stop(); onDisconnect?()
    }
    func stop() {
        generation = UUID()
        output?.readabilityHandler = nil
        try? input?.close(); try? output?.close()
        input = nil; output = nil; buffer.removeAll()
        let task = process; process = nil
        if let task, task.isRunning {
            task.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            }
        }
        let callbacks = Array(pending.values); pending.removeAll()
        callbacks.forEach { $0(.failure(AgentFailure.failed("Codex connection ended. Retry to reconnect."))) }
    }
    deinit {
        output?.readabilityHandler = nil
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
    }
}

enum CodexAccountState: Equatable {
    case checking, missing, signedOut, signingIn, signedIn(String), failed(String)
    var isSignedIn: Bool { if case .signedIn = self { return true }; return false }
}

final class CodexAccount {
    static let shared = CodexAccount()
    static let changed = Notification.Name("PDFNanoCodexAccountChanged")
    private(set) var state: CodexAccountState = .checking
    private(set) var models: [String] = []
    private(set) var loginURL: URL?
    private(set) var isChanging = false
    private var loginID: String?
    private var ready = false
    private var checking = false
    private var started = false
    private var loginGeneration = UUID()
    private var modelGeneration = UUID()
    private let transport: CodexAccountTransport
    private let executable: () -> URL?
    var openBrowser: (URL) -> Void = { _ in }
    init(transport: CodexAccountTransport = CodexAccountTransport(), executable: @escaping () -> URL? = CodexBridge.executable) {
        self.transport = transport; self.executable = executable
        transport.onNotification = { [weak self] method, params in self?.notification(method, params) }
        transport.onDisconnect = { [weak self] in
            guard let self else { return }
            self.ready = false; self.checking = false; self.isChanging = false
            self.clearLogin(); self.state = .failed("Could not connect to Codex. Update Codex or retry."); self.publish()
        }
    }
    private func publish() { NotificationCenter.default.post(name: Self.changed, object: self) }
    func refresh() {
        guard !checking, !isChanging else { return }
        started = true; checking = true
        if ready { readAccount(); return }
        guard let executable = executable() else { checking = false; state = .missing; publish(); return }
        state = .checking; publish()
        transport.start(executable: executable) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.ready = true; self.readAccount()
            case .failure: self.checking = false; self.state = .failed("Could not connect to Codex. Update Codex or retry."); self.publish()
            }
        }
    }
    func shutdown() { transport.stop(); ready = false; started = false; clearLogin() }
    func refreshIfStarted() { if started { refresh() } }
    private func readAccount() {
        transport.request("account/read", params: ["refreshToken": false]) { [weak self] result in
            guard let self else { return }
            self.checking = false
            switch result {
            case .success(let object):
                if let account = object["account"] as? [String: Any] {
                    let type = account["type"] as? String ?? ""
                    let label = type == "apiKey" ? "API key" : (account["email"] as? String ?? "ChatGPT")
                    self.state = .signedIn(label)
                    self.loadModels()
                } else { self.state = .signedOut; self.models = []; self.modelGeneration = UUID() }
            case .failure: self.state = .failed("Could not read your account. Retry the connection.")
            }
            self.publish()
        }
    }
    static func browserURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "auth.openai.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return url
    }
    func signIn() {
        guard ready, !isChanging, !checking else { refresh(); return }
        isChanging = true; state = .signingIn; publish()
        let token = UUID(); loginGeneration = token
        transport.request("account/login/start", params: ["type": "chatgpt"]) { [weak self] result in
            guard let self, self.loginGeneration == token else { return }
            guard case .success(let object) = result, let id = object["loginId"] as? String,
                  let address = object["authUrl"] as? String, let url = Self.browserURL(address) else {
                self.isChanging = false; self.state = .failed("Could not start browser sign-in. Retry or update Codex."); self.publish(); return
            }
            self.loginID = id; self.loginURL = url; self.publish(); self.openBrowser(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
                guard let self, self.loginGeneration == token, self.loginID == id else { return }
                self.cancelLogin()
            }
        }
    }
    private func clearLogin() { loginID = nil; loginURL = nil; loginGeneration = UUID() }
    func cancelLogin() {
        guard let id = loginID else { return }
        clearLogin()
        transport.request("account/login/cancel", params: ["loginId": id]) { [weak self] _ in
            guard let self else { return }
            self.isChanging = false; self.refresh()
        }
    }
    // Explicit user action; the UI explains that credentials are shared with Codex.
    func signOut() {
        guard ready, !isChanging, !checking else { return }
        isChanging = true; publish()
        transport.request("account/logout") { [weak self] result in
            guard let self else { return }
            self.isChanging = false
            switch result {
            case .success:
                self.models = []; self.modelGeneration = UUID(); self.state = .signedOut
            case .failure: self.state = .failed("Could not sign out. Retry the connection.")
            }
            self.publish()
        }
    }
    private func notification(_ method: String, _ params: [String: Any]) {
        if method == "account/login/completed", let id = params["loginId"] as? String, id == loginID {
            clearLogin(); isChanging = false
            if params["success"] as? Bool == true { refresh() }
            else { state = .failed("Sign-in was not completed. Try again."); publish() }
        } else if method == "account/updated", !isChanging { refresh() }
    }
    private func loadModels() {
        let token = UUID(); modelGeneration = token
        loadModelPage(cursor: nil, rows: [], seen: [], token: token)
    }
    private func loadModelPage(cursor: String?, rows: [[String: Any]], seen: Set<String>, token: UUID) {
        var params: [String: Any] = ["limit": 100, "includeHidden": false]
        if let cursor { params["cursor"] = cursor }
        transport.request("model/list", params: params) { [weak self] result in
            guard let self, self.modelGeneration == token, self.state.isSignedIn else { return }
            guard case .success(let result) = result else { return }
            let all = rows + (result["data"] as? [[String: Any]] ?? [])
            if let next = result["nextCursor"] as? String, !seen.contains(next), seen.count < 10 {
                self.loadModelPage(cursor: next, rows: all, seen: seen.union([next]), token: token); return
            }
            var ids = Set<String>()
            self.models = all.enumerated().sorted {
                let a = $0.element["isDefault"] as? Bool == true, b = $1.element["isDefault"] as? Bool == true
                return a != b ? a : $0.offset < $1.offset
            }.compactMap { _, row in
                guard row["hidden"] as? Bool != true, let id = row["model"] as? String, !id.isEmpty, ids.insert(id).inserted else { return nil }
                return id
            }
            self.publish()
        }
    }
}
