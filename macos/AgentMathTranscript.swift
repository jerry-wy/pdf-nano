import AppKit
import WebKit

private final class ReaderMathWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX), let scroll = enclosingScrollView {
            scroll.scrollWheel(with: event)
        } else { super.scrollWheel(with: event) }
    }
}

private final class ReaderMathMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: AgentMathTranscript?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

// One small offline WebKit view for the transcript, only created when a reply
// contains math. PDF rendering and the rest of the reader remain native.
final class AgentMathTranscript: NSView, WKNavigationDelegate {
    var onHeight: ((CGFloat) -> Void)?
    var onFailure: (() -> Void)?
    private var web: ReaderMathWebView?
    private var handler = ReaderMathMessageHandler()
    private var payload: [[String: Any]] = []
    private var revision = 0
    private var ready = false
    private var failed = false
    private var flushQueued = false
    private(set) var contentHeight: CGFloat = 24

    override init(frame: NSRect) {
        super.init(frame: frame)
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("AgentRenderer"),
              let assets = try? AgentRendererAssets(directory: directory) else {
            DispatchQueue.main.async { [weak self] in self?.fail() }; return
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: assets.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        handler.owner = self
        configuration.userContentController.add(handler, name: "readerHeight")
        let view = ReaderMathWebView(frame: bounds, configuration: configuration)
        view.autoresizingMask = [.width, .height]; view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        addSubview(view); web = view
        view.loadHTMLString(assets.html, baseURL: nil)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    func setMessages(_ messages: [[String: Any]]) { payload = messages; revision += 1; queueFlush() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); revision += 1; queueFlush()
    }
    private func theme() -> [String: Any] {
        var colors: [String: Any] = [:]
        effectiveAppearance.performAsCurrentDrawingAppearance {
            func css(_ color: NSColor) -> String {
                let c = color.usingColorSpace(.sRGB) ?? .black
                return "rgba(\(Int(c.redComponent * 255)),\(Int(c.greenComponent * 255)),\(Int(c.blueComponent * 255)),\(c.alphaComponent))"
            }
            colors = ["ink": css(.labelColor), "muted": css(.secondaryLabelColor),
                      "bubble": css(NSColor.labelColor.withAlphaComponent(0.055)),
                      "dark": effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua]
        }
        return colors
    }
    private func queueFlush() {
        guard ready, !failed, !flushQueued else { return }
        flushQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.failed else { return }
            self.flushQueued = false
            self.web?.callAsyncJavaScript("return window.readerRender(items, theme, revision);",
                arguments: ["items": self.payload, "theme": self.theme(), "revision": self.revision], in: nil, in: .page) { [weak self] result in
                switch result {
                case .success(let value):
                    if let metrics = value as? [String: Any] { self?.receiveMetrics(metrics) }
                    else { self?.fail() }
                case .failure: self?.fail()
                }
            }
        }
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let object = message.body as? [String: Any] else { return }
        receiveMetrics(object)
    }
    private func receiveMetrics(_ object: [String: Any]) {
        guard !failed, object["revision"] as? Int == revision, object["count"] as? Int == payload.count,
              let value = object["height"] as? Double, value.isFinite, value > 0, value <= 4_000_000 else { return }
        contentHeight = CGFloat(value); onHeight?(contentHeight)
    }
    private func fail() {
        guard !failed else { return }; failed = true
        web?.stopLoading(); onFailure?()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; queueFlush() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Model replies cannot navigate, fetch remote pages, or open windows.
        let allowed = navigationAction.navigationType == .other && navigationAction.request.url?.absoluteString == "about:blank" && navigationAction.targetFrame?.isMainFrame != false
        decisionHandler(allowed ? .allow : .cancel)
    }
    deinit { web?.configuration.userContentController.removeScriptMessageHandler(forName: "readerHeight") }
}
