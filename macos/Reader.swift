import AppKit
import PDFKit
import Vision
import UniformTypeIdentifiers
import CoreImage

enum ReaderTool: Int { case select, highlight, pen, note }

final class NanoPDFView: PDFView {
    var tool: ReaderTool = .select
    var addMarks: ([(PDFPage, PDFAnnotation)]) -> Void = { _ in }
    var requestNote: (PDFPage, CGPoint) -> Void = { _, _ in }
    var selectAnnotation: (PDFPage, PDFAnnotation) -> Void = { _, _ in }
    var cancelTool: () -> Void = {}
    var openFile: (URL) -> Void = { _ in }
    var insertDroppedPages: ([PDFPage]) -> Void = { _ in }
    private var strokePage: PDFPage?
    private var stroke: [CGPoint] = []
    private var preview: PDFAnnotation?
    private var consumedMouseDown = false
    private var noteClickMonitor: Any?
    private var finishingNoteClick = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        finishingNoteClick = false
        if let noteClickMonitor { NSEvent.removeMonitor(noteClickMonitor); self.noteClickMonitor = nil }
        guard window != nil else { return }
        // PDFKit's internal document view can receive clicks before PDFView's
        // mouseDown override. Intercept only note clicks inside this PDF view.
        noteClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            guard let self else { return event }
            if self.finishingNoteClick && event.type != .leftMouseDown {
                if event.type == .leftMouseUp { self.finishingNoteClick = false }
                return nil
            }
            guard event.type == .leftMouseDown, let window = self.window, event.window === window,
                  let content = window.contentView else { return event }
            let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            let hit = content.hitTest(point)
            guard let hit, hit === self || hit.isDescendant(of: self), !(hit is NSScroller) else { return event }
            if self.handleNoteClick(at: self.convert(event.locationInWindow, from: nil), clickCount: event.clickCount) {
                self.finishingNoteClick = true
                window.makeKey(); return nil
            }
            return event
        }
    }
    deinit { if let noteClickMonitor { NSEvent.removeMonitor(noteClickMonitor) } }

    @discardableResult func handleNoteClick(at location: NSPoint, clickCount: Int = 1) -> Bool {
        guard tool == .select || tool == .note,
              let page = page(for: location, nearest: false) else { return false }
        if tool == .note && clickCount > 1 { cancelTool(); return true }
        if let mark = page.annotations.reversed().first(where: { annotation in
            guard annotation.type == "Text" || (annotation.type == "Highlight" && (tool == .note || annotation.contents?.isEmpty == false)) else { return false }
            var hitRect = convert(annotation.bounds, from: page)
            if annotation.type == "Text" {
                // The icon remains easy to click even when the page is zoomed out.
                hitRect = hitRect.insetBy(dx: -max(3, (22 - hitRect.width) / 2), dy: -max(3, (22 - hitRect.height) / 2))
            }
            return hitRect.contains(location)
        }) {
            selectAnnotation(page, mark); return true
        }
        if tool == .note { requestNote(page, convert(location, to: page)); return true }
        return false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let highlight = NSMenuItem(title: "Highlight", action: #selector(highlightSelectedText), keyEquivalent: "")
            highlight.target = self
            menu.insertItem(highlight, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    @objc func highlightSelectedText() {
        guard let selection = currentSelection, selection.string?.isEmpty == false else { return }
        addMarks(PDFOperations.highlight(selection))
        clearSelection()
        cancelTool()
    }

    override func mouseDown(with event: NSEvent) {
        consumedMouseDown = false
        if event.clickCount > 1 && tool != .select {
            consumedMouseDown = true
            cancelTool()
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        guard let page = page(for: location, nearest: false) else { super.mouseDown(with: event); return }
        let point = convert(location, to: page)
        if handleNoteClick(at: location, clickCount: event.clickCount) {
            consumedMouseDown = true; return
        }
        switch tool {
        case .note: consumedMouseDown = true; requestNote(page, point)
        case .pen:
            strokePage = page
            stroke = [point]
        default: super.mouseDown(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if handleReadingKey(event) { return }
        super.keyDown(with: event)
    }

    @discardableResult func handleReadingKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 123: goToPreviousPage(nil)
        case 124: goToNextPage(nil)
        case 125, 126:
            guard let scroll = documentView?.enclosingScrollView else { return false }
            let clip = scroll.contentView
            var bounds = clip.bounds
            let down = event.keyCode == 125
            let delta: CGFloat = down ? 54 : -54
            bounds.origin.y += documentView?.isFlipped == true ? delta : -delta
            clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
            scroll.reflectScrolledClipView(clip)
        case 53:
            cancelTool()
        default: return false
        }
        return true
    }

    override func mouseDragged(with event: NSEvent) {
        guard tool == .pen, let page = strokePage else { super.mouseDragged(with: event); return }
        let point = convert(convert(event.locationInWindow, from: nil), to: page)
        let bounds = page.bounds(for: .cropBox)
        stroke.append(CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY)))
        if let preview { page.removeAnnotation(preview) }
        preview = makeStroke(on: page)
        if let preview { page.addAnnotation(preview) }
    }

    override func mouseUp(with event: NSEvent) {
        if consumedMouseDown { consumedMouseDown = false; return }
        if tool == .pen {
            if let page = strokePage {
                if let preview { page.removeAnnotation(preview) }
                if stroke.count > 1, let mark = makeStroke(on: page) { addMarks([(page, mark)]) }
            }
            strokePage = nil; stroke = []; preview = nil
            return
        }
        guard tool != .note else { return }
        super.mouseUp(with: event)
        if tool == .highlight, let selection = currentSelection {
            addMarks(PDFOperations.highlight(selection))
            clearSelection()
        }
    }

    private func makeStroke(on page: PDFPage) -> PDFAnnotation? {
        guard let first = stroke.first else { return nil }
        let bounds = page.bounds(for: .cropBox)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: first.x - bounds.minX, y: first.y - bounds.minY))
        for point in stroke.dropFirst() { path.line(to: NSPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)) }
        let mark = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        mark.color = NSColor(calibratedRed: 0.23, green: 0.36, blue: 0.28, alpha: 1)
        let border = PDFBorder(); border.lineWidth = 1.6; mark.border = border
        mark.add(path)
        return mark
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        PageTransfer.supports(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty, urls.allSatisfy({ $0.pathExtension.lowercased() == "pdf" }),
           pasteboard.availableType(from: [PageTransfer.pageType]) == nil {
            for url in urls { openFile(url) }
            return true
        }
        do { insertDroppedPages(try PageTransfer.pages(from: pasteboard)); return true }
        catch { NSApp.presentError(error); return false }
    }
}

