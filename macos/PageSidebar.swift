import AppKit
import PDFKit
import CoreImage
import UniformTypeIdentifiers

// Each dragged thumbnail carries a standalone PDF, so the destination never
// takes ownership of a page that still belongs to another document.
enum PageTransfer {
    static let pageType = NSPasteboard.PasteboardType("app.pdfnano.page")
    static let types: [NSPasteboard.PasteboardType] = [pageType, .fileURL, .pdf, .tiff, .png]

    static func supports(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: [pageType, .pdf, .tiff, .png]) != nil { return true }
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        return urls.allSatisfy { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .pdf) || type.conforms(to: .image)
        }
    }

    static func pages(from pasteboard: NSPasteboard) throws -> [PDFPage] {
        var result: [PDFPage] = []
        for item in pasteboard.pasteboardItems ?? [] {
            if let data = item.data(forType: pageType) ?? item.data(forType: .pdf) {
                guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0 else { throw invalidDrop() }
                for index in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: index)?.copy() as? PDFPage else { throw invalidDrop() }
                    result.append(page)
                }
            } else if let path = item.string(forType: .fileURL), let url = URL(string: path), url.isFileURL {
                if url.pathExtension.lowercased() == "pdf" {
                    guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount > 0 else { throw invalidDrop() }
                    for index in 0..<pdf.pageCount {
                        guard let page = pdf.page(at: index)?.copy() as? PDFPage else { throw invalidDrop() }
                        result.append(page)
                    }
                } else {
                    guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { throw invalidDrop() }
                    result.append(page)
                }
            } else if let data = item.data(forType: .tiff) ?? item.data(forType: .png),
                      let image = NSImage(data: data), let page = PDFPage(image: image) {
                result.append(page)
            } else { throw invalidDrop() }
        }
        guard !result.isEmpty else { throw invalidDrop() }
        return result
    }

    private static func invalidDrop() -> NSError {
        NSError(domain: "PDFNano", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not insert these pages. Use readable, unlocked PDFs or image files."])
    }
}

// The frame follows the PDF's real aspect ratio, including rotated pages.
final class PageThumbnailCell: NSTableCellView {
    private let preview = NSImageView()
    private let number = NSTextField(labelWithString: "")
    var aspect: CGFloat = 1
    override init(frame: NSRect) {
        super.init(frame: frame)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.borderWidth = 1
        preview.layer?.shadowOpacity = 0.16
        preview.layer?.shadowRadius = 3
        preview.layer?.shadowOffset = NSSize(width: 0, height: -1)
        number.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        number.alignment = .center
        addSubview(preview); addSubview(number)
        imageView = preview; textField = number
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            preview.layer?.borderColor = NSColor.separatorColor.cgColor
            preview.layer?.backgroundColor = NSColor.white.cgColor
            preview.layer?.shadowColor = NSColor.black.cgColor
        }
        number.textColor = .secondaryLabelColor
    }
    func setNightMode(_ enabled: Bool) {
        preview.contentFilters = enabled ? [CIFilter(name: "CIColorInvert")].compactMap { $0 } : []
    }
    override func layout() {
        super.layout()
        let width = max(1, bounds.width - 40)
        let height = width * aspect
        preview.frame = NSRect(x: 20, y: 30, width: width, height: height)
        number.frame = NSRect(x: 0, y: 7, width: bounds.width, height: 16)
    }
}

final class PageThumbnailRow: SidebarSelectionRow {}

