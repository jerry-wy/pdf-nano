import AppKit
import PDFKit

func runSmokeTests() throws {
    func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
        guard value() else { throw NSError(domain: "SmokeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS: \(name)")
    }
    guard let url = Bundle.main.url(forResource: "Welcome", withExtension: "pdf"), let pdf = PDFDocument(url: url) else {
        throw NSError(domain: "SmokeTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bundled sample PDF missing"])
    }
    try check(pdf.pageCount == 3, "Bundled PDF opens with three pages")
    let matches = pdf.findString("attention", withOptions: .caseInsensitive)
    try check(!matches.isEmpty, "PDF text search finds results")
    let marks = PDFOperations.highlight(matches[0])
    try check(!marks.isEmpty, "Text selection produces native highlights")
    for (page, annotation) in marks { page.addAnnotation(annotation) }
    let note = PDFAnnotation(bounds: CGRect(x: 100, y: 200, width: 24, height: 24), forType: .text, withProperties: nil)
    note.contents = "A saved thought — 日本語"
    pdf.page(at: 0)!.addAnnotation(note)
    let document = NanoDocument(); document.pdf = pdf
    let exported = try document.data(ofType: "com.adobe.pdf")
    let reopened = NanoDocument(); try reopened.read(from: exported, ofType: "com.adobe.pdf")
    try check(reopened.pdf.page(at: 0)!.annotations.contains { $0.contents == note.contents }, "Saved Unicode note survives PDF round trip")
    try check(reopened.pdf.page(at: 0)!.annotations.contains { $0.type == "Highlight" }, "Saved highlight survives PDF round trip")
    let image = NSImage(size: NSSize(width: 300, height: 400))
    image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 300, height: 400).fill(); image.unlockFocus()
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-nano-scan-\(UUID().uuidString).tiff")
    try image.tiffRepresentation!.write(to: temp)
    defer { try? FileManager.default.removeItem(at: temp) }
    let scan = try PDFOperations.scan([temp, temp])
    try check(scan.pageCount == 2 && scan.dataRepresentation() != nil, "Two images become an exportable multipage PDF")
    let scannedPage = scan.page(at: 0)!
    let imageNote = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24), forType: .text, withProperties: nil)
    imageNote.contents = "Keep my note"; scannedPage.addAnnotation(imageNote)
    let recognized = try PDFOperations.recognizedPage(scannedPage, lines: [RecognizedLine(text: "Selectable OCR text", bounds: CGRect(x: 0.1, y: 0.6, width: 0.7, height: 0.08))])
    try check(recognized.string?.contains("Selectable OCR text") == true,
              "OCR creates native selectable PDF text on an image page")
    let textRegion = CGRect(x: 0, y: 200, width: 300, height: 150)
    try check(recognized.selection(for: textRegion)?.string?.contains("Selectable") == true,
              "OCR text can be selected at the image's page coordinates")
    try check(recognized.annotations.contains { $0.contents == "Keep my note" }, "OCR preserves editable annotations")
    let ocrDocument = PDFDocument(); ocrDocument.insert(recognized, at: 0)
    let ocrSaved = PDFDocument(data: ocrDocument.dataRepresentation()!)!
    try check(!ocrSaved.findString("Selectable", withOptions: []).isEmpty, "OCR text remains searchable after saving")
    for rotation in [90, 180, 270] {
        let rotated = scannedPage.copy() as! PDFPage; rotated.rotation = rotation
        rotated.setBounds(CGRect(x: 20, y: 30, width: 240, height: 340), for: .cropBox)
        let uprightLine = RecognizedLine(text: "Rotated OCR", bounds: CGRect(x: 0.1, y: 0.5, width: 0.7, height: 0.08))
        let rotatedResult = try PDFOperations.recognizedPage(rotated, lines: [uprightLine])
        let geometry = PDFOperations.ocrTransform(for: rotated)
        let selectionRect = CGRect(x: uprightLine.bounds.minX * geometry.size.width, y: uprightLine.bounds.minY * geometry.size.height,
                                   width: uprightLine.bounds.width * geometry.size.width, height: uprightLine.bounds.height * geometry.size.height).applying(geometry.transform).insetBy(dx: -2, dy: -2)
        try check(rotatedResult.rotation == rotation && rotatedResult.selection(for: selectionRect)?.string?.contains("Rotated") == true,
                  "OCR coordinates support rotation \(rotation) with a cropped origin")
    }
    var rejected = false
    do { try reopened.read(from: Data("not a PDF".utf8), ofType: "com.adobe.pdf") }
    catch { rejected = true }
    try check(rejected, "Invalid PDF rejected")
    // Exercise real document windows, including a system preference that disables
    // automatic grouping, so tabs do not depend on the user's desktop settings.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let automaticTabbing = NSWindow.allowsAutomaticWindowTabbing
    NSWindow.allowsAutomaticWindowTabbing = false
    defer { NSWindow.allowsAutomaticWindowTabbing = automaticTabbing }
    let first = NanoDocument()
    let second = NanoDocument()
    try first.read(from: exported, ofType: "com.adobe.pdf")
    try second.read(from: exported, ofType: "com.adobe.pdf")
    first.makeWindowControllers(); second.makeWindowControllers()
    defer { first.close(); second.close() }
    first.showWindows(); second.showWindows()
    let firstWindow = first.windowControllers[0].window!
    let secondWindow = second.windowControllers[0].window!
    try check(firstWindow.tabbedWindows?.count == 2 && firstWindow.tabbedWindows?.contains(secondWindow) == true,
              "Two PDFs share a tab group with automatic tabbing disabled")
    first.showWindows()
    try check(firstWindow.tabbedWindows?.count == 2, "Showing an existing PDF keeps its tab group")
    second.pdf.page(at: 0)!.addAnnotation(PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 24, height: 24), forType: .text, withProperties: nil))
    try check(first.pdf.page(at: 0)!.annotations.count + 1 == second.pdf.page(at: 0)!.annotations.count,
              "Tabbed PDFs keep independent document contents")
    let reader = second.windowControllers[0] as! ReaderController
    second.undoManager?.removeAllActions()
    second.undoManager?.groupsByEvent = false
    let layout = ReaderColumnsView(frame: NSRect(x: 0, y: 0, width: 1100, height: 600))
    let navigationPane = NSView(), readingPane = NSView(), notesPane = NSView()
    let savedNavigation = UserDefaults.standard.object(forKey: "PDFNanoNavigationWidth")
    let savedNotes = UserDefaults.standard.object(forKey: "PDFNanoAgentWidth")
    defer {
        UserDefaults.standard.set(savedNavigation, forKey: "PDFNanoNavigationWidth")
        UserDefaults.standard.set(savedNotes, forKey: "PDFNanoAgentWidth")
    }
    layout.configure(navigation: navigationPane, reading: readingPane, agent: notesPane)
    layout.navigationHidden = false; layout.agentHidden = false
    layout.resizeAgent(to: 280); layout.resizeNavigation(to: 180); layout.layoutSubtreeIfNeeded()
    let originalReadingWidth = readingPane.frame.width
    layout.resizeNavigation(to: 250); layout.layoutSubtreeIfNeeded()
    try check(abs(navigationPane.frame.width - 250) < 1 && readingPane.frame.width < originalReadingWidth,
              "Dragging navigation divider changes actual pane widths")
    layout.resizeAgent(to: 350); layout.layoutSubtreeIfNeeded()
    try check(abs(notesPane.frame.width - 350) < 1 && readingPane.frame.maxX < notesPane.frame.minX,
              "Dragging notes divider resizes the notes pane without overlap")
    layout.frame.size.width = 720; layout.needsLayout = true; layout.layoutSubtreeIfNeeded()
    try check(readingPane.frame.width >= 260 && navigationPane.frame.width >= 150 && notesPane.frame.width >= 240,
              "Narrow windows retain usable reading and sidebar widths")
    let sourcePage = first.pdf.page(at: 0)!
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let sourceReader = first.windowControllers[0] as! ReaderController
    let writer = sourceReader.thumbnails.tableView(sourceReader.thumbnails.table, pasteboardWriterForRow: 0)!
    pasteboard.writeObjects([writer])
    let copiedPages = try PageTransfer.pages(from: pasteboard)
    second.undoManager?.beginUndoGrouping()
    reader.insert(pages: copiedPages, at: 1)
    second.undoManager?.endUndoGrouping()
    try check(second.pdf.pageCount == 4 && first.pdf.pageCount == 3 && second.isDocumentEdited,
              "Cross-document page drop inserts a copy and marks destination edited")
    try check(second.pdf.page(at: 1) !== sourcePage && second.pdf.page(at: 1)!.string == sourcePage.string,
              "Copied page keeps text without sharing source ownership")
    second.undoManager?.undo()
    try check(second.pdf.pageCount == 3, "Undo removes inserted pages")
    second.undoManager?.redo()
    try check(second.pdf.pageCount == 4, "Redo restores inserted pages")
    let beforeMove = second.pdf.page(at: 0)!
    second.undoManager?.beginUndoGrouping()
    reader.move(pages: IndexSet([0, 1]), to: 4)
    second.undoManager?.endUndoGrouping()
    try check(second.pdf.page(at: 2) === beforeMove, "Multiple selected pages move together in order")
    second.undoManager?.undo()
    try check(second.pdf.page(at: 0) === beforeMove, "Undo restores page order")
    pasteboard.clearContents(); pasteboard.writeObjects([temp as NSURL])
    let imagePages = try PageTransfer.pages(from: pasteboard)
    try check(imagePages.count == 1 && imagePages[0].bounds(for: .mediaBox).width > 0,
              "Dropped image becomes a PDF page")
    let empty = NanoDocument(); empty.makeWindowControllers()
    defer { empty.close() }
    let emptyReader = empty.windowControllers[0] as! ReaderController
    emptyReader.insert(pages: imagePages, at: 0)
    try check(empty.pdf.pageCount == 1 && emptyReader.pdfView.document === empty.pdf,
              "Image drop into empty tab builds the reader")
    let root = PDFOutline(); let chapter = PDFOutline(); let section = PDFOutline()
    chapter.label = "Chapter 1"; section.label = "Section 1.1"
    chapter.destination = PDFDestination(page: beforeMove, at: .zero)
    section.destination = PDFDestination(page: beforeMove, at: .zero)
    chapter.insertChild(section, at: 0); root.insertChild(chapter, at: 0)
    second.pdf.outlineRoot = root; reader.outline.reload()
    try check(reader.outline.tree.numberOfRows == 2, "Outline displays chapter and section hierarchy")
    let sectionPosition = OutlinePosition(page: second.pdf.index(for: beforeMove), offset: 1)
    reader.outline.synchronizeSelection(at: sectionPosition)
    try check((reader.outline.tree.item(atRow: reader.outline.tree.selectedRow) as? PDFOutline) === section,
              "Reading position selects the deepest matching section")
    reader.outline.tree.collapseItem(nil, collapseChildren: true)
    reader.outline.synchronizeSelection(at: sectionPosition)
    try check(reader.outline.tree.numberOfRows == 1 && (reader.outline.tree.item(atRow: reader.outline.tree.selectedRow) as? PDFOutline) === chapter,
              "Following the same section respects manual Collapse all and highlights its visible ancestor")
    reader.outline.synchronizeSelection(at: sectionPosition, reveal: true)
    try check(reader.outline.tree.numberOfRows == 2 && (reader.outline.tree.item(atRow: reader.outline.tree.selectedRow) as? PDFOutline) === section,
              "Reopening Outline reveals the current section")
    let originalOutlineWidth = reader.outline.tree.frame.width
    for width: CGFloat in [180, 320] {
        reader.outline.tree.frame.size.width = width
        let chapterFrame = reader.outline.tree.frameOfCell(atColumn: 0, row: 0)
        let sectionFrame = reader.outline.tree.frameOfCell(atColumn: 0, row: 1)
        try check(chapterFrame.minX == 22 && sectionFrame.minX == 34,
                  "Outline roots stay left-aligned and children remain indented as the sidebar resizes")
    }
    let deep = DocumentOutline()
    let deepPDF = PDFDocument(); let deepRoot = PDFOutline()
    var parent = deepRoot
    for depth in 0..<8 {
        let entry = PDFOutline(); entry.label = "Depth \(depth)"
        parent.insertChild(entry, at: 0); parent = entry
    }
    deepPDF.outlineRoot = deepRoot
    let deepView = PDFView(); deepView.document = deepPDF
    deep.pdfView = deepView; deep.reload(); deep.tree.expandItem(nil, expandChildren: true)
    try check(deep.tree.numberOfRows == 8, "Deep outline fixture exposes eight levels")
    for row in 0..<deep.tree.numberOfRows {
        try check(deep.tree.frameOfCell(atColumn: 0, row: row).minX == OutlineLayout.titleX(level: row, width: deep.tree.bounds.width)
                  && deep.tree.frameOfOutlineCell(atRow: row).minX == OutlineLayout.disclosureX(level: row, width: deep.tree.bounds.width),
                  "Deep outline levels cannot accumulate horizontal whitespace")
    }
    deep.collapseAll()
    try check(deep.tree.numberOfRows == 1, "Collapse All leaves only the root headings visible")
    deep.reload()
    try check(deep.tree.numberOfRows == 1, "Reloading does not reopen collapsed sections")
    deep.expandAll()
    try check(deep.tree.numberOfRows == 8, "Expand All restores deeply nested outline entries")
    if let container = reader.outline.superview {
        container.layoutSubtreeIfNeeded()
        try check(abs(reader.outline.frame.minX) < 1 && abs(reader.outline.frame.width - container.bounds.width) < 1,
                  "Outline container fills the navigation pane from its left edge")
    }
    reader.outline.tree.frame.size.width = originalOutlineWidth
    try check(OutlineTitleCell.cleanTitle("   Chapter\n    continuation") == "Chapter\ncontinuation",
              "Embedded leading whitespace cannot center outline titles")
    let saved = PDFDocument(data: try second.data(ofType: "com.adobe.pdf"))!
    try check(saved.pageCount == 4 && saved.outlineRoot?.child(at: 0)?.child(at: 0)?.label == "Section 1.1",
              "Inserted pages and outline survive saving")
    reader.pdfView.layoutSubtreeIfNeeded()
    let initialScale = reader.pdfView.scaleFactor
    reader.zoomIn()
    try check(!reader.pdfView.autoScales && reader.pdfView.scaleFactor > initialScale, "Zoom in increases scale and leaves fit mode")
    reader.zoomOut()
    try check(reader.pdfView.scaleFactor < initialScale * 1.2, "Zoom out decreases scale")
    let scaleBeforeShortcut = reader.pdfView.scaleFactor
    let zoomEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: 0, windowNumber: secondWindow.windowNumber, context: nil,
                                    characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24)!
    try check(secondWindow.performKeyEquivalent(with: zoomEvent) && reader.pdfView.scaleFactor > scaleBeforeShortcut,
              "Cmd equals triggers zoom without Shift")
    reader.fitPage()
    try check(reader.pdfView.autoScales, "Fit page restores automatic scaling")
    let toolbarIDs = reader.toolbarDefaultItemIdentifiers(secondWindow.toolbar!).map(\.rawValue)
    try check(toolbarIDs.last == "search" && !toolbarIDs.contains("save") && !toolbarIDs.contains("open") && !toolbarIDs.contains("more") && !toolbarIDs.contains("night"),
              "Minimal toolbar ends with Find and leaves secondary controls off the toolbar")
    try check(reader.columns.handleWidth >= 8,
              "Column dividers provide an explicit drag target")
    reader.setTool(.highlight); reader.setTool(.select)
    try check(reader.pdfView.tool == .select, "Annotation mode can return to normal text selection")
    let linkedHighlight = beforeMove.annotations.first { $0.type == "Highlight" }!
    let previousNote = linkedHighlight.contents ?? ""
    second.undoManager?.beginUndoGrouping()
    reader.updateNote(linkedHighlight, text: "A linked reflection — 日本語")
    second.undoManager?.endUndoGrouping()
    reader.revealNote(linkedHighlight, focus: false)
    try check(reader.readingSurface.selectedNote?.annotation === linkedHighlight && reader.readingSurface.editor!.string == "A linked reflection — 日本語",
              "Selecting a highlight opens its linked note beside the annotation")
    second.undoManager?.undo()
    try check((linkedHighlight.contents ?? "") == previousNote, "Undo restores previous highlight note")
    second.undoManager?.redo()
    try check(linkedHighlight.contents == "A linked reflection — 日本語", "Redo restores highlight note edit")
    let linkedPopup = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 180, height: 100), forType: .popup, withProperties: nil)
    beforeMove.addAnnotation(linkedPopup); linkedHighlight.popup = linkedPopup
    second.undoManager?.beginUndoGrouping()
    reader.deleteNote(linkedHighlight)
    second.undoManager?.endUndoGrouping()
    try check(linkedHighlight.contents == nil && linkedHighlight.popup == nil && linkedHighlight.page === beforeMove
              && !beforeMove.annotations.contains { $0 === linkedPopup }
              && !reader.readingSurface.entries.contains { $0.annotation === linkedHighlight },
              "Deleting a highlight note removes its contents and popup while preserving the highlight")
    let afterDelete = PDFDocument(data: try second.data(ofType: "com.adobe.pdf"))!
    let savedHighlight = afterDelete.page(at: 0)!.annotations.first { $0.type == "Highlight" && $0.bounds == linkedHighlight.bounds }
    try check(savedHighlight != nil && savedHighlight?.contents?.isEmpty != false && savedHighlight?.popup == nil,
              "Deleted highlight notes stay deleted after PDF saving")
    second.undoManager?.undo()
    try check(linkedHighlight.contents == "A linked reflection — 日本語" && linkedHighlight.popup === linkedPopup,
              "Undo restores the deleted highlight note and its popup")
    second.undoManager?.redo()
    try check(linkedHighlight.contents == nil && linkedHighlight.popup == nil, "Redo deletes the highlight note again")
    second.undoManager?.undo()
    let countBeforeNote = beforeMove.annotations.count
    second.undoManager?.beginUndoGrouping()
    reader.note(on: beforeMove, at: CGPoint(x: 50, y: 100))
    second.undoManager?.endUndoGrouping()
    let standalone = reader.readingSurface.selectedNote!.annotation
    try check(beforeMove.annotations.count == countBeforeNote + 1 && standalone.type == "Text" && reader.pdfView.tool == .select,
              "A standalone page note creates a page annotation without a modal dialog")
    try check(reader.readingSurface.editor?.isEditable == true && reader.readingSurface.editor?.enclosingScrollView?.superview?.frame.width == 260,
              "New notes have an editable, explicitly sized popover card")
    reader.readingSurface.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: NSPopover()))
    try check(reader.readingSurface.selectedNote?.annotation === standalone,
              "An old popover closing cannot clear the current note editor")
    reader.revealNote(standalone, focus: false)
    try check(reader.readingSurface.selectedNote == nil, "A second note click dismisses even a pending presentation")
    reader.revealNote(standalone, focus: true)
    try check(reader.readingSurface.selectedNote?.annotation === standalone && reader.readingSurface.editor != nil,
              "A dismissed note can immediately reopen for editing")
    second.undoManager?.beginUndoGrouping()
    reader.readingSurface.editor!.string = "Independent page note"
    reader.updateNote(standalone, text: reader.readingSurface.editor!.string)
    second.undoManager?.endUndoGrouping()
    try check(standalone.contents == "Independent page note", "Popover typing updates native annotation contents")
    try check(reader.readingSurface.entries.contains { $0.annotation === standalone && $0.page === beforeMove },
              "Page notes retain their PDF page association")
    let notesRoundTrip = PDFDocument(data: try second.data(ofType: "com.adobe.pdf"))!
    try check(notesRoundTrip.page(at: 0)!.annotations.contains { $0.type == "Highlight" && $0.contents == "A linked reflection — 日本語" }
              && notesRoundTrip.page(at: 0)!.annotations.contains { $0.type == "Text" && $0.contents == "Independent page note" },
              "Linked and standalone page notes survive PDF saving")
    try check(reader.columns.agentHidden, "Creating a page note does not open the Agent panel")
    reader.toggleAgent()
    try check(!reader.columns.agentHidden, "Agent opens independently of notes")
    reader.toggleAgent()
    try check(reader.columns.agentHidden, "Clicking Agent again closes the panel")
    reader.readingSurface.layoutSubtreeIfNeeded()
    try check(reader.pdfView.frame == reader.readingSurface.bounds, "Note popovers reserve no page display area")
    if let selection = beforeMove.selection(for: beforeMove.bounds(for: .cropBox)), selection.string?.isEmpty == false {
        let count = beforeMove.annotations.filter { $0.type == "Highlight" }.count
        reader.pdfView.setCurrentSelection(selection, animate: false)
        second.undoManager?.beginUndoGrouping()
        reader.pdfView.highlightSelectedText()
        second.undoManager?.endUndoGrouping()
        try check(beforeMove.annotations.filter { $0.type == "Highlight" }.count > count,
                  "Context-menu Highlight annotates selected text")
        second.undoManager?.undo()
        try check(beforeMove.annotations.filter { $0.type == "Highlight" }.count == count,
                  "Context-menu highlighting supports undo")
    }
    let oldOCRPage = second.pdf.page(at: 1)!
    let ocrBookmark = PDFOutline(); ocrBookmark.label = "OCR target"
    ocrBookmark.destination = PDFDestination(page: oldOCRPage, at: CGPoint(x: 40, y: 100))
    second.pdf.outlineRoot!.insertChild(ocrBookmark, at: second.pdf.outlineRoot!.numberOfChildren)
    second.undoManager?.beginUndoGrouping()
    reader.replacePage(oldOCRPage, with: recognized)
    second.undoManager?.endUndoGrouping()
    try check(second.pdf.page(at: 1) === recognized && ocrBookmark.destination?.page === recognized,
              "OCR page replacement keeps bookmark destinations attached")
    second.undoManager?.undo()
    try check(second.pdf.page(at: 1) === oldOCRPage && ocrBookmark.destination?.page === oldOCRPage,
              "Undo restores the original page and its bookmark")
    try check(reader.thumbnails.table.intercellSpacing.height >= 16, "Thumbnails have explicit vertical spacing")
    reader.revealNote(linkedHighlight, focus: false)
    try check(reader.pdfView.currentSelection?.string?.isEmpty == false,
              "Selecting a highlight's note emphasizes its passage on the page")
    let keyWindow = secondWindow.windowNumber
    func arrow(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: keyWindow,
                        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    reader.pdfView.go(to: beforeMove)
    try check(reader.pdfView.handleReadingKey(arrow(124)) && reader.pdfView.currentPage === second.pdf.page(at: 1),
              "Right arrow navigates to next page")
    try check(reader.pdfView.handleReadingKey(arrow(123)) && reader.pdfView.currentPage === beforeMove,
              "Left arrow navigates to previous page")
    reader.pdfView.autoScales = false; reader.pdfView.scaleFactor = 2
    reader.pdfView.layoutSubtreeIfNeeded()
    reader.pdfView.go(to: beforeMove)
    if let clip = reader.pdfView.documentView?.enclosingScrollView?.contentView {
        let y = clip.bounds.origin.y
        try check(reader.pdfView.handleReadingKey(arrow(125)) && clip.bounds.origin.y != y,
                  "Down arrow scrolls the document")
        let afterDown = clip.bounds.origin.y
        try check(reader.pdfView.handleReadingKey(arrow(126)) && clip.bounds.origin.y != afterDown,
                  "Up arrow scrolls in the opposite direction")
    } else { try check(false, "Reader exposes a scrollable document") }
    second.close()
    try check(firstWindow.isVisible && (firstWindow.tabbedWindows?.count ?? 1) == 1,
              "Closing one tab keeps the other PDF open")
    print("Native PDF smoke tests complete.")
}