final class ReaderWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option),
           let reader = windowController as? ReaderController {
            if event.charactersIgnoringModifiers?.lowercased() == "z", (firstResponder as? NoteEditor)?.delegate is MarginNoteCard {
                if modifiers.contains(.shift) { reader.redo(nil) } else { reader.undo(nil) }
                return true
            }
            switch event.charactersIgnoringModifiers {
            case "+", "=": reader.zoomIn(); return true
            case "-": reader.zoomOut(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let reader = windowController as? ReaderController,
           !(firstResponder is NSTextView), reader.pdfView.handleReadingKey(event) { return }
        super.keyDown(with: event)
    }

    override func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }
}

final class ReaderController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate {
    let nanoDocument: NanoDocument
    let pdfView = NanoPDFView()
    let thumbnails = PageSidebar()
    let outline = DocumentOutline()
    private let sidebar = NSView()
    let sidebarMode = SidebarTabs()
    private let outlinePane = NSView()
    let columns = ReaderColumnsView()
    lazy var readingSurface = ReadingSurface(pdfView: pdfView)
    let agentPanel = AgentPanel()
    private let unsavedDocumentID = "untitled:" + UUID().uuidString
    private weak var navigationButton: NSButton?
    private weak var agentButton: NSButton?
    private var toolButtons: [ReaderTool: AnnotationToolButton] = [:]
    private var showingReader = false
    let pageLabel = NSTextField(labelWithString: "")
    let status = NSTextField(labelWithString: "")
    let searchField = NSSearchField()
    private var searchResults: [PDFSelection] = []
    private var resultIndex = 0
    private var recognizing = false
    private var ocrNoticeVisible = false
    private var ocrJob: UUID?
    private weak var ocrButton: NSButton?
    private let ocrProgress = OCRProgressView()
    private var ocrPages: [PDFPage] = []
    private var ocrIndex = 0
    private var ocrResults: [(original: PDFPage, replacement: PDFPage)] = []
    private var ocrSkipped = 0
    private var ocrEmpty = 0
    private var ocrFailed = 0
    private var ocrRebuild = false
    private var searchWork: DispatchWorkItem?
    private var outlineSyncWork: DispatchWorkItem?
    private var outlineRevealPending = false
    private var nightMode = UserDefaults.standard.bool(forKey: "PDFNanoNightMode")
    private let nightButton = ReaderActionButton()
    private let footer = NSView()
    private let titleIcon = NanoIcons.title()

    init(document: NanoDocument) {
        nanoDocument = document
        let window = ReaderWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.tabbingIdentifier = "PDFNanoDocuments"
        window.tabbingMode = .preferred
        window.minSize = NSSize(width: 720, height: 440)
        window.title = "PDF Nano"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PDFNanoReader")
        window.center()
        super.init(window: window)
        buildInterface()
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        if showingReader { agentPanel.pageChanged() }
        if nanoDocument.pdf.pageCount == 0 { window?.title = "PDF Nano" }
        applyTitleIcon()
        // NSDocument can finish refreshing its proxy icon later in this turn.
        DispatchQueue.main.async { [weak self] in self?.applyTitleIcon() }
    }

    override func showWindow(_ sender: Any?) {
        // Explicit grouping also works when the system tab preference is Manual.
        // Do not regroup an existing document when it is opened again.
        if let window, !window.isVisible,
           let host = NSApp.orderedWindows.first(where: {
               $0 !== window && $0.isVisible && $0.windowController is ReaderController
           }), !(host.tabbedWindows ?? []).contains(window) {
            host.addTabbedWindow(window, ordered: .above)
        }
        super.showWindow(sender)
        applyTitleIcon()
    }

    private func applyTitleIcon() {
        guard let window else { return }
        // A native window tab has its own title; the document proxy button is
        // a separate control. Supply a PNG attachment for the tab as well.
        window.tab.attributedTitle = NanoIcons.tabTitle(window.title)
        window.tab.toolTip = nanoDocument.fileURL?.path ?? window.title
        if let titleIcon, let button = window.standardWindowButton(.documentIconButton) {
            button.image = titleIcon
            button.alternateImage = titleIcon
            button.imageScaling = .scaleProportionallyDown
            button.needsDisplay = true
        }
    }