final class PageSidebar: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    var nightMode = false { didSet { if oldValue != nightMode { table.reloadData() } } }
    weak var pdfView: PDFView?
    var prepareDrag: () -> Void = {}
    var insertPages: ([PDFPage], Int) -> Void = { _, _ in }
    var movePages: (IndexSet, Int) -> Void = { _, _ in }
    private var draggedRows = IndexSet()
    private var synchronizing = false
    private var lastWidth: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page")))
        table.frame = NSRect(x: 0, y: 0, width: 190, height: 0)
        table.autoresizingMask = [.width]
        table.headerView = nil
        table.style = .plain
        table.rowHeight = 146
        hasHorizontalScroller = false
        horizontalScrollElasticity = .none
        table.intercellSpacing = NSSize(width: 0, height: 18)
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Pages: drag to reorder or copy to another document; drop images between pages")
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes(PageTransfer.types)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        documentView = table
    }
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func layout() {
        super.layout()
        let width = contentSize.width
        guard width > 0, abs(lastWidth - width) > 0.5 else { return }
        lastWidth = width
        table.setFrameSize(NSSize(width: width, height: table.frame.height))
        table.tableColumns.first?.width = width
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
        table.enumerateAvailableRowViews { row, _ in row.needsLayout = true }
    }
    private func aspect(for page: PDFPage) -> CGFloat {
        let size = page.bounds(for: .cropBox).size
        let rotated = abs(page.rotation % 180) == 90
        return rotated ? max(size.width, 1) / max(size.height, 1) : max(size.height, 1) / max(size.width, 1)
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let page = pdfView?.document?.page(at: row) else { return 146 }
        return max(1, tableView.bounds.width - 40) * aspect(for: page) + 42
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PageThumbnailRow() }
    func reload() { table.reloadData(); synchronizeSelection() }
    func synchronizeSelection() {
        guard let pdf = pdfView?.document, let page = pdfView?.currentPage else { return }
        let row = pdf.index(for: page)
        guard row < pdf.pageCount, !table.selectedRowIndexes.contains(row) else { return }
        synchronizing = true
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        synchronizing = false
    }
    func numberOfRows(in tableView: NSTableView) -> Int { pdfView?.document?.pageCount ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let page = pdfView?.document?.page(at: row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("thumbnail")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PageThumbnailCell) ?? PageThumbnailCell()
        cell.identifier = id
        cell.setNightMode(nightMode)
        cell.aspect = aspect(for: page)
        // Render for the maximum sidebar width so divider drags only relayout cells.
        cell.imageView?.image = page.thumbnail(of: NSSize(width: 760, height: 760 * cell.aspect), for: .cropBox)
        cell.needsLayout = true
        cell.textField?.stringValue = "\(row + 1)"
        cell.setAccessibilityLabel("Page \(row + 1)")
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !synchronizing, table.selectedRow >= 0, let page = pdfView?.document?.page(at: table.selectedRow) else { return }
        pdfView?.go(to: page)
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        prepareDrag()
        guard let page = pdfView?.document?.page(at: row)?.copy() as? PDFPage else { return nil }
        let pdf = PDFDocument(); pdf.insert(page, at: 0)
        guard let data = pdf.dataRepresentation() else { return nil }
        let item = NSPasteboardItem(); item.setData(data, forType: PageTransfer.pageType)
        item.setData(data, forType: .pdf)
        return item
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        draggedRows = rowIndexes
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedRows = []
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard PageTransfer.supports(info.draggingPasteboard) else { return [] }
        tableView.setDropRow(max(0, row), dropOperation: .above)
        let local = (info.draggingSource as? NSTableView) === table
        return local && !NSEvent.modifierFlags.contains(.option) ? .move : .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        if (info.draggingSource as? NSTableView) === table && !NSEvent.modifierFlags.contains(.option) {
            movePages(draggedRows, row)
            return !draggedRows.isEmpty
        }
        do { insertPages(try PageTransfer.pages(from: info.draggingPasteboard), row); return true }
        catch { NSApp.presentError(error); return false }
    }
}

// Own the cell geometry: AppKit's automatic outline-cell positioning must not
// move a short title toward the center of a wide navigation pane.
final class LeftAlignedOutlineView: NSOutlineView {
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var rect = super.frameOfCell(atColumn: column, row: row)
        guard row >= 0, row < numberOfRows, column == 0 else { return rect }
        rect.origin.x = OutlineLayout.titleX(level: level(forRow: row), width: bounds.width)
        rect.size.width = max(0, bounds.width - rect.minX - 12)
        return rect
    }
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var rect = super.frameOfOutlineCell(atRow: row)
        guard row >= 0, row < numberOfRows else { return rect }
        rect.origin.x = OutlineLayout.disclosureX(level: level(forRow: row), width: bounds.width)
        rect.size.width = 14
        return rect
    }
}

