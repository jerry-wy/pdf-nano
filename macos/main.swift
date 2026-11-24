import AppKit

if CommandLine.arguments.contains("--smoke-test") {
    setbuf(stdout, nil)
    do { try runSmokeTests(); exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
