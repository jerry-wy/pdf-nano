import AppKit

final class OCRProgressView: NSView {
    private let spinner = NSProgressIndicator()
    private let bar = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    private var pageNumber = 0
    private var pageCount = 1
    private var addingLayer = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        spinner.style = .spinning; spinner.controlSize = .small
        spinner.isIndeterminate = true; spinner.isDisplayedWhenStopped = false
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1
        bar.controlSize = .small; bar.isHidden = true
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor; label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spinner, label, bar]); row.spacing = 6; row.alignment = .centerY
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14), spinner.heightAnchor.constraint(equalToConstant: 14),
            bar.widthAnchor.constraint(equalToConstant: 48)
        ])
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    func begin(page: Int, total: Int = 1) {
        addingLayer = false
        pageNumber = page; pageCount = max(1, total)
        isHidden = false; bar.isHidden = false; bar.doubleValue = Double(page - 1) / Double(pageCount)
        label.stringValue = "OCR · \(page)/\(pageCount) · Preparing…"
        spinner.startAnimation(nil)
        setAccessibilityLabel(label.stringValue)
    }
    func recognize(fraction: Double? = nil) {
        guard !addingLayer else { return }
        if let fraction, fraction.isFinite {
            bar.isHidden = false
            bar.doubleValue = max(bar.doubleValue, (Double(pageNumber - 1) + min(1, max(0, fraction))) / Double(pageCount))
            label.stringValue = "OCR · \(pageNumber)/\(pageCount) · \(Int(bar.doubleValue * 100))%"
        } else {
            bar.isHidden = false
            label.stringValue = "OCR · \(pageNumber)/\(pageCount) · Recognizing…"
        }
        setAccessibilityLabel(label.stringValue)
    }
    func applying() {
        addingLayer = true
        bar.isHidden = true
        label.stringValue = "OCR · \(pageNumber)/\(pageCount) · Adding text…"
        setAccessibilityLabel(label.stringValue)
    }
    func finish() { spinner.stopAnimation(nil); isHidden = true }
}
