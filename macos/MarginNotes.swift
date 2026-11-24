import AppKit
import PDFKit

final class MarginNoteCard: NSView, NSTextViewDelegate {
    let note: ReaderNote
    let editor = NoteEditor()
    var onEdit: (ReaderNote, String) -> Void = { _, _ in }
    var onDelete: (ReaderNote) -> Void = { _ in }
    var onSelect: (ReaderNote) -> Void = { _ in }
    var onFocus: (ReaderNote) -> Void = { _ in }
    private let quote = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    init(note: ReaderNote) {
        self.note = note
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 7; layer?.borderWidth = 1
        let page = NSButton(title: "p. \(note.pageNumber)", target: self, action: #selector(selectNote))
        page.isBordered = false; page.font = .systemFont(ofSize: 10, weight: .medium)
        page.toolTip = "Show linked passage"
        let delete = NSButton(image: NanoIcons.symbol("trash", label: "Delete note") ?? NSImage(), target: self, action: #selector(deleteNote))
        delete.isBordered = false; delete.controlSize = .small
        let header = NSStackView(views: [page, NSView(), delete])
        quote.stringValue = note.quote; quote.font = .systemFont(ofSize: 10); quote.textColor = .secondaryLabelColor
        quote.maximumNumberOfLines = 2
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        editor.string = note.annotation.contents ?? ""; editor.font = .systemFont(ofSize: 12)
        editor.isEditable = true; editor.isSelectable = true
        editor.isRichText = false; editor.drawsBackground = false; editor.allowsUndo = false
        editor.textContainerInset = NSSize(width: 2, height: 4)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.frame = NSRect(x: 0, y: 0, width: 130, height: 60)
        editor.textContainer?.containerSize = NSSize(width: 130, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = self; scroll.documentView = editor
        editor.setAccessibilityLabel("Note on page \(note.pageNumber)")
        for view in [header, quote, scroll] { addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 5), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), header.heightAnchor.constraint(equalToConstant: 20),
            quote.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2), quote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), quote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: quote.bottomAnchor, constant: 4), scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7), scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7), scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAppearance() }
    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.45).cgColor
        }
    }
    override func layout() {
        super.layout()
        let size = scroll.contentSize
        guard size.width > 0, size.height > 0 else { return }
        editor.minSize = NSSize(width: 0, height: size.height)
        editor.setFrameSize(NSSize(width: size.width, height: max(size.height, editor.frame.height)))
    }
    func refresh() {
        if window?.firstResponder !== editor { editor.string = note.annotation.contents ?? "" }
    }
    func textDidBeginEditing(_ notification: Notification) { onFocus(note) }
    func textDidChange(_ notification: Notification) { onEdit(note, editor.string) }
    @objc private func deleteNote() {
        // Closing the editor must not write its stale text back after deletion.
        editor.delegate = nil
        onDelete(note)
    }
    @objc private func selectNote() { onSelect(note) }
}

// The reading surface never reserves space for notes. A note opens beside its
// annotation in a transient popover, without changing the PDF viewport or zoom.
final class ReadingSurface: NSView, NSPopoverDelegate {
    let pdfView: NanoPDFView
    var onEdit: (ReaderNote, String) -> Void = { _, _ in }
    var onDelete: (ReaderNote) -> Void = { _ in }
    var onSelect: (ReaderNote) -> Void = { _ in }
    private(set) var selectedNote: ReaderNote?
    private(set) var entries: [ReaderNote] = []
    var onUndo: (Bool) -> Void = { _ in }
    private var popover: NSPopover?
    private var focusRequested = false
    private var card: MarginNoteCard?
    var editor: NoteEditor? { card?.editor }

