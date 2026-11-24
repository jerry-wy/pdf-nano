import AppKit
import PDFKit

// Quiet hover and selection feedback shared by the toolbar and sidebar tabs.
class ReaderToolbarButton: NSButton {
    private var hovering = false
    private var hoverArea: NSTrackingArea?
    override var state: NSControl.StateValue { didSet { updateTint(); needsDisplay = true } }
    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    private func updateTint() { contentTintColor = state == .on ? .controlAccentColor : .secondaryLabelColor }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateTint(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if state == .on || hovering || cell?.isHighlighted == true {
            let fill = state == .on ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.labelColor.withAlphaComponent(0.06)
            fill.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
}

// Momentary actions share one padded drawing area for their background, icon
// and text. They deliberately do not use the native cell's bezel/title drawing.
final class ReaderActionButton: NSButton {
    private var hovering = false
    private var suppressFeedback = false
    private var hoverArea: NSTrackingArea?
    private let iconSize: CGFloat = 14
    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var image: NSImage? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var imagePosition: NSControl.ImagePosition { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var font: NSFont? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setButtonType(.momentaryChange); isBordered = false
        font = .systemFont(ofSize: 11, weight: .medium)
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    private var showsIcon: Bool { image != nil && imagePosition != .noImage }
    private var showsTitle: Bool { !title.isEmpty && imagePosition != .imageOnly }
    private var text: NSAttributedString {
        NSAttributedString(string: showsTitle ? title : "", attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isEnabled ? NSColor.labelColor : .disabledControlTextColor
        ])
    }
    override var intrinsicContentSize: NSSize {
        let gap: CGFloat = showsIcon && showsTitle ? 6 : 0
        return NSSize(width: max(32, ceil(text.size().width) + (showsIcon ? iconSize : 0) + gap + (showsTitle ? 20 : 16)), height: 28)
    }
    private var pointerInside: Bool {
        guard let window else { return false }
        return visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        if !pointerInside { hovering = false; suppressFeedback = false }
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) {
        hovering = pointerInside && !suppressFeedback; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false; suppressFeedback = false; needsDisplay = true
    }
    private func finishInteraction() {
        // Menu tracking can swallow mouseExited and can re-highlight the cell
        // after its action returns. Finish at both action and tracking boundaries.
        hovering = false; suppressFeedback = pointerInside
        state = .off; highlight(false); needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        suppressFeedback = false
        defer { finishInteraction() }
        super.mouseDown(with: event)
    }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        defer { finishInteraction() }
        return super.sendAction(action, to: target)
    }
    override func performClick(_ sender: Any?) {
        suppressFeedback = false
        defer { finishInteraction() }
        super.performClick(sender)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && !suppressFeedback && (hovering || cell?.isHighlighted == true) {
            NSColor.labelColor.withAlphaComponent(cell?.isHighlighted == true ? 0.12 : 0.06).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        let label = text, size = label.size()
        let gap: CGFloat = showsIcon && showsTitle ? 6 : 0
        let width = size.width + (showsIcon ? iconSize : 0) + gap
        var x = bounds.midX - width / 2
        if showsIcon, let image {
            let color: NSColor = isEnabled ? .secondaryLabelColor : .disabledControlTextColor
            let icon = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) ?? image
            icon.draw(in: NSRect(x: x, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += iconSize + gap
        }
        if showsTitle { label.draw(in: NSRect(x: x, y: bounds.midY - size.height / 2, width: ceil(size.width), height: ceil(size.height))) }
    }
}

final class ToolbarGroupView: NSStackView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 10
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAppearance() }
    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.035).cgColor }
    }
}

// Both sidebars use the same dimensions, selection fill, and button behavior.
final class SidebarTabs: NSView {
    var selectedIndex = 0 { didSet { updateSelection() } }
    var isEnabled = true { didSet { buttons.forEach { $0.isEnabled = isEnabled } } }
    var onChange: (Int) -> Void = { _ in }
    private var buttons: [ReaderToolbarButton] = []
    init(labels: [String] = ["Pages", "Outline"]) {
        super.init(frame: .zero)
        let row = ToolbarGroupView(); row.spacing = 2; row.distribution = .fillEqually; row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        for (index, title) in labels.enumerated() {
            let button = ReaderToolbarButton(title: title, target: self, action: #selector(selectTab(_:)))
            button.tag = index; button.isBordered = false; button.setButtonType(.pushOnPushOff)
            button.font = .systemFont(ofSize: 11, weight: .medium); button.setAccessibilityLabel(title)
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            row.addArrangedSubview(button); buttons.append(button)
        }
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46), row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor), row.heightAnchor.constraint(equalToConstant: 32)
        ])
        updateSelection()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            button.state = index == selectedIndex ? .on : .off
            button.setAccessibilityValue(index == selectedIndex ? "Selected" : "")
        }
    }
    @objc private func selectTab(_ sender: NSButton) { selectedIndex = sender.tag; onChange(selectedIndex) }
}

class SidebarSelectionRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 7, yRadius: 7).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

final class AnnotationToolButton: ReaderToolbarButton {
    var deactivate: () -> Void = {}
    override func mouseDown(with event: NSEvent) {
        if event.clickCount > 1 { deactivate(); return }
        super.mouseDown(with: event)
    }
}

final class NoteEditor: NSTextView {
    var onUndo: ((Bool) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z", let onUndo {
            onUndo(event.modifierFlags.contains(.shift)); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && isEditable {
            ("Write a thought…" as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor])
        }
    }
}

struct ReaderNote {
    let page: PDFPage
    let annotation: PDFAnnotation
    let pageNumber: Int
    var quote: String {
        guard annotation.type == "Highlight" else { return "" }
        return page.selection(for: annotation.bounds)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Highlighted passage"
    }
}

final class ColumnResizeHandle: NSView {
    var onDrag: (CGFloat) -> Void = { _ in }
    var onBegin: () -> Void = {}
    var onReset: () -> Void = {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSRect(x: bounds.midX, y: 0, width: 1, height: bounds.height).fill()
        NSColor.tertiaryLabelColor.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 1, y: bounds.midY - 14, width: 2, height: 28), xRadius: 1, yRadius: 1).fill()
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 { onReset(); return }
        onBegin()
        let start = event.locationInWindow.x
        NSCursor.resizeLeftRight.push()
        defer { NSCursor.pop() }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            onDrag(next.locationInWindow.x - start)
        }
    }
}

// Explicit column frames avoid intrinsic sizing constraints from the PDF view
// and stack views taking precedence over the user's divider drag.
final class ReaderColumnsView: NSView {
    private(set) var navigationWidth: CGFloat = 200
    private(set) var agentWidth: CGFloat = 290
    var navigationHidden = true { didSet { if oldValue != navigationHidden { animateColumns() } } }
    var agentHidden = true { didSet { if oldValue != agentHidden { animateColumns() } } }
    private let leftHandle = ColumnResizeHandle()
    private let rightHandle = ColumnResizeHandle()
    private weak var navigation: NSView?
    private weak var reading: NSView?
    private weak var agent: NSView?
    private var leftDragStart: CGFloat?
    private var rightDragStart: CGFloat?
    let handleWidth: CGFloat = 9

    private var navigationProgress: CGFloat = 0
    private var agentProgress: CGFloat = 0
    private var transition: Timer?

    private func animateColumns() {
        transition?.invalidate()
        let startLeft = navigationProgress, startRight = agentProgress
        let endLeft: CGFloat = navigationHidden ? 0 : 1
        let endRight: CGFloat = agentHidden ? 0 : 1
        let start = ProcessInfo.processInfo.systemUptime
        let duration = window == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : 0.30
        let pdf = (reading as? ReadingSurface)?.pdfView
        let startingScale = pdf?.scaleFactor ?? 1
        pdf?.autoScales = false
        if duration == 0 {
            navigationProgress = endLeft; agentProgress = endRight
            needsLayout = true; layoutSubtreeIfNeeded(); pdf?.autoScales = true; return
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / duration)
            let eased = CGFloat(t * t * (3 - 2 * t))
            self.navigationProgress = startLeft + (endLeft - startLeft) * eased
            self.agentProgress = startRight + (endRight - startRight) * eased
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            if let pdf = (self.reading as? ReadingSurface)?.pdfView {
                let fit = pdf.scaleFactorForSizeToFit
                if fit > 0 { pdf.scaleFactor = startingScale + (fit - startingScale) * eased }
            }
            if t >= 1 {
                timer.invalidate(); self.transition = nil
                ((self.reading as? ReadingSurface)?.pdfView)?.autoScales = true
            }
        }
        transition = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    deinit { transition?.invalidate() }

