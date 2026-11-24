import AppKit

private final class ChatHistoryCell: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let deleteButton = ReaderToolbarButton()
    var onDelete: () -> Void = {}
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 12, weight: .medium); title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 10); detail.textColor = .secondaryLabelColor
        deleteButton.image = NanoIcons.symbol("trash", label: "Delete chat")
        deleteButton.isBordered = false; deleteButton.target = self; deleteButton.action = #selector(deleteChat)
        deleteButton.toolTip = "Delete this conversation"
        for view in [title, detail, deleteButton] { addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), title.topAnchor.constraint(equalTo: topAnchor, constant: 11), title.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor), detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5), detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor), deleteButton.widthAnchor.constraint(equalToConstant: 28), deleteButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    func configure(_ thread: ChatThread) {
        title.stringValue = thread.title; title.toolTip = thread.title
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short
        detail.stringValue = formatter.string(from: thread.updatedAt)
        deleteButton.setAccessibilityLabel("Delete conversation: \(thread.title)")
    }
    @objc private func deleteChat() { onDelete() }
}

final class ChatHistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onOpen: (ChatThread) -> Void = { _ in }
    var onDelete: (UUID) -> Void = { _ in }
    private var records: [ChatThread] = []
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(wrappingLabelWithString: "No conversations for this PDF yet.")
    override init(frame: NSRect) {
        super.init(frame: frame)
        table.addTableColumn(NSTableColumn(identifier: .init("chat")))
        table.headerView = nil; table.style = .plain; table.rowHeight = 64; table.intercellSpacing = .zero
        table.backgroundColor = .clear; table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.autoresizingMask = [.width]; table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(openChat)
        table.setAccessibilityLabel("Saved conversations for this PDF")
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = table
        empty.font = .systemFont(ofSize: 12); empty.textColor = .secondaryLabelColor; empty.alignment = .center
        addSubview(scroll); addSubview(empty)
        scroll.translatesAutoresizingMaskIntoConstraints = false; empty.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor), empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layout() {
        super.layout()
        table.setFrameSize(NSSize(width: scroll.contentSize.width, height: table.frame.height))
        table.tableColumns.first?.width = scroll.contentSize.width
    }
    func show(_ records: [ChatThread], error: String? = nil) {
        self.records = records; table.reloadData()
        empty.stringValue = error ?? "No conversations for this PDF yet."
        empty.isHidden = !records.isEmpty && error == nil
    }
    func numberOfRows(in tableView: NSTableView) -> Int { records.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let record = records[row]
        let cell = ChatHistoryCell()
        cell.configure(record); cell.onDelete = { [weak self] in self?.onDelete(record.id) }
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SidebarSelectionRow() }
    @objc private func openChat() {
        guard records.indices.contains(table.clickedRow) else { return }
        onOpen(records[table.clickedRow])
    }
}
