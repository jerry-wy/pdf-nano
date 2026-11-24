import AppKit

private final class ModelPickerCell: NSButtonCell {
    override func drawInterior(withFrame frame: NSRect, in controlView: NSView) {
        let text = NSTextFieldCell(textCell: title)
        text.font = font ?? .systemFont(ofSize: 11, weight: .medium)
        text.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        text.alignment = .left; text.lineBreakMode = .byTruncatingMiddle
        text.isScrollable = false; text.wraps = false
        let height = ceil(text.cellSize.height)
        let textRect = NSRect(x: frame.minX + 10, y: frame.midY - height / 2,
                              width: max(0, frame.width - 36), height: height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: frame.insetBy(dx: 2, dy: 2)).addClip()
        text.drawInterior(withFrame: textRect, in: controlView)
        let x = frame.maxX - 14, y = frame.midY
        let down: CGFloat = controlView.isFlipped ? 1 : -1
        let chevron = NSBezierPath(); chevron.lineWidth = 1.2; chevron.lineCapStyle = .round
        chevron.move(to: NSPoint(x: x - 3, y: y - down * 1.5))
        chevron.line(to: NSPoint(x: x, y: y + down * 1.5))
        chevron.line(to: NSPoint(x: x + 3, y: y - down * 1.5))
        (isEnabled ? NSColor.secondaryLabelColor : .disabledControlTextColor).setStroke()
        chevron.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

// A compact menu button using the same typography, corners and hover treatment
// as sidebar tabs. Custom IDs remain available without an always-editable field.
final class ModelPicker: ReaderToolbarButton {
    private var options: [String] = []
    var selectedValue = "" {
        didSet {
            title = selectedValue
            toolTip = selectedValue
            setAccessibilityValue(selectedValue)
            invalidateIntrinsicContentSize(); needsDisplay = true
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = ModelPickerCell(textCell: "")
        isBordered = false; setButtonType(.momentaryChange)
        imagePosition = .noImage; alignment = .left
        font = .systemFont(ofSize: 11, weight: .medium)
        cell?.lineBreakMode = .byTruncatingMiddle
        target = self; action = #selector(showModels)
        setAccessibilityRole(.popUpButton); setAccessibilityLabel("Codex model")
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override var intrinsicContentSize: NSSize {
        let width = (selectedValue as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 11, weight: .medium)]).width
        return NSSize(width: max(84, ceil(width) + 40), height: 28)
    }
    func addOptions(_ titles: [String]) { options = titles }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        super.draw(dirtyRect)
    }
    @objc private func showModels() {
        let menu = NSMenu()
        var values = options
        if !selectedValue.isEmpty && !values.contains(selectedValue) { values.insert(selectedValue, at: 0) }
        for value in values {
            let item = NSMenuItem(title: value, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = value
            item.state = value == selectedValue ? .on : .off; menu.addItem(item)
        }
        menu.addItem(.separator())
        let custom = NSMenuItem(title: "Custom model…", action: #selector(enterCustomModel), keyEquivalent: "")
        custom.target = self; menu.addItem(custom)
        menu.popUp(positioning: menu.items.first(where: { $0.state == .on }), at: NSPoint(x: 0, y: bounds.maxY + 4), in: self)
    }
    @objc private func selectModel(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { selectedValue = value }
    }
    @objc private func enterCustomModel() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "Custom model"
        alert.informativeText = "Enter a model ID available to your Codex account."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Model ID"; field.setAccessibilityLabel("Custom model ID")
        alert.accessoryView = field; alert.addButton(withTitle: "Use model"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .alertFirstButtonReturn && !value.isEmpty { self?.selectedValue = value }
        }
    }
}