    init(pdfView: NanoPDFView) {
        self.pdfView = pdfView
        super.init(frame: .zero)
        wantsLayer = true
        pdfView.translatesAutoresizingMaskIntoConstraints = true
        pdfView.autoresizingMask = [.width, .height]
        addSubview(pdfView)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        popover?.appearance = effectiveAppearance
    }
    override func layout() { super.layout(); pdfView.frame = bounds }
    func reload(document: PDFDocument, selecting annotation: PDFAnnotation? = nil) {
        entries = (0..<document.pageCount).flatMap { index -> [ReaderNote] in
            guard let page = document.page(at: index) else { return [] }
            return page.annotations.filter { $0.type == "Text" || ($0.type == "Highlight" && ($0.contents?.isEmpty == false || $0 === selectedNote?.annotation)) }.map {
                ReaderNote(page: page, annotation: $0, pageNumber: index + 1)
            }
        }
        if let selectedNote {
            self.selectedNote = entries.first { $0.annotation === selectedNote.annotation }
            if self.selectedNote == nil { closeNote() }
            else if annotation === selectedNote.annotation { card?.editor.string = annotation?.contents ?? "" }
            else { card?.refresh() }
        }
    }
    func dismiss(_ annotation: PDFAnnotation, in document: PDFDocument) {
        if selectedNote?.annotation === annotation {
            card?.editor.delegate = nil
            closeNote()
        }
        reload(document: document)
    }
    private func closeNote() {
        let previous = popover; popover = nil
        selectedNote = nil; card = nil; focusRequested = false
        previous?.close()
    }
    func select(_ annotation: PDFAnnotation, in document: PDFDocument, toggle: Bool = false) {
        if toggle && selectedNote?.annotation === annotation && card != nil {
            closeNote(); return
        }
        closeNote()
        guard let page = annotation.page, page.document === document else { return }
        let note = ReaderNote(page: page, annotation: annotation, pageNumber: document.index(for: page) + 1)
        selectedNote = note
        reload(document: document)
        let view = MarginNoteCard(note: note)
        let size = NSSize(width: 260, height: note.quote.isEmpty ? 190 : 220)
        view.frame = NSRect(origin: .zero, size: size)
        view.editor.onUndo = { [weak self] redo in self?.onUndo(redo) }
        view.onEdit = { [weak self] note, text in self?.onEdit(note, text) }
        view.onDelete = { [weak self] note in self?.onDelete(note) }
        view.onSelect = { [weak self] note in self?.onSelect(note) }
        let controller = NSViewController(); controller.view = view; controller.preferredContentSize = size
        let popup = NSPopover()
        popup.behavior = .transient; popup.animates = true; popup.delegate = self
        popup.contentViewController = controller; popup.contentSize = size
        popup.appearance = effectiveAppearance
        popover = popup; card = view
        // Present after the triggering click has finished. This also gives
        // PDFKit a layout pass after scrolling to an offscreen annotation.
        DispatchQueue.main.async { [weak self, weak popup] in
            guard let self, let popup, self.popover === popup, self.window != nil,
                  annotation.page?.document === document else { return }
            self.layoutSubtreeIfNeeded()
            let rect = self.pdfView.convert(annotation.bounds, from: page).intersection(self.pdfView.visibleRect)
            let anchor = rect.isNull || rect.isEmpty ? NSRect(x: self.pdfView.bounds.midX, y: self.pdfView.bounds.midY, width: 1, height: 1) : rect
            popup.show(relativeTo: anchor, of: self.pdfView, preferredEdge: .maxX)
        }
    }
    func focusEditor() {
        guard card != nil else { return }
        focusRequested = true
        if popover?.isShown == true { focusShownEditor() }
    }
    private func focusShownEditor() {
        guard focusRequested, let editor, let window = editor.window else { return }
        window.makeKey()
        if window.makeFirstResponder(editor) {
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            editor.scrollRangeToVisible(editor.selectedRange()); focusRequested = false
        }
    }
    func popoverDidShow(_ notification: Notification) {
        guard let shown = notification.object as? NSPopover, shown === popover else { return }
        focusShownEditor()
    }
    func popoverDidClose(_ notification: Notification) {
        // An old animated popover may finish closing after a new one opens.
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        popover = nil; selectedNote = nil; card = nil; focusRequested = false
    }
}
