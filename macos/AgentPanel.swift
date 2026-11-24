import AppKit
import PDFKit

final class AgentPanel: NSView {
    weak var pdfView: PDFView?
    var onToggle: () -> Void = {}
    var documentContext: () -> (id: String, title: String) = { ("session", "PDF") }
    private let historyTabs = SidebarTabs(labels: ["Chat", "History"])
    private let historyView = ChatHistoryView()
    private let historyStore = ChatHistoryStore.shared
    private let composer = AgentComposerView()
    private var currentThread: ChatThread?
    private var documentID = ""
    private var documentTitle = "PDF"
    private var saveError: String?
    private let model = ModelPicker()
    private var availableModels = CodexModels.available()
    private let account = CodexAccount.shared
    private let accountView = AgentAccountView()
    private let accountButton = ReaderActionButton()
    private var accountObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var defaultModelID: String? { availableModels.first }
    private var defaultModelLabel: String { defaultModelID.map { "\($0) · Default" } ?? "Default · unavailable" }
    private var reading: ReadingAgent?
    private let transcript = AgentConversationView()
    private let chatScroll = NSScrollView()
    private let promptScroll = NSScrollView()
    private let welcome = NSTextField(labelWithString: "Ask about this PDF")
    private var promptHeight: NSLayoutConstraint?
    private let question = AgentPromptEditor()
    private let send = NSButton(title: "Send", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Ask about your reading.")
    private let bridge = CodexBridge()
    private var history: [AgentTurn] = []
    private var busy = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSButton(title: "Agent", target: self, action: #selector(togglePanel))
        title.isBordered = false; title.toolTip = "Hide Agent"
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let clear = NSButton(image: NanoIcons.symbol("square.and.pencil", label: "New chat") ?? NSImage(), target: self, action: #selector(newChat))
        clear.isBordered = false; clear.contentTintColor = .secondaryLabelColor; clear.toolTip = "New chat"
        accountButton.font = .systemFont(ofSize: 11, weight: .medium)
        accountButton.target = self; accountButton.action = #selector(showAccount)
        let header = NSStackView(views: [title, NSView(), accountButton, clear]); header.spacing = 8; header.alignment = .centerY
        account.openBrowser = { NSWorkspace.shared.open($0) }
        accountView.onPrimary = { [weak self] in self?.accountPrimary() }
        accountView.onSecondary = { [weak self] in self?.accountSecondary() }
        accountObserver = NotificationCenter.default.addObserver(forName: CodexAccount.changed, object: account, queue: .main) { [weak self] _ in self?.accountChanged() }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.isHiddenOrHasHiddenAncestor else { return }
            self.account.refreshIfStarted()
        }
        historyTabs.selectedIndex = 0
        historyTabs.onChange = { [weak self] _ in self?.changeHistoryTab() }
        historyView.onOpen = { [weak self] thread in self?.openThread(thread) }
        historyView.onDelete = { [weak self] id in self?.deleteThread(id) }
        model.addOptions([defaultModelLabel] + availableModels)
        let savedModel = UserDefaults.standard.string(forKey: "PDFNanoAgentModel") ?? "Default"
        model.selectedValue = savedModel == "Default" ? defaultModelLabel : savedModel
        model.controlSize = .small; model.font = .systemFont(ofSize: 11, weight: .medium)
        model.isBordered = false
        model.setAccessibilityLabel("Codex model")
        model.toolTip = defaultModelID.map { "Default: \($0). Choose another model or enter an ID." } ?? "Default could not be resolved. Enter a model ID or run Codex to refresh its model list."
        model.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chatScroll.hasVerticalScroller = true; chatScroll.autohidesScrollers = true
        chatScroll.drawsBackground = false; chatScroll.contentView.drawsBackground = false
        chatScroll.documentView = transcript
        question.font = .systemFont(ofSize: 13); question.isRichText = false
        question.drawsBackground = false; question.isVerticallyResizable = true; question.isHorizontallyResizable = false
        question.autoresizingMask = [.width]; question.textContainer?.widthTracksTextView = true
        question.textContainerInset = NSSize(width: 4, height: 9)
        question.frame = NSRect(x: 0, y: 0, width: 240, height: 60)
        question.textContainer?.containerSize = NSSize(width: 240, height: CGFloat.greatestFiniteMagnitude)
        question.onSubmit = { [weak self] in self?.submit() }
        question.onChange = { [weak self] in self?.updateComposer() }
        question.setAccessibilityLabel("Question for Agent")
        promptScroll.drawsBackground = false; promptScroll.contentView.drawsBackground = false
        promptScroll.hasVerticalScroller = true; promptScroll.autohidesScrollers = true; promptScroll.documentView = question
        send.target = self; send.action = #selector(submit)
        send.title = ""; send.isBordered = false; send.imagePosition = .imageOnly
        send.wantsLayer = true; send.layer?.cornerRadius = 14
        question.onFocus = { [weak composer] focused in composer?.focused = focused }
        let controls = NSStackView(views: [model, NSView(), send]); controls.spacing = 8
        status.font = .systemFont(ofSize: 10); status.textColor = .secondaryLabelColor
        welcome.font = .systemFont(ofSize: 16, weight: .medium); welcome.textColor = .tertiaryLabelColor
        wantsLayer = true
        for view in [header, historyTabs, chatScroll, status, composer, welcome, historyView, accountView] { addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        for view in [promptScroll, controls] { composer.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        promptHeight = promptScroll.heightAnchor.constraint(equalToConstant: 60)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 14), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), header.heightAnchor.constraint(equalToConstant: 28),
            historyTabs.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2), historyTabs.leadingAnchor.constraint(equalTo: leadingAnchor), historyTabs.trailingAnchor.constraint(equalTo: trailingAnchor),
            accountView.topAnchor.constraint(equalTo: historyTabs.bottomAnchor), accountView.bottomAnchor.constraint(equalTo: bottomAnchor),
            accountView.leadingAnchor.constraint(equalTo: leadingAnchor), accountView.trailingAnchor.constraint(equalTo: trailingAnchor),
            historyView.topAnchor.constraint(equalTo: historyTabs.bottomAnchor, constant: 2), historyView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), historyView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), historyView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            chatScroll.topAnchor.constraint(equalTo: historyTabs.bottomAnchor, constant: 2), chatScroll.leadingAnchor.constraint(equalTo: leadingAnchor), chatScroll.trailingAnchor.constraint(equalTo: trailingAnchor), chatScroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            welcome.centerXAnchor.constraint(equalTo: chatScroll.centerXAnchor), welcome.centerYAnchor.constraint(equalTo: chatScroll.centerYAnchor, constant: -24),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), status.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            composer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), composer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), composer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            promptScroll.topAnchor.constraint(equalTo: composer.topAnchor, constant: 4), promptScroll.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 8), promptScroll.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -8), promptHeight!,
            controls.topAnchor.constraint(equalTo: promptScroll.bottomAnchor, constant: 4), controls.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 12), controls.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -10), controls.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -10), controls.heightAnchor.constraint(equalToConstant: 28),
            model.widthAnchor.constraint(lessThanOrEqualTo: controls.widthAnchor, constant: -44), send.widthAnchor.constraint(equalToConstant: 28), send.heightAnchor.constraint(equalToConstant: 28)
        ])
        accountChanged(); updateComposer(); updateHistoryVisibility()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        updateComposer()
    }
    override func layout() {
        super.layout()
        transcript.reflow(width: chatScroll.contentSize.width)
    }
    private func updateComposer() {
        let hasText = !question.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        send.isEnabled = busy || (hasText && account.state.isSignedIn && !account.isChanging)
        accountButton.isEnabled = !busy && !account.isChanging
        historyTabs.isEnabled = !busy
        send.image = NanoIcons.symbol(busy ? "stop.fill" : "arrow.up", label: busy ? "Stop" : "Send")
        send.toolTip = busy ? "Stop answer" : "Send · Enter (Shift+Enter for a new line)"
        effectiveAppearance.performAsCurrentDrawingAppearance {
            send.layer?.backgroundColor = (send.isEnabled ? NSColor.labelColor : NSColor.quaternaryLabelColor).cgColor
            send.contentTintColor = .windowBackgroundColor
        }
        if let container = question.textContainer, let manager = question.layoutManager {
            manager.ensureLayout(for: container)
            promptHeight?.constant = min(132, max(60, ceil(manager.usedRect(for: container).height) + 22))
        }
        question.needsDisplay = true
    }
    func activate() { account.refresh() }
    private func accountChanged() {
        if busy && (!account.state.isSignedIn || account.isChanging) { stop() }
        let oldDefault = defaultModelLabel
        if !account.models.isEmpty { availableModels = account.models }
        else if !account.state.isSignedIn { availableModels = [] }
        model.addOptions([defaultModelLabel] + availableModels)
        if model.selectedValue == oldDefault || model.selectedValue == "Default" || model.selectedValue.hasPrefix("Default ·") {
            model.selectedValue = defaultModelLabel
        }
        accountButton.title = account.state.isSignedIn ? "" : "Sign in"
        accountButton.image = account.state.isSignedIn ? NanoIcons.symbol("person.crop.circle", label: "Account") : nil
        accountButton.imagePosition = account.state.isSignedIn ? .imageOnly : .noImage
        accountButton.toolTip = "Account"
        if case .signedIn(let label) = account.state { accountButton.toolTip = label }
        accountButton.setAccessibilityLabel(accountButton.toolTip ?? "Account")
        accountView.show(account); updateComposer(); updateHistoryVisibility()
    }
    private func openCodexSetup() { NSWorkspace.shared.open(URL(string: "https://developers.openai.com/codex/cli/")!) }
    private func accountPrimary() {
        switch account.state {
        case .missing: openCodexSetup()
        case .signedOut: account.signIn()
        case .signingIn: if let url = account.loginURL { NSWorkspace.shared.open(url) }
        default: account.refresh()
        }
    }
    private func accountSecondary() {
        switch account.state {
        case .signingIn: account.cancelLogin()
        case .failed: openCodexSetup()
        default: account.refresh()
        }
    }
    @objc private func showAccount() {
        guard case .signedIn(let label) = account.state else { historyTabs.selectedIndex = 0; updateHistoryVisibility(); account.refresh(); return }
        let menu = NSMenu()
        let identity = NSMenuItem(title: label, action: nil, keyEquivalent: ""); identity.isEnabled = false
        menu.addItem(identity); menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh account & models", action: #selector(refreshAccount), keyEquivalent: "")
        refresh.target = self; menu.addItem(refresh)
        let logout = NSMenuItem(title: "Sign out…", action: #selector(signOutAccount), keyEquivalent: "")
        logout.target = self; menu.addItem(logout)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: accountButton.bounds.maxY + 4), in: accountButton)
    }
    @objc private func refreshAccount() { account.refresh() }
    @objc private func signOutAccount() {
        guard let window, !busy else { return }
        let alert = NSAlert(); alert.messageText = "Sign out of Codex?"
        alert.informativeText = "PDF Nano shares this login with Codex on this Mac. This also signs out the local Codex CLI. Saved chats stay on this Mac. You can then sign in with another account."
        alert.addButton(withTitle: "Sign out"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.account.signOut() }
        }
    }
    @objc private func togglePanel() { onToggle() }
    func pageChanged() {
        guard !busy else { return }
        syncDocument()
        status.stringValue = saveError ?? (pdfView?.document == nil ? "Open a PDF to start." : "")
    }
    private func syncDocument() {
        let context = documentContext()
        guard documentID != context.id else { return }
        if documentID.hasPrefix("untitled:"), !context.id.hasPrefix("untitled:") {
            do {
                try historyStore.migrate(from: documentID, to: context.id, title: context.title)
                currentThread?.documentID = context.id; currentThread?.documentTitle = context.title
            } catch { saveError = "Could not move saved chats to this PDF."; return }
        } else if !documentID.isEmpty {
            guard saveCurrentThread() else { return }
            currentThread = nil; history = []; transcript.clear()
        }
        documentID = context.id; documentTitle = context.title
        refreshHistory(); updateHistoryVisibility()
    }
    private func refreshHistory() {
        historyView.show(historyStore.records(for: documentID), error: historyStore.loadError == nil ? nil : "Saved chats could not be read. The existing file has been kept.")
    }
    private func updateHistoryVisibility() {
        let showingHistory = historyTabs.selectedIndex == 1
        historyView.isHidden = !showingHistory
        let needsAccount = !account.state.isSignedIn
        for view in [chatScroll as NSView, composer, status] { view.isHidden = showingHistory || needsAccount }
        welcome.isHidden = showingHistory || needsAccount || !transcript.isEmpty
        accountView.isHidden = showingHistory || !needsAccount
    }
    @objc private func changeHistoryTab() {
        syncDocument(); refreshHistory(); updateHistoryVisibility()
    }
    @discardableResult private func saveCurrentThread() -> Bool {
        guard let currentThread else { return true }
        if historyStore.wasDeleted(currentThread.id) {
            self.currentThread = nil; history = []; transcript.clear(); saveError = nil
            refreshHistory(); updateHistoryVisibility(); return true
        }
        do {
            try historyStore.save(currentThread); saveError = nil; refreshHistory(); return true
        } catch {
            saveError = "Could not save this chat. Keep it open and try again."
            status.stringValue = saveError!; return false
        }
    }
    @discardableResult private func record(_ text: String, role: String, pages: String, model: String?) -> Bool {
        if currentThread == nil { currentThread = ChatThread(documentID: documentID, documentTitle: documentTitle) }
        currentThread?.messages.append(ChatEntry(role: role, text: text, pages: pages, model: model))
        currentThread?.updatedAt = Date()
        return saveCurrentThread()
    }
    @objc private func newChat() {
        guard !busy else { status.stringValue = "Stop the current answer before starting a new chat."; return }
        guard saveCurrentThread() else { historyTabs.selectedIndex = 0; updateHistoryVisibility(); return }
        currentThread = nil; history = []; transcript.clear(); question.string = ""
        historyTabs.selectedIndex = 0; updateHistoryVisibility(); updateComposer(); pageChanged()
    }
    private func openThread(_ thread: ChatThread) {
        guard !busy, saveCurrentThread() else { return }
        currentThread = thread; history = thread.turns; transcript.clear(); question.string = ""
        for message in thread.messages { transcript.append(message.text, isUser: message.role == "user") }
        if let modelID = thread.messages.last(where: { $0.model != nil })?.model { model.selectedValue = modelID }
        historyTabs.selectedIndex = 0; updateHistoryVisibility(); updateComposer(); pageChanged()
        layoutSubtreeIfNeeded(); transcript.scrollToLatest()
    }
    private func deleteThread(_ id: UUID) {
        guard !busy else { return }
        do {
            try historyStore.delete(id)
            if currentThread?.id == id {
                currentThread = nil; history = []; transcript.clear(); question.string = ""; saveError = nil
            }
            refreshHistory(); updateHistoryVisibility(); updateComposer()
        } catch { historyView.show(historyStore.records(for: documentID), error: "Could not delete this chat. Try again.") }
    }
    private func append(_ text: String, isUser: Bool = false) {
        welcome.isHidden = true
        transcript.append(text, isUser: isUser)
        transcript.scrollToLatest()
    }
    @objc private func submit() {
        if busy { stop(); return }
        guard account.state.isSignedIn, !account.isChanging else { account.refresh(); return }
        syncDocument()
        let text = question.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let pdf = pdfView?.document, let page = pdfView?.currentPage else { return }
        let current = pdf.index(for: page)
        guard current < pdf.pageCount else { return }
        // Capture page identities at Send; navigation/reordering cannot change this question's source.
        let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }
        let chosen = model.selectedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesDefault = chosen.isEmpty || chosen == "Default" || chosen == defaultModelLabel
        let modelID = usesDefault ? defaultModelID : chosen
        guard let modelID else { status.stringValue = "Choose a model; the default is unavailable."; return }
        UserDefaults.standard.set(usesDefault ? "Default" : modelID, forKey: "PDFNanoAgentModel")
        busy = true; question.isEditable = false; model.isEnabled = false; updateComposer()
        append(text, isUser: true)
        // Save the question before requesting an answer, so interrupted requests
        // still appear in History. An I/O failure never discards the on-screen chat.
        _ = record(text, role: "user", pages: String(current + 1), model: modelID)
        let agent = ReadingAgent(pageCount: pages.count, currentPage: current + 1, question: text, history: history, model: modelID,
            pageText: { number in pages.indices.contains(number - 1) ? pages[number - 1].string ?? "" : "" },
            request: { [bridge] prompt, model, completion in
                bridge.ask(prompt: prompt, model: model, outputSchema: AgentDecision.schema, completion: completion)
            }, cancel: { [bridge] in bridge.cancel() })
        reading = agent
        agent.onProgress = { [weak self] text in self?.status.stringValue = text }
        agent.start { [weak self] result in
            guard let self else { return }
            self.busy = false; self.question.isEditable = true; self.model.isEnabled = true
            self.reading = nil
            switch result {
            case .success(let answer):
                self.history.append(AgentTurn(question: text, answer: answer, pages: String(current + 1)))
                self.append(answer)
                _ = self.record(answer, role: "assistant", pages: String(current + 1), model: modelID)
                self.question.string = ""; self.pageChanged()
            case .failure(let error):
                self.append(error.localizedDescription)
                _ = self.record(error.localizedDescription, role: "error", pages: String(current + 1), model: modelID)
                self.status.stringValue = self.saveError ?? "Try again when ready."
            }
            self.updateComposer()
        }
    }
    func stop() { reading?.cancel(); bridge.cancel() }
    deinit {
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        reading?.cancel(); bridge.cancel()
    }
}
