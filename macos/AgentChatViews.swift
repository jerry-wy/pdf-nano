import AppKit

final class AgentPromptEditor: NSTextView {
    var onSubmit: () -> Void = {}
    var onChange: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder(); if result { onFocus(true) }; return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder(); if result { onFocus(false) }; return result
    }
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onSubmit(); return
        }
        super.keyDown(with: event)
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true; onChange() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("Ask about this PDF…" as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
}

final class AgentComposerView: NSView {
    var focused = false { didSet { updateColors() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 16; layer?.borderWidth = 1
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = (focused ? NSColor.controlAccentColor.withAlphaComponent(0.45) : NSColor.separatorColor.withAlphaComponent(0.32)).cgColor
        }
    }
}

final class AgentMessageView: NSView {
    let isUser: Bool
    let text: String
    private let body = NSTextField(wrappingLabelWithString: "")
    private let caption = NSTextField(labelWithString: "Agent")
    override var isFlipped: Bool { true }
    init(text: String, isUser: Bool) {
        self.isUser = isUser; self.text = text
        super.init(frame: .zero)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = 7
        body.attributedStringValue = NSAttributedString(string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
        body.isSelectable = true; body.maximumNumberOfLines = 0
        caption.font = .systemFont(ofSize: 10, weight: .semibold); caption.textColor = .secondaryLabelColor
        caption.isHidden = isUser
        addSubview(body); addSubview(caption)
        setAccessibilityLabel(isUser ? "Your message" : "Agent response")
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    private func bubbleWidth(_ width: CGFloat) -> CGFloat {
        // Short messages fit their text; longer messages wrap within 85% of
        // the conversation width. Leave room for the text field's own inset.
        min(width, max(28, min(ceil(body.attributedStringValue.size().width) + 28, floor(width * 0.85))))
    }
    private func textWidth(_ width: CGFloat) -> CGFloat {
        max(1, (isUser ? bubbleWidth(width) : width) - 24)
    }
    func height(for width: CGFloat) -> CGFloat {
        let rect = body.attributedStringValue.boundingRect(with: NSSize(width: textWidth(width), height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height) + (isUser ? 26 : 46)
    }
    override func layout() {
        super.layout()
        let inset: CGFloat = isUser ? bounds.width - bubbleWidth(bounds.width) + 12 : 12
        body.preferredMaxLayoutWidth = textWidth(bounds.width)
        body.frame = NSRect(x: inset, y: isUser ? 12 : 30, width: textWidth(bounds.width), height: max(1, bounds.height - (isUser ? 24 : 42)))
        caption.frame = NSRect(x: 12, y: 9, width: max(1, bounds.width - 24), height: 14)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isUser {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
            let width = bubbleWidth(bounds.width)
            NSBezierPath(roundedRect: NSRect(x: bounds.maxX - width, y: 0, width: width, height: bounds.height), xRadius: 14, yRadius: 14).fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class AgentConversationView: NSView {
    private var messages: [AgentMessageView] = []
    private var mathView: AgentMathTranscript?
    private var mathLoadingCover: NSView?
    private var showingMath = false
    private var mathFailed = false
    private var scrollAfterRender = false
    override var isFlipped: Bool { true }
    var isEmpty: Bool { messages.isEmpty }
    func append(_ text: String, isUser: Bool) {
        let message = AgentMessageView(text: text, isUser: isUser)
        message.isHidden = showingMath
        messages.append(message); addSubview(message)
        if !isUser && !mathFailed && mathView == nil &&
            (text.contains("$") || text.contains("\\(") || text.contains("\\[") || text.contains("\\begin{") || text.contains("```latex") || text.contains("```math") || text.contains("```tex")) {
            enableMath()
        }
        updateMath(); reflow(width: bounds.width)
    }
    private func enableMath() {
        let view = AgentMathTranscript(frame: bounds)
        // Keep WebKit visible while it loads. An opaque native cover preserves
        // the plain transcript until the first typeset layout is ready.
        addSubview(view, positioned: .below, relativeTo: subviews.first); mathView = view
        let cover = NSView(frame: bounds); cover.wantsLayer = true
        cover.autoresizingMask = [.width, .height]
        addSubview(cover, positioned: .above, relativeTo: view); mathLoadingCover = cover
        updateLoadingCover()
        view.onHeight = { [weak self] _ in
            guard let self else { return }
            let follow = self.scrollAfterRender || self.visibleRect.maxY >= self.bounds.maxY - 40
            self.showingMath = true; self.mathView?.isHidden = false; self.mathLoadingCover?.isHidden = true
            self.messages.forEach { $0.isHidden = true }
            self.reflow(width: self.bounds.width)
            if follow { self.scrollToVisible(NSRect(x: 0, y: max(0, self.bounds.height - 1), width: 1, height: 1)) }
            self.scrollAfterRender = false
        }
        view.onFailure = { [weak self] in
            guard let self else { return }
            self.mathFailed = true; self.showingMath = false; self.mathView?.isHidden = true; self.mathLoadingCover?.isHidden = true
            self.messages.forEach { $0.isHidden = false }; self.reflow(width: self.bounds.width)
        }
    }
    private func updateLoadingCover() {
        effectiveAppearance.performAsCurrentDrawingAppearance { mathLoadingCover?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateLoadingCover() }
    private func updateMath() {
        mathView?.setMessages(messages.map { ["text": $0.text, "isUser": $0.isUser] })
    }
    func clear() {
        messages.forEach { $0.removeFromSuperview() }; messages = []
        mathLoadingCover?.removeFromSuperview(); mathLoadingCover = nil
        mathView?.removeFromSuperview(); mathView = nil; showingMath = false; mathFailed = false; scrollAfterRender = false
        reflow(width: bounds.width)
    }
    func reflow(width: CGFloat) {
        var y: CGFloat = 8
        if showingMath, let mathView { y = mathView.contentHeight }
        else {
            for message in messages {
                let height = message.height(for: max(60, width - 16))
                message.frame = NSRect(x: 8, y: y, width: max(60, width - 16), height: height)
                message.needsLayout = true; y += height + 16
            }
        }
        setFrameSize(NSSize(width: max(1, width), height: y))
        mathView?.frame = NSRect(x: 0, y: 0, width: max(1, width), height: max(24, y))
    }
    func scrollToLatest() {
        scrollAfterRender = mathView != nil
        scrollToVisible(NSRect(x: 0, y: max(0, bounds.height - 1), width: 1, height: 1))
    }
}
