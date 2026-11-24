import Foundation

@main struct CodexAccountTests {
    static func require(_ value: Bool, _ message: String) {
        if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func until(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        require(condition(), "Async operation finishes")
    }
    static func main() throws {
        if CommandLine.arguments.contains("--live-check") {
            let transport = CodexAccountTransport(timeout: 15)
            let account = CodexAccount(transport: transport)
            account.refresh()
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if case .failed(let message) = account.state {
                    transport.stop(); print("LIVE UNAVAILABLE: \(message)"); exit(2)
                }
                if account.state.isSignedIn && !account.models.isEmpty {
                    print("PASS: Live account metadata and model list; no login/logout or prompt submitted")
                    transport.stop(); return
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            transport.stop(); print("LIVE UNAVAILABLE: Account/models did not become available."); exit(2)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pdfnano-account-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("codex")
        try #"""
        #!/usr/bin/python3
        import sys, json
        logged_in = False
        initialized = False
        login_id = 0
        def send(value):
            # Split response writes to exercise buffered line framing.
            data = json.dumps(value) + '\n'
            sys.stdout.write(data[:9]); sys.stdout.flush()
            sys.stdout.write(data[9:]); sys.stdout.flush()
        for line in sys.stdin:
            msg = json.loads(line)
            method = msg['method']; ident = msg.get('id'); params = msg.get('params', {})
            if method == 'initialized':
                initialized = True
                continue
            if method != 'initialize' and not initialized:
                send({'id': ident, 'error': {'code': -1}})
                continue
            result = {}
            if method == 'account/read':
                result = {'account': {'type': 'chatgpt', 'email': 'reader@example.test'} if logged_in else None}
            elif method == 'account/login/start':
                login_id += 1
                result = {'type': 'chatgpt', 'loginId': str(login_id), 'authUrl': 'https://auth.openai.com/authorize?state=test'}
            elif method == 'account/login/cancel':
                send({'method': 'account/login/completed', 'params': {'loginId': str(login_id), 'success': False}})
                result = {'status': 'canceled'}
            elif method == 'test/complete':
                logged_in = True
                send({'method': 'account/login/completed', 'params': {'loginId': str(login_id), 'success': True}})
                send({'method': 'account/updated', 'params': {'authMode': 'chatgpt'}})
            elif method == 'test/stale':
                send({'method': 'account/login/completed', 'params': {'loginId': str(login_id - 1), 'success': True}})
            elif method == 'account/logout':
                logged_in = False
                send({'method': 'account/updated', 'params': {'authMode': None}})
            elif method == 'model/list':
                if params.get('cursor') == 'more':
                    result = {'data': [{'model': 'preferred', 'isDefault': True}, {'model': 'hidden', 'hidden': True}], 'nextCursor': None}
                else:
                    result = {'data': [{'model': 'another'}, {'model': 'another'}], 'nextCursor': 'more'}
            elif method == 'test/fail':
                send({'id': ident, 'error': {'message': 'secret-value-must-not-be-displayed'}})
                continue
            elif method == 'test/hang':
                continue
            send({'id': ident, 'result': result})
        """#.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        let transport = CodexAccountTransport(timeout: 2)
        let account = CodexAccount(transport: transport, executable: { fake })
        var notices = 0
        let observer = NotificationCenter.default.addObserver(forName: CodexAccount.changed, object: account, queue: .main) { _ in notices += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        var opened = 0
        account.openBrowser = { url in require(url.host == "auth.openai.com", "Login opens the official authorization host"); opened += 1 }
        account.refresh()
        until { account.state == .signedOut }
        require(notices >= 2, "Shared account observers receive state updates across windows")
        require(opened == 0, "Checking account never starts browser login")
        account.signIn()
        until { account.loginURL != nil }
        require(account.state == .signingIn && opened == 1, "Explicit sign-in waits for browser authorization")
        account.cancelLogin()
        until { account.state == .signedOut && !account.isChanging }
        require(account.loginURL == nil, "Cancel clears the transient authorization URL")
        account.signIn()
        until { account.loginURL != nil }
        var staleDone = false
        transport.request("test/stale") { _ in staleDone = true }
        until { staleDone }
        require(account.state == .signingIn, "A cancelled attempt cannot complete a later sign-in")
        transport.request("test/complete") { _ in }
        until { account.state.isSignedIn && account.models.count == 2 }
        require(account.state == .signedIn("reader@example.test"), "Successful login exposes account identity without tokens")
        require(account.models == ["preferred", "another"], "Fresh model pages prioritize the actual default, filter hidden entries and deduplicate")
        require(account.loginURL == nil, "Successful login clears transient authorization data")
        var errorText: String?
        transport.request("test/fail") { if case .failure(let error) = $0 { errorText = error.localizedDescription } }
        until { errorText != nil }
        require(!errorText!.contains("secret-value"), "Raw server errors cannot leak credentials into the UI")
        account.signOut()
        until { account.state == .signedOut && !account.isChanging }
        require(account.models.isEmpty, "Sign-out clears account-specific model choices")
        var timedOut = false
        transport.request("test/hang") { if case .failure = $0 { timedOut = true } }
        until { timedOut }
        if case .failed = account.state {} else { require(false, "Connection timeout is recoverable") }
        account.refresh()
        until { account.state == .signedOut }
        require(true, "Connection can restart after a timeout")
        transport.stop()
        let missing = CodexAccount(executable: { nil }); missing.refresh()
        require(missing.state == .missing, "A clean Mac gets install guidance instead of a broken composer")
        for url in ["http://auth.openai.com/a", "https://auth.openai.com.evil.test/a", "file:///tmp/a", "https://evil.test/a", "https://user:pass@auth.openai.com/a", "https://auth.openai.com:444/a"] {
            require(CodexAccount.browserURL(url) == nil, "Reject non-official authorization URL")
        }
    }
}