    func configure(navigation: NSView, reading: NSView, agent: NSView) {
        wantsLayer = true; layer?.masksToBounds = true
        self.navigation = navigation; self.reading = reading; self.agent = agent
        let savedLeft = UserDefaults.standard.double(forKey: "PDFNanoNavigationWidth")
        let savedRight = UserDefaults.standard.double(forKey: "PDFNanoAgentWidth")
        if savedLeft > 0 { navigationWidth = CGFloat(savedLeft) }
        if savedRight > 0 { agentWidth = CGFloat(savedRight) }
        for view in [navigation, reading, agent, leftHandle, rightHandle] {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = []
            addSubview(view)
        }
        leftHandle.onBegin = { [weak self] in self?.leftDragStart = self?.navigation?.frame.width }
        rightHandle.onBegin = { [weak self] in self?.rightDragStart = self?.agent?.frame.width }
        leftHandle.onDrag = { [weak self] delta in
            guard let self else { return }
            if self.leftDragStart == nil { self.leftDragStart = self.navigationWidth }
            self.resizeNavigation(to: self.leftDragStart! + delta)
            self.layoutSubtreeIfNeeded()
        }
        rightHandle.onDrag = { [weak self] delta in
            guard let self else { return }
            if self.rightDragStart == nil { self.rightDragStart = self.agentWidth }
            self.resizeAgent(to: self.rightDragStart! - delta)
            self.layoutSubtreeIfNeeded()
        }
        leftHandle.onReset = { [weak self] in self?.resizeNavigation(to: 200) }
        rightHandle.onReset = { [weak self] in self?.resizeAgent(to: 290) }
    }
    func resizeNavigation(to width: CGFloat) {
        let other = agentHidden ? 0 : agentWidth + handleWidth
        let maximum = max(150, min(380, bounds.width - other - handleWidth - 260))
        ((reading as? ReadingSurface)?.pdfView)?.autoScales = true
        navigationWidth = min(max(width, 150), maximum)
        UserDefaults.standard.set(Double(navigationWidth), forKey: "PDFNanoNavigationWidth")
        needsLayout = true
    }
    func resizeAgent(to width: CGFloat) {
        let other = navigationHidden ? 0 : navigationWidth + handleWidth
        let maximum = max(240, min(480, bounds.width - other - handleWidth - 260))
        ((reading as? ReadingSurface)?.pdfView)?.autoScales = true
        agentWidth = min(max(width, 240), maximum)
        UserDefaults.standard.set(Double(agentWidth), forKey: "PDFNanoAgentWidth")
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let available = max(bounds.width, 0)
        var targetLeft = min(max(navigationWidth, 150), 380)
        var targetRight = min(max(agentWidth, 240), 480)
        let hasLeft = !navigationHidden || navigationProgress > 0
        let hasRight = !agentHidden || agentProgress > 0
        let handles: CGFloat = (hasLeft ? handleWidth : 0) + (hasRight ? handleWidth : 0)
        var excess = max(0, (hasLeft ? targetLeft : 0) + (hasRight ? targetRight : 0) + handles + 260 - available)
        let rightReduction = hasRight ? min(excess, max(0, targetRight - 240)) : 0
        targetRight -= rightReduction; excess -= rightReduction
        if hasLeft { targetLeft -= min(excess, max(0, targetLeft - 150)) }
        let left = targetLeft * navigationProgress
        let right = targetRight * agentProgress
        navigation?.isHidden = navigationProgress == 0; leftHandle.isHidden = navigationProgress == 0
        navigation?.alphaValue = max(0, (navigationProgress - 0.25) / 0.75)
        agent?.isHidden = agentProgress == 0; rightHandle.isHidden = agentProgress == 0
        agent?.alphaValue = max(0, (agentProgress - 0.25) / 0.75)
        let panelWidth = targetLeft
        navigation?.frame = NSRect(x: left - panelWidth, y: 0, width: panelWidth, height: bounds.height)
        leftHandle.frame = NSRect(x: left, y: 0, width: handleWidth * navigationProgress, height: bounds.height)
        let readingX = left + (handleWidth * navigationProgress)
        let rightX = available - right
        let readingEnd = rightX - (handleWidth * agentProgress)
        reading?.frame = NSRect(x: readingX, y: 0, width: max(0, readingEnd - readingX), height: bounds.height)
        rightHandle.frame = NSRect(x: readingEnd, y: 0, width: handleWidth * agentProgress, height: bounds.height)
        agent?.frame = NSRect(x: rightX, y: 0, width: targetRight, height: bounds.height)
        window?.invalidateCursorRects(for: leftHandle); window?.invalidateCursorRects(for: rightHandle)
    }
}
