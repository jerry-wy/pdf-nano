import AppKit

// The signed-out state replaces the chat's empty canvas, preserving the same tabs.
final class AgentAccountView: NSView {
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
    private let heading = NSTextField(labelWithString: "Your reading companion")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let primary = NSButton(title: "Sign in with ChatGPT", target: nil, action: nil)
    private let secondary = NSButton(title: "", target: nil, action: nil)
    override init(frame: NSRect) {
        super.init(frame: frame)
        heading.font = .systemFont(ofSize: 16, weight: .medium); heading.alignment = .center
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor; detail.alignment = .center
        primary.bezelStyle = .rounded; primary.controlSize = .large
        primary.target = self; primary.action = #selector(primaryAction)
        secondary.isBordered = false; secondary.font = .systemFont(ofSize: 11)
        secondary.contentTintColor = .secondaryLabelColor; secondary.target = self; secondary.action = #selector(secondaryAction)
        let row = NSStackView(views: [heading, detail, primary, secondary]); row.orientation = .vertical
        row.alignment = .centerX; row.spacing = 14
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            detail.widthAnchor.constraint(equalTo: row.widthAnchor),
            heading.widthAnchor.constraint(equalTo: row.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    func show(_ account: CodexAccount) {
        primary.isEnabled = true; secondary.isEnabled = true; secondary.isHidden = false
        switch account.state {
        case .checking:
            heading.stringValue = "Connecting…"; detail.stringValue = "Checking your Codex account."
            primary.title = "Connecting…"; primary.isEnabled = false; secondary.isHidden = true
        case .missing:
            heading.stringValue = "Connect your account"
            detail.stringValue = "Install Codex, then sign in with your own ChatGPT account."
            primary.title = "Get Codex"; secondary.title = "Check again"
        case .signedOut:
            heading.stringValue = "Your reading companion"
            detail.stringValue = "Sign in to ask questions about this PDF."
            primary.title = "Sign in with ChatGPT"; secondary.title = "Refresh connection"
        case .signingIn:
            heading.stringValue = "Continue in your browser"
            detail.stringValue = "This window will update when sign-in is complete."
            primary.title = "Open browser"; primary.isEnabled = account.loginURL != nil
            secondary.title = "Cancel"; secondary.isEnabled = account.loginURL != nil
        case .failed(let message):
            heading.stringValue = "Let’s reconnect"; detail.stringValue = message
            primary.title = "Retry"; secondary.title = "Codex setup"
        case .signedIn:
            break
        }
    }
    @objc private func primaryAction() { onPrimary() }
    @objc private func secondaryAction() { onSecondary() }
}