final class OutlineTitleCell: NSTableCellView {
    var title = "" { didSet { setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityLabel(title); needsDisplay = true } }
    override var isFlipped: Bool { true }
    static func cleanTitle(_ title: String?) -> String {
        (title ?? "Untitled").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
    static var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left; paragraph.baseWritingDirection = .leftToRight
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        (title as NSString).draw(with: NSRect(x: 0, y: 7, width: bounds.width, height: max(0, bounds.height - 14)),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: Self.textAttributes)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class DocumentOutline: NSScrollView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let tree = LeftAlignedOutlineView()
    weak var pdfView: PDFView?
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No outline in this PDF")
    private var lastContentWidth: CGFloat = -1
    private weak var loadedDocument: PDFDocument?
    private weak var loadedRoot: PDFOutline?
    private var trackedEntries: [PDFOutline] = []
    private var markers: [OutlineMarker] = []
    private weak var activeEntry: PDFOutline?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true; autohidesScrollers = true
        automaticallyAdjustsContentInsets = false; contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        hasHorizontalScroller = false; horizontalScrollElasticity = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.minWidth = 40; column.resizingMask = .autoresizingMask
        tree.addTableColumn(column); tree.outlineTableColumn = column
        tree.autoresizesOutlineColumn = false
        tree.indentationMarkerFollowsCell = false
        tree.frame = NSRect(x: 0, y: 0, width: 190, height: 0)
        tree.autoresizingMask = [.width]
        tree.style = .plain
        tree.intercellSpacing = .zero
        tree.headerView = nil; tree.rowHeight = 28; tree.indentationPerLevel = 0
        tree.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tree.dataSource = self; tree.delegate = self
        tree.target = self; tree.action = #selector(navigate)
        tree.setAccessibilityLabel("Document outline")
        let menu = NSMenu()
        let collapse = NSMenuItem(title: "Collapse All", action: #selector(collapseAll), keyEquivalent: "")
        collapse.target = self; menu.addItem(collapse)
        let expand = NSMenuItem(title: "Expand All", action: #selector(expandAll), keyEquivalent: "")
        expand.target = self; menu.addItem(expand); tree.menu = menu
        documentView = tree
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .left
        addSubview(emptyLabel); emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layout() {
        super.layout()
        tree.setFrameOrigin(NSPoint(x: 0, y: tree.frame.origin.y))
        contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y))
        let width = contentSize.width
        guard width > 0, abs(width - lastContentWidth) > 0.5 else { return }
        lastContentWidth = width
        tree.setFrameSize(NSSize(width: width, height: tree.frame.height))
        tree.tableColumns.first?.width = width
        // Reflow long titles as the divider moves; never retain a horizontal
        // scroll offset from an earlier, wider outline.
        contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y))
        if tree.numberOfRows > 0 {
            tree.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<tree.numberOfRows))
        }
    }

    private func titleWidth(for item: Any) -> CGFloat {
        return OutlineLayout.titleWidth(level: tree.level(forItem: item), width: tree.bounds.width)
    }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let entry = item as? PDFOutline else { return 28 }
        let bounds = (OutlineTitleCell.cleanTitle(entry.label) as NSString).boundingRect(
            with: NSSize(width: titleWidth(for: item), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: OutlineTitleCell.textAttributes)
        return max(28, ceil(bounds.height) + 14)
    }

    @objc func collapseAll() {
        tree.collapseItem(nil, collapseChildren: true)
        synchronizeSelection(allowExpansion: false)
    }
    @objc func expandAll() { tree.expandItem(nil, expandChildren: true) }
    func reload() {
        let sameDocument = loadedDocument === pdfView?.document && loadedRoot === pdfView?.document?.outlineRoot
        let expanded = sameDocument ? (0..<tree.numberOfRows).compactMap { row -> PDFOutline? in
            guard let item = tree.item(atRow: row) as? PDFOutline, tree.isItemExpanded(item) else { return nil }
            return item
        } : []
        let selected = tree.selectedRow >= 0 ? tree.item(atRow: tree.selectedRow) : nil
        tree.reloadData()
        emptyLabel.isHidden = (pdfView?.document?.outlineRoot?.numberOfChildren ?? 0) > 0
        if sameDocument {
            tree.collapseItem(nil, collapseChildren: true)
            expanded.forEach { tree.expandItem($0) }
        } else if let root = pdfView?.document?.outlineRoot {
            for index in 0..<root.numberOfChildren {
                if let child = root.child(at: index) { tree.expandItem(child) }
            }
        }
        loadedDocument = pdfView?.document
        loadedRoot = pdfView?.document?.outlineRoot
        rebuildTrackingIndex()
        if let selected {
            let row = tree.row(forItem: selected)
            if row >= 0 { tree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
    }
    private func rebuildTrackingIndex() {
        trackedEntries = []; markers = []
        guard let pdf = pdfView?.document, let root = pdf.outlineRoot else { activeEntry = nil; return }
        var pending: [(PDFOutline, Int)] = [(root, -1)]
        var visited = Set<ObjectIdentifier>()
        while let (entry, depth) = pending.popLast() {
            guard visited.insert(ObjectIdentifier(entry)).inserted else { continue }
            if entry !== root,
               let destination = entry.destination ?? (entry.action as? PDFActionGoTo)?.destination,
               let page = destination.page, page.document === pdf {
                let pageIndex = pdf.index(for: page)
                if pageIndex < pdf.pageCount {
                    let point = destination.point
                    let vertical = page.rotation % 180 == 0 ? point.y : point.x
                    let offset = vertical == kPDFDestinationUnspecifiedValue || !vertical.isFinite ? 0 :
                        OutlineTracking.offset(point: point, bounds: page.bounds(for: .cropBox), rotation: page.rotation)
                    markers.append(OutlineMarker(position: OutlinePosition(page: pageIndex, offset: offset), depth: depth, index: trackedEntries.count))
                    trackedEntries.append(entry)
                }
            }
            for index in (0..<entry.numberOfChildren).reversed() {
                if let child = entry.child(at: index) { pending.append((child, depth + 1)) }
            }
        }
        markers = OutlineTracking.sorted(markers)
        if let activeEntry, !trackedEntries.contains(where: { $0 === activeEntry }) { self.activeEntry = nil }
    }

    func synchronizeSelection(reveal: Bool = false, allowExpansion: Bool = true) {
        guard !isHiddenOrHasHiddenAncestor, let pdfView, let pdf = pdfView.document,
              pdfView.bounds.height > 0, pdfView.bounds.width > 0 else { return }
        // Read near the top of the viewport, with a little lead-in for the
        // heading currently being read rather than the page's center.
        let rect = pdfView.visibleRect
        let inset = min(72, rect.height * 0.15)
        let anchor = NSPoint(x: rect.midX, y: pdfView.isFlipped ? rect.minY + inset : rect.maxY - inset)
        guard let page = pdfView.page(for: anchor, nearest: true), page.document === pdf else { return }
        let position = OutlinePosition(page: pdf.index(for: page), offset: OutlineTracking.offset(
            point: pdfView.convert(anchor, to: page), bounds: page.bounds(for: .cropBox), rotation: page.rotation))
        synchronizeSelection(at: position, reveal: reveal, allowExpansion: allowExpansion)
    }

    // Selection changes never invoke navigate(): scrolling the outline cannot
    // feed back into PDF navigation or steal keyboard focus from the reader.
    func synchronizeSelection(at position: OutlinePosition, reveal: Bool = false, allowExpansion: Bool = true) {
        guard let index = OutlineTracking.active(in: markers, at: position) else {
            activeEntry = nil; tree.deselectAll(nil); return
        }
        let entry = trackedEntries[index]
        let changed = activeEntry !== entry
        activeEntry = entry
        if allowExpansion && (changed || reveal) {
            var parents: [PDFOutline] = []
            var parent = entry.parent
            while let item = parent, item !== loadedRoot { parents.append(item); parent = item.parent }
            for item in parents.reversed() { tree.expandItem(item) }
        }
        // Respect a manual collapse while the reader stays in this section.
        // A visible ancestor carries the highlight until the next section.
        var visible: PDFOutline? = entry
        while let item = visible, tree.row(forItem: item) < 0 { visible = item.parent }
        guard let visible else { return }
        let row = tree.row(forItem: visible)
        guard row >= 0 else { return }
        if tree.selectedRow != row { tree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        if changed || reveal { tree.scrollRowToVisible(row) }
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.synchronizeSelection(allowExpansion: false) }
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.synchronizeSelection(allowExpansion: false) }
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { SidebarSelectionRow() }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? PDFOutline) ?? pdfView?.document?.outlineRoot)?.numberOfChildren ?? 0
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? PDFOutline) ?? pdfView!.document!.outlineRoot!).child(at: index)!
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? PDFOutline)?.numberOfChildren ?? 0 > 0
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let entry = item as? PDFOutline else { return nil }
        let id = NSUserInterfaceItemIdentifier("outlineTitle")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? OutlineTitleCell) ?? OutlineTitleCell()
        cell.identifier = id
        cell.title = OutlineTitleCell.cleanTitle(entry.label)
        cell.toolTip = entry.label
        return cell
    }
    @objc private func navigate() {
        guard tree.clickedRow >= 0, let entry = tree.item(atRow: tree.clickedRow) as? PDFOutline,
              let destination = entry.destination ?? (entry.action as? PDFActionGoTo)?.destination,
              destination.page?.document === pdfView?.document else { return }
        pdfView?.go(to: destination)
    }
}