    private func buildInterface() {
        guard let window, let content = window.contentView else { return }
        window.appearance = NSAppearance(named: .aqua)
        pdfView.insertDroppedPages = { [weak self] pages in
            guard let self else { return }
            let index = self.pdfView.currentPage.map { self.nanoDocument.pdf.index(for: $0) + 1 } ?? 0
            self.insert(pages: pages, at: index)
        }
        if nanoDocument.pdf.pageCount == 0 {
            buildEmptyState(in: content)
            return
        }
        showingReader = true
        let toolbar = NSToolbar(identifier: "PDFNanoToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        pdfView.document = nanoDocument.pdf
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.backgroundColor = .underPageBackgroundColor
        pdfView.registerForDraggedTypes(PageTransfer.types)
        pdfView.addMarks = { [weak self] marks in self?.add(marks) }
        pdfView.requestNote = { [weak self] page, point in self?.note(on: page, at: point) }
        pdfView.openFile = { url in NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } } }
        thumbnails.pdfView = pdfView
        thumbnails.insertPages = { [weak self] pages, index in self?.insert(pages: pages, at: index) }
        thumbnails.movePages = { [weak self] rows, index in self?.move(pages: rows, to: index) }
        outline.pdfView = pdfView
        outline.reload()
        thumbnails.reload()
        sidebarMode.selectedIndex = 0
        sidebarMode.onChange = { [weak self] _ in self?.changeSidebarMode() }
        let collapse = ReaderActionButton(title: "Collapse all", target: outline, action: #selector(DocumentOutline.collapseAll))
        collapse.font = .systemFont(ofSize: 11, weight: .medium)
        collapse.image = NanoIcons.symbol("chevron.up", label: "Collapse all")
        collapse.imagePosition = .imageLeading; collapse.isBordered = false
        collapse.toolTip = "Collapse all outline sections"
        let outlineFooter = NSView()
        outlineFooter.addSubview(collapse); collapse.translatesAutoresizingMaskIntoConstraints = false
        for view in [outline, outlineFooter] {
            outlinePane.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            outline.topAnchor.constraint(equalTo: outlinePane.topAnchor),
            outline.leadingAnchor.constraint(equalTo: outlinePane.leadingAnchor),
            outline.trailingAnchor.constraint(equalTo: outlinePane.trailingAnchor),
            outline.bottomAnchor.constraint(equalTo: outlineFooter.topAnchor),
            outlineFooter.leadingAnchor.constraint(equalTo: outlinePane.leadingAnchor),
            outlineFooter.trailingAnchor.constraint(equalTo: outlinePane.trailingAnchor),
            outlineFooter.bottomAnchor.constraint(equalTo: outlinePane.bottomAnchor),
            outlineFooter.heightAnchor.constraint(equalToConstant: 36),
            collapse.leadingAnchor.constraint(equalTo: outlineFooter.leadingAnchor, constant: 10),
            collapse.centerYAnchor.constraint(equalTo: outlineFooter.centerYAnchor),
            collapse.trailingAnchor.constraint(lessThanOrEqualTo: outlineFooter.trailingAnchor, constant: -10)
        ])
        for view in [sidebarMode, thumbnails, outlinePane] {
            sidebar.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            sidebarMode.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarMode.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarMode.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor)
        ])
        for pane in [thumbnails as NSView, outlinePane] {
            NSLayoutConstraint.activate([
                pane.topAnchor.constraint(equalTo: sidebarMode.bottomAnchor),
                pane.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
                pane.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
            ])
        }
        outlinePane.isHidden = true
        thumbnails.backgroundColor = .windowBackgroundColor
        thumbnails.table.backgroundColor = .windowBackgroundColor
        outline.tree.backgroundColor = .windowBackgroundColor
        columns.configure(navigation: sidebar, reading: readingSurface, agent: agentPanel)
        agentPanel.pdfView = pdfView
        agentPanel.documentContext = { [weak self] in
            guard let self else { return ("unavailable", "PDF") }
            let id = self.nanoDocument.fileURL?.standardizedFileURL.resolvingSymlinksInPath().absoluteString ?? self.unsavedDocumentID
            return (id, self.nanoDocument.displayName)
        }
        agentPanel.onToggle = { [weak self] in self?.toggleAgent() }
        let body = columns
        configureNotes()
        pdfView.cancelTool = { [weak self] in self?.setTool(.select) }
        pdfView.selectAnnotation = { [weak self] _, mark in
            guard let self else { return }
            let addingNote = self.pdfView.tool == .note
            self.revealNote(mark, focus: addingNote)
            if addingNote { self.setTool(.select) }
        }

        pageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .center
        status.font = .systemFont(ofSize: 10)
        status.textColor = .tertiaryLabelColor
        let previous = button("chevron.left", "Previous page", #selector(previousPage))
        let next = button("chevron.right", "Next page", #selector(nextPage))
        let pageControls = NSStackView(views: [previous, pageLabel, next]); pageControls.spacing = 12
        let zoomOut = button("minus", "Zoom out", #selector(zoomOut))
        let zoomIn = button("plus", "Zoom in", #selector(zoomIn))
        let fit = button("arrow.up.left.and.arrow.down.right", "Fit page", #selector(fitPage))
        nightButton.setButtonType(.momentaryChange); nightButton.isBordered = false
        nightButton.target = self; nightButton.action = #selector(toggleNightMode)
        nightButton.contentTintColor = .secondaryLabelColor
        let zoomControls = NSStackView(views: [nightButton, zoomOut, zoomIn, fit]); zoomControls.spacing = 12
        for view in [body, footer] { content.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        for view in [status, ocrProgress, pageControls, zoomControls] { footer.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor), body.leadingAnchor.constraint(equalTo: content.leadingAnchor), body.trailingAnchor.constraint(equalTo: content.trailingAnchor), body.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor), footer.leadingAnchor.constraint(equalTo: content.leadingAnchor), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor), footer.heightAnchor.constraint(equalToConstant: 34),
            pageControls.centerXAnchor.constraint(equalTo: footer.centerXAnchor), pageControls.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            ocrProgress.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16), ocrProgress.centerYAnchor.constraint(equalTo: footer.centerYAnchor), ocrProgress.trailingAnchor.constraint(lessThanOrEqualTo: pageControls.leadingAnchor, constant: -16),
            status.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16), status.centerYAnchor.constraint(equalTo: footer.centerYAnchor), status.trailingAnchor.constraint(lessThanOrEqualTo: pageControls.leadingAnchor, constant: -16),
            zoomControls.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14), zoomControls.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(stopAgent), name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(pdfViewportChanged(_:)), name: NSView.boundsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pdfScaleChanged), name: .PDFViewScaleChanged, object: pdfView)
        // PDFKit's native note popovers can edit an existing annotation.
        NotificationCenter.default.addObserver(self, selector: #selector(annotationChanged), name: .PDFViewAnnotationHit, object: pdfView)
        pageChanged()
        applyNightMode()
    }

    private func buildEmptyState(in content: NSView) {
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.registerForDraggedTypes(PageTransfer.types)
        pdfView.openFile = { [weak self] url in self?.openDocument(at: url) }
        content.addSubview(pdfView)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: content.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
        applyNightMode()
    }

    private func openDocument(at url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            if let error { NSApp.presentError(error); return }
            if let self, self.nanoDocument.pdf.pageCount == 0, !self.nanoDocument.isDocumentEdited {
                self.nanoDocument.close()
            }
        }
    }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let b = ReaderToolbarButton(image: NanoIcons.symbol(symbol, label: label) ?? NSImage(), target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.isBordered = false
        b.toolTip = label
        b.setAccessibilityLabel(label)
        b.contentTintColor = .secondaryLabelColor
        return b
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("pages"), .flexibleSpace, .init("tools"), .init("agent"), .init("search")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id.rawValue {
        case "tools":
            let row = ToolbarGroupView(); row.spacing = 2; row.alignment = .centerY; row.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
            let definitions: [(ReaderTool, String, String)] = [(.highlight, "highlighter", "Highlight"), (.pen, "pencil.tip", "Write"), (.note, "note.text", "Add note")]
            for (tool, symbol, label) in definitions {
                let control = AnnotationToolButton(image: NanoIcons.symbol(symbol, label: label) ?? NSImage(), target: self, action: #selector(chooseTool(_:)))
                control.tag = tool.rawValue; control.setButtonType(.pushOnPushOff)
                control.bezelStyle = .recessed; control.isBordered = false
                control.toolTip = label + " · click again or double-click to exit"
                control.setAccessibilityLabel(label)
                control.contentTintColor = .secondaryLabelColor
                control.deactivate = { [weak self] in
                    self?.setTool(.select)
                }
                control.widthAnchor.constraint(equalToConstant: 32).isActive = true
                control.heightAnchor.constraint(equalToConstant: 28).isActive = true
                row.addArrangedSubview(control); toolButtons[tool] = control
            }
            let divider = NSBox(); divider.boxType = .separator
            divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
            divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
            row.addArrangedSubview(divider)
            let ocr = button("text.viewfinder", "Recognize document text (OCR)", #selector(recognizeText))
            ocr.bezelStyle = .recessed; ocr.setButtonType(.momentaryChange)
            ocr.widthAnchor.constraint(equalToConstant: 32).isActive = true
            ocr.heightAnchor.constraint(equalToConstant: 28).isActive = true
            ocr.state = ocrNoticeVisible ? .on : .off
            let ocrMenu = NSMenu()
            let rebuild = NSMenuItem(title: "Rebuild OCR for Entire Document…", action: #selector(rebuildDocumentOCR), keyEquivalent: "")
            rebuild.target = self; ocrMenu.addItem(rebuild)
            let stop = NSMenuItem(title: "Stop OCR", action: #selector(stopOCR), keyEquivalent: "")
            stop.target = self; ocrMenu.addItem(stop); ocr.menu = ocrMenu
            ocrButton = ocr
            updateOCRButton()
            row.addArrangedSubview(ocr)
            item.view = row; item.label = "Annotate & recognize"
        case "search":
            searchField.placeholderString = "Find"
            searchField.delegate = self; searchField.sendsSearchStringImmediately = true
            searchField.target = self; searchField.action = #selector(searchEntered)
            searchField.controlSize = .small; searchField.bezelStyle = .roundedBezel
            searchField.widthAnchor.constraint(equalToConstant: 150).isActive = true
            item.view = searchField; item.label = "Find"
        case "agent":
            let control = button("sparkles", "Agent · click again to close", #selector(toggleAgent))
            control.setButtonType(.toggle); control.state = columns.agentHidden ? .off : .on
            control.widthAnchor.constraint(equalToConstant: 32).isActive = true
            control.heightAnchor.constraint(equalToConstant: 30).isActive = true
            agentButton = control; item.view = control; item.label = "Agent"
        case "pages":
            let control = button("sidebar.left", "Toggle navigation", #selector(togglePages))
            control.setButtonType(.toggle); control.state = columns.navigationHidden ? .off : .on
            control.widthAnchor.constraint(equalToConstant: 32).isActive = true
            control.heightAnchor.constraint(equalToConstant: 30).isActive = true
            navigationButton = control; item.view = control; item.label = "Navigation"
        default: return nil
        }
        return item
    }

    @objc func pageChanged() {
        guard let page = pdfView.currentPage else { pageLabel.stringValue = "No pages"; return }
        pageLabel.stringValue = "\(nanoDocument.pdf.index(for: page) + 1) / \(nanoDocument.pdf.pageCount)"
        thumbnails.synchronizeSelection()
        pdfView.documentView?.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
        queueOutlineSelection()
        readingSurface.needsLayout = true
        agentPanel.pageChanged()
    }
    @objc private func pdfViewportChanged(_ notification: Notification) {
        guard let clip = notification.object as? NSClipView,
              clip === pdfView.documentView?.enclosingScrollView?.contentView else { return }
        queueOutlineSelection()
    }
    @objc private func pdfScaleChanged() { queueOutlineSelection() }
    private func queueOutlineSelection(reveal: Bool = false) {
        guard showingReader, !columns.navigationHidden, sidebarMode.selectedIndex == 1 else { return }
        outlineRevealPending = outlineRevealPending || reveal
        guard outlineSyncWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.outlineSyncWork = nil
            let reveal = self.outlineRevealPending; self.outlineRevealPending = false
            self.outline.synchronizeSelection(reveal: reveal)
        }
        outlineSyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }
    @objc func annotationChanged() {
        // Mark as edited when PDFKit lets the user interact with an existing note.
        if pdfView.tool == .select {
            nanoDocument.updateChangeCount(.changeDone)
            DispatchQueue.main.async { [weak self] in self?.thumbnails.reload() }
        }
    }
    @objc func previousPage() { pdfView.goToPreviousPage(nil) }
    @objc func nextPage() { pdfView.goToNextPage(nil) }
    @objc func zoomIn() { guard showingReader else { return }; pdfView.autoScales = false; pdfView.zoomIn(nil) }
    @objc func zoomOut() { guard showingReader else { return }; pdfView.autoScales = false; pdfView.zoomOut(nil) }
    @objc func fitPage() { pdfView.autoScales = true }
    @objc func toggleNightMode() {
        nightMode.toggle()
        UserDefaults.standard.set(nightMode, forKey: "PDFNanoNightMode")
        applyNightMode()
    }

    private func updateNightButton() {
        let label = nightMode ? "Turn off night mode" : "Turn on night mode"
        nightButton.image = NanoIcons.symbol(nightMode ? "moon.fill" : "moon", label: label)
        nightButton.toolTip = label
        nightButton.setAccessibilityLabel(label)
        nightButton.state = .off
        nightButton.setAccessibilityValue(nightMode ? "On" : "Off")
    }

    private func applyNightMode() {
        window?.appearance = NSAppearance(named: nightMode ? .darkAqua : .aqua)
        // The PDF filter also inverts its canvas. Use a light input canvas so
        // the displayed canvas stays dark, rather than inverting dark Aqua to white.
        pdfView.wantsLayer = true
        // Inverted page shadows become a bright halo along the bottom edge.
        pdfView.pageShadowsEnabled = !nightMode
        footer.wantsLayer = true
        footer.effectiveAppearance.performAsCurrentDrawingAppearance { footer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        let inverted = nightMode && nanoDocument.pdf.pageCount > 0
        pdfView.backgroundColor = inverted ? NSColor(calibratedWhite: 0.90, alpha: 1) : .underPageBackgroundColor
        pdfView.contentFilters = inverted ? [CIFilter(name: "CIColorInvert")].compactMap { $0 } : []
        thumbnails.contentFilters = []
        thumbnails.nightMode = nightMode
        thumbnails.backgroundColor = .windowBackgroundColor
        thumbnails.table.backgroundColor = .windowBackgroundColor
        outline.backgroundColor = .windowBackgroundColor
        outline.tree.backgroundColor = .windowBackgroundColor
        pdfView.needsDisplay = true
        updateNightButton()
    }
    @objc func togglePages() {
        guard showingReader else { return }
        columns.navigationHidden.toggle()
        navigationButton?.state = columns.navigationHidden ? .off : .on
        if columns.navigationHidden { window?.makeFirstResponder(pdfView) }
        else { queueOutlineSelection(reveal: true) }
    }
    @objc func changeSidebarMode() {
        thumbnails.isHidden = sidebarMode.selectedIndex == 1
        outlinePane.isHidden = sidebarMode.selectedIndex == 0
        queueOutlineSelection(reveal: true)
        let incoming: NSView = sidebarMode.selectedIndex == 0 ? thumbnails : outlinePane
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            incoming.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                incoming.animator().alphaValue = 1
            }
        } else { incoming.alphaValue = 1 }
    }
    @objc private func stopAgent() {
        outlineSyncWork?.cancel(); outlineSyncWork = nil
        agentPanel.stop()
        if recognizing { finishOCR("Text recognition stopped") }
    }

    @objc func toggleAgent() {
        guard showingReader else { return }
        columns.agentHidden.toggle()
        agentButton?.state = columns.agentHidden ? .off : .on
        agentPanel.pageChanged()
        if !columns.agentHidden { agentPanel.activate() }
        if columns.agentHidden { window?.makeFirstResponder(pdfView) }
    }

    func insert(pages: [PDFPage], at index: Int) {
        guard !pages.isEmpty, index >= 0, index <= nanoDocument.pdf.pageCount else { return }
        var order = (0..<nanoDocument.pdf.pageCount).compactMap { nanoDocument.pdf.page(at: $0) }
        order.insert(contentsOf: pages, at: index)
        setPages(order, focus: pages.first, action: "Insert Pages")
    }

    func move(pages rows: IndexSet, to index: Int) {
        let order = (0..<nanoDocument.pdf.pageCount).compactMap { nanoDocument.pdf.page(at: $0) }
        guard !rows.isEmpty, rows.allSatisfy({ $0 < order.count }), index >= 0, index <= order.count else { return }
        let moving = rows.map { order[$0] }
        var remaining = order.enumerated().filter { !rows.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: index - rows.filter { $0 < index }.count)
        guard !zip(order, remaining).allSatisfy({ $0 === $1 }) else { return }
        setPages(remaining, focus: moving.first, action: "Move Pages")
    }

    private func setPages(_ pages: [PDFPage], focus: PDFPage?, action: String) {
        let previous = (0..<nanoDocument.pdf.pageCount).compactMap { nanoDocument.pdf.page(at: $0) }
        let previousFocus = pdfView.currentPage
        nanoDocument.undoManager?.registerUndo(withTarget: self) { target in
            target.setPages(previous, focus: previousFocus, action: action)
        }
        nanoDocument.undoManager?.setActionName(action)
        searchWork?.cancel(); searchResults = []
        pdfView.highlightedSelections = []; pdfView.clearSelection()
        // Keep the PDFDocument instance and its bookmarks; page identities also
        // preserve destinations and annotation undo targets during reordering.
        if previous.count == pages.count {
            let replacements = zip(previous, pages).filter { old, new in old !== new && !pages.contains(where: { $0 === old }) }
            func remap(_ destination: PDFDestination?) -> PDFDestination? {
                guard let destination, let replacement = replacements.first(where: { $0.0 === destination.page }) else { return destination }
                let result = PDFDestination(page: replacement.1, at: destination.point)
                result.zoom = destination.zoom
                return result
            }
            func updateOutline(_ node: PDFOutline) {
                if let destination = node.destination { node.destination = remap(destination) }
                if let action = node.action as? PDFActionGoTo { action.destination = remap(action.destination)! }
                for index in 0..<node.numberOfChildren { if let child = node.child(at: index) { updateOutline(child) } }
            }
            if let root = nanoDocument.pdf.outlineRoot { updateOutline(root) }
            for page in pages {
                for annotation in page.annotations {
                    if let action = annotation.action as? PDFActionGoTo { action.destination = remap(action.destination)! }
                }
            }
        }
        for index in (0..<nanoDocument.pdf.pageCount).reversed() { nanoDocument.pdf.removePage(at: index) }
        for (index, page) in pages.enumerated() { nanoDocument.pdf.insert(page, at: index) }
        if !showingReader && !pages.isEmpty, let content = window?.contentView {
            NSLayoutConstraint.deactivate(content.constraints)
            content.subviews.forEach { $0.removeFromSuperview() }
            buildInterface()
            columns.navigationHidden = false
        }
        pdfView.document = nil; pdfView.document = nanoDocument.pdf
        thumbnails.reload(); outline.reload(); readingSurface.reload(document: nanoDocument.pdf)
        if let focus, nanoDocument.pdf.index(for: focus) < nanoDocument.pdf.pageCount { pdfView.go(to: focus) }
        pageChanged(); status.stringValue = ""
        if !searchField.stringValue.isEmpty { search() }
        let undo = nanoDocument.undoManager
        nanoDocument.updateChangeCount(undo?.isUndoing == true ? .changeUndone : .changeDone)
    }
    @objc func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { self?.openDocument(at: url) }
        }
    }
    @objc func savePDF() { nanoDocument.save(self) }
    @objc func focusSearch() { window?.makeFirstResponder(searchField) }
    @objc func chooseTool(_ sender: NSButton) {
        guard let tool = ReaderTool(rawValue: sender.tag) else { return }
        setTool(pdfView.tool == tool ? .select : tool)
    }
    func setTool(_ tool: ReaderTool) {
        pdfView.tool = tool
        for (kind, control) in toolButtons {
            control.state = kind == tool ? .on : .off
            control.isBordered = false
            control.contentTintColor = kind == tool ? .controlAccentColor : .secondaryLabelColor
        }
        status.stringValue = ["", "Select text to highlight · Esc to exit", "Draw on the page · Esc to exit", "Click a page to add a note · Esc to exit"][tool.rawValue]
        if tool == .highlight, let selection = pdfView.currentSelection, selection.string?.isEmpty == false {
            let marks = PDFOperations.highlight(selection)
            add(marks); pdfView.clearSelection()
        }
        if tool == .note {
            if let selection = pdfView.currentSelection, selection.string?.isEmpty == false {
                let existing = selection.pages.lazy.compactMap { page in
                    page.annotations.first { $0.type == "Highlight" && $0.bounds.insetBy(dx: -2, dy: -2).contains(selection.bounds(for: page)) }
                }.first
                if let existing { revealNote(existing, focus: true) }
                else {
                    let marks = PDFOperations.highlight(selection)
                    add(marks); pdfView.clearSelection()
                    if let mark = marks.first?.1 { revealNote(mark, focus: true) }
                }
                setTool(.select)
            }
        }
    }
    @objc func undoAnnotation() { nanoDocument.undoManager?.undo() }
    @objc func undo(_ sender: Any?) { nanoDocument.undoManager?.undo() }
    @objc func redo(_ sender: Any?) { nanoDocument.undoManager?.redo() }

    func add(_ marks: [(PDFPage, PDFAnnotation)]) {
        guard !marks.isEmpty else { return }
        for (page, mark) in marks { page.addAnnotation(mark) }
        nanoDocument.undoManager?.registerUndo(withTarget: self) { target in target.remove(marks) }
        thumbnails.reload()
        readingSurface.reload(document: nanoDocument.pdf)
        nanoDocument.undoManager?.setActionName("Annotation")
        nanoDocument.updateChangeCount(nanoDocument.undoManager?.isUndoing == true ? .changeUndone : .changeDone)
    }
    private func remove(_ marks: [(PDFPage, PDFAnnotation)]) {
        for (page, mark) in marks { page.removeAnnotation(mark) }
        nanoDocument.undoManager?.registerUndo(withTarget: self) { target in target.add(marks) }
        nanoDocument.updateChangeCount(nanoDocument.undoManager?.isUndoing == true ? .changeUndone : .changeDone)
        thumbnails.reload()
        readingSurface.reload(document: nanoDocument.pdf)
    }
    func note(on page: PDFPage, at point: CGPoint) {
        guard page.document === nanoDocument.pdf else { return }
        let mark = PDFAnnotation(bounds: CGRect(x: point.x, y: point.y - 20, width: 24, height: 24), forType: .text, withProperties: nil)
        mark.contents = ""; mark.color = .systemYellow
        add([(page, mark)])
        revealNote(mark, focus: true)
        setTool(.select)
    }

    private func configureNotes() {
        readingSurface.onUndo = { [weak self] redo in
            if redo { self?.redo(nil) } else { self?.undo(nil) }
        }
        readingSurface.onSelect = { [weak self] note in self?.emphasize(note.annotation) }
        readingSurface.onEdit = { [weak self] note, text in self?.updateNote(note.annotation, text: text, refresh: false) }
        readingSurface.onDelete = { [weak self] note in self?.deleteNote(note.annotation) }
        readingSurface.reload(document: nanoDocument.pdf)
    }

    func revealNote(_ annotation: PDFAnnotation, focus: Bool) {
        if let page = annotation.page {
            let anchor = pdfView.convert(annotation.bounds, from: page)
            if !pdfView.visibleRect.intersects(anchor) { emphasize(annotation) }
        }
        readingSurface.select(annotation, in: nanoDocument.pdf, toggle: !focus)
        readingSurface.focusEditor()
    }

    private func emphasize(_ annotation: PDFAnnotation) {
        guard let page = annotation.page else { return }
        pdfView.clearSelection()
        pdfView.go(to: annotation.bounds, on: page)
        if annotation.type == "Highlight", let selection = page.selection(for: annotation.bounds) {
            pdfView.setCurrentSelection(selection, animate: true)
        }
    }

    func deleteNote(_ annotation: PDFAnnotation) {
        guard let page = annotation.page, page.document === nanoDocument.pdf else { return }
        readingSurface.dismiss(annotation, in: nanoDocument.pdf)
        if annotation.type == "Highlight" {
            setNote(annotation, contents: nil, popup: nil)
            nanoDocument.undoManager?.setActionName("Delete Note")
        } else { remove([(page, annotation)]) }
        readingSurface.reload(document: nanoDocument.pdf)
    }

    func updateNote(_ annotation: PDFAnnotation, text: String, refresh: Bool = true) {
        guard annotation.contents != text else { return }
        setNote(annotation, contents: text, popup: annotation.popup, refresh: refresh)
    }
    private func setNote(_ annotation: PDFAnnotation, contents: String?, popup: PDFAnnotation?, refresh: Bool = true) {
        guard let page = annotation.page, page.document === nanoDocument.pdf else { return }
        let previous = annotation.contents, previousPopup = annotation.popup
        nanoDocument.undoManager?.registerUndo(withTarget: self) { target in
            target.setNote(annotation, contents: previous, popup: previousPopup)
        }
        nanoDocument.undoManager?.setActionName("Edit Note")
        if previousPopup !== popup, let previousPopup, previousPopup.page === page { page.removeAnnotation(previousPopup) }
        annotation.contents = contents
        if contents == nil { annotation.removeValue(forAnnotationKey: .contents) }
        annotation.popup = popup
        if popup == nil { annotation.removeValue(forAnnotationKey: .popup) }
        else if let popup, popup.page !== page { page.addAnnotation(popup) }
        nanoDocument.updateChangeCount(nanoDocument.undoManager?.isUndoing == true ? .changeUndone : .changeDone)
        pdfView.needsDisplay = true
        if refresh { readingSurface.reload(document: nanoDocument.pdf, selecting: annotation) }
    }

    func controlTextDidChange(_ obj: Notification) {
        searchWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.search() }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    @objc private func searchEntered() { nextSearchResult() }
    private func search() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        searchResults = []; resultIndex = 0
        guard !query.isEmpty else { pdfView.highlightedSelections = []; pdfView.clearSelection(); status.stringValue = ""; return }
        searchResults = nanoDocument.pdf.findString(query, withOptions: .caseInsensitive)
        for selection in searchResults { selection.color = NSColor.systemYellow.withAlphaComponent(0.3) }
        pdfView.highlightedSelections = searchResults
        showSearchResult()
    }
    @objc func nextSearchResult() {
        if !searchResults.isEmpty { resultIndex = (resultIndex + 1) % searchResults.count; showSearchResult() }
    }
    private func showSearchResult() {
        guard !searchResults.isEmpty else { status.stringValue = "No matches"; return }
        status.stringValue = "\(resultIndex + 1) of \(searchResults.count) matches"
        let selection = searchResults[resultIndex]
        pdfView.setCurrentSelection(selection, animate: true); pdfView.go(to: selection)
    }

    @objc func scanImages() {
        let panel = NSOpenPanel(); panel.title = "Choose page images"; panel.prompt = "Create PDF"
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]; panel.allowsMultipleSelection = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            do {
                let document = NanoDocument(); document.pdf = try PDFOperations.scan(panel.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
                NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows(); document.updateChangeCount(.changeDone)
            } catch { NSApp.presentError(error) }
        }
    }

    private func updateOCRButton() {
        ocrButton?.state = ocrNoticeVisible ? .on : .off
        ocrButton?.toolTip = ocrNoticeVisible ? "Hide OCR status" : (recognizing ? "Show OCR progress" : "Recognize document text (OCR) · Right-click to rebuild")
    }

    private func finishOCR(_ message: String) {
        recognizing = false; ocrJob = nil
        ocrPages = []; ocrResults = []
        ocrProgress.finish(); status.isHidden = false
        status.stringValue = ocrNoticeVisible ? message : ""
        updateOCRButton()
    }

    @objc func recognizeText() {
        if recognizing {
            ocrNoticeVisible.toggle()
            ocrProgress.isHidden = !ocrNoticeVisible
            updateOCRButton()
            return
        }
        if ocrNoticeVisible {
            ocrNoticeVisible = false; status.stringValue = ""
            updateOCRButton()
            return
        }
        startDocumentOCR(rebuild: false)
    }

    @objc private func rebuildDocumentOCR() {
        guard !recognizing, nanoDocument.pdf.pageCount > 0, let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Rebuild OCR for this document?"
        alert.informativeText = "Use this to repair misaligned text selection. Every page's content will become a high-resolution image with a fresh text layer. This can increase file size. Notes and highlights stay editable; Undo restores the original pages."
        alert.addButton(withTitle: "Rebuild OCR"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.startDocumentOCR(rebuild: true) }
        }
    }
    private func startDocumentOCR(rebuild: Bool) {
        guard !recognizing, nanoDocument.pdf.pageCount > 0 else { return }
        recognizing = true; ocrJob = UUID(); ocrNoticeVisible = true; ocrRebuild = rebuild
        ocrPages = (0..<nanoDocument.pdf.pageCount).compactMap { nanoDocument.pdf.page(at: $0) }
        ocrResults = []; ocrIndex = 0; ocrSkipped = 0; ocrEmpty = 0; ocrFailed = 0
        status.isHidden = true; updateOCRButton()
        processNextOCRPage()
    }
    private func advanceOCR() {
        guard let job = ocrJob else { return }
        ocrIndex += 1
        let index = ocrIndex
        DispatchQueue.main.async { [weak self] in
            guard let self, self.ocrJob == job, self.ocrIndex == index else { return }
            self.processNextOCRPage()
        }
    }
    private func processNextOCRPage() {
        guard recognizing, let job = ocrJob else { return }
        guard ocrIndex < ocrPages.count else { applyDocumentOCR(); return }
        let index = ocrIndex, page = ocrPages[index], rebuild = ocrRebuild
        ocrProgress.begin(page: index + 1, total: ocrPages.count)
        ocrProgress.isHidden = !ocrNoticeVisible
        guard page.document === nanoDocument.pdf else { ocrSkipped += 1; advanceOCR(); return }
        if !rebuild && page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            ocrSkipped += 1; advanceOCR(); return
        }
        guard let snapshot = page.copy() as? PDFPage else { ocrFailed += 1; advanceOCR(); return }
        // Do not recognize or flatten editable notes/highlights into the scan.
        for annotation in snapshot.annotations { snapshot.removeAnnotation(annotation) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = snapshot.thumbnail(of: NSSize(width: 2400, height: 3200), for: .cropBox)
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.ocrJob == job, self.ocrIndex == index else { return }
                    self.ocrFailed += 1; self.advanceOCR()
                }
                return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.ocrJob == job, self.ocrIndex == index else { return }
                self.ocrProgress.recognize()
            }
            request.progressHandler = { [weak self] request, fraction, error in
                guard error == nil else { return }
                let indeterminate = (request as? VNRecognizeTextRequest)?.indeterminate ?? true
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.ocrJob == job, self.ocrIndex == index else { return }
                    self.ocrProgress.recognize(fraction: indeterminate ? nil : fraction)
                }
            }
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                let lines = (request.results ?? []).compactMap { OCRRecognition.line(from: $0) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.ocrJob == job, self.ocrIndex == index else { return }
                    if lines.isEmpty { self.ocrEmpty += 1; self.advanceOCR(); return }
                    guard page.document === self.nanoDocument.pdf else { self.ocrSkipped += 1; self.advanceOCR(); return }
                    self.ocrProgress.applying()
                    do {
                        let recognized = try PDFOperations.recognizedPage(page, lines: lines, replacingTextWith: rebuild ? cgImage : nil)
                        self.ocrResults.append((page, recognized))
                    } catch { self.ocrFailed += 1 }
                    self.advanceOCR()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.ocrJob == job, self.ocrIndex == index else { return }
                    self.ocrFailed += 1; self.advanceOCR()
                }
            }
        }
    }
    @objc private func stopOCR() {
        guard recognizing else { return }
        applyDocumentOCR(stopped: true)
    }
    private func applyDocumentOCR(stopped: Bool = false) {
        // One replacement/undo step and one full-document search refresh, rather
        // than reloading and rescanning the PDF after every recognized page.
        ocrJob = nil
        var replacements: [ObjectIdentifier: PDFPage] = [:]
        for pair in ocrResults where pair.original.document === nanoDocument.pdf {
            // Notes may have been edited while later pages were being recognized.
            let annotations = pair.original.annotations.compactMap { $0.copy() as? PDFAnnotation }
            guard annotations.count == pair.original.annotations.count else { ocrFailed += 1; continue }
            for annotation in pair.replacement.annotations { pair.replacement.removeAnnotation(annotation) }
            for annotation in annotations { pair.replacement.addAnnotation(annotation) }
            replacements[ObjectIdentifier(pair.original)] = pair.replacement
        }
        if !replacements.isEmpty {
            let destination = pdfView.currentDestination
            let pages = (0..<nanoDocument.pdf.pageCount).compactMap { nanoDocument.pdf.page(at: $0) }
            let focus = pdfView.currentPage.map { replacements[ObjectIdentifier($0)] ?? $0 }
            setPages(pages.map { replacements[ObjectIdentifier($0)] ?? $0 }, focus: focus, action: "Recognize Document Text")
            if let destination, let page = destination.page {
                pdfView.go(to: PDFDestination(page: replacements[ObjectIdentifier(page)] ?? page, at: destination.point))
            }
        }
        var summary = stopped ? "OCR stopped · " : "OCR complete · "
        summary += "\(replacements.count) pages updated"
        if ocrSkipped > 0 { summary += " · \(ocrSkipped) skipped" }
        if ocrEmpty > 0 { summary += " · \(ocrEmpty) without text" }
        if ocrFailed > 0 { summary += " · \(ocrFailed) failed" }
        if !replacements.isEmpty { summary += " · ⌘S to keep" }
        finishOCR(summary)
    }

    func replacePage(_ original: PDFPage, with replacement: PDFPage) {
        let index = nanoDocument.pdf.index(for: original)
        guard index < nanoDocument.pdf.pageCount else { return }
        var pages = (0..<nanoDocument.pdf.pageCount).compactMap { nanoDocument.pdf.page(at: $0) }
        pages[index] = replacement
        setPages(pages, focus: replacement, action: "Recognize Page Text")
    }

    deinit { agentPanel.stop(); NotificationCenter.default.removeObserver(self) }
}
