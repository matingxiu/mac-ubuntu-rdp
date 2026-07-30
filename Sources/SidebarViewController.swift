import Cocoa

/// 侧边栏：服务器列表（Finder 风格，带图标）
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let tableView = NSTableView()
    private let addButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "")

    var servers: [Server] = [] {
        didSet {
            tableView.reloadData()
            updateEmptyState()
        }
    }
    var selectedServer: Server? {
        let row = tableView.selectedRow
        guard row >= 0, row < servers.count else { return nil }
        return servers[row]
    }
    var onSelect: ((Server?) -> Void)?
    var onAdd: (() -> Void)?
    var onEdit: ((Server) -> Void)?
    var onDelete: ((Server) -> Void)?
    var onConnect: ((Server) -> Void)?
    var onTest: ((Server) -> Void)?

    override func loadView() {
        view = NSView()
        buildUI()
    }

    private func buildUI() {
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        let col = NSTableColumn(identifier: .init("server"))
        tableView.addTableColumn(col)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        // 底部添加按钮
        addButton.title = "添加服务器"
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.bezelStyle = .rounded
        addButton.controlSize = .regular
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.target = self
        addButton.action = #selector(addClicked)
        view.addSubview(addButton)

        // 空状态提示
        emptyLabel.stringValue = "没有服务器\n点击下方添加"
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

            addButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
        ])

        updateEmptyState()
        setupContextMenu()
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !servers.isEmpty
    }

    // MARK: - 右键菜单

    private func setupContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "连接", action: #selector(menuConnect), keyEquivalent: "").target = self
        menu.addItem(withTitle: "测试连接", action: #selector(menuTest), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "编辑", action: #selector(menuEdit), keyEquivalent: "").target = self
        menu.addItem(withTitle: "删除", action: #selector(menuDelete), keyEquivalent: "").target = self
        tableView.menu = menu
    }

    private func actionForRow(_ block: (Server) -> Void) {
        let row = tableView.clickedRow
        guard row >= 0, row < servers.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        block(servers[row])
    }

    @objc private func menuConnect() { actionForRow { onConnect?($0) } }
    @objc private func menuTest() { actionForRow { onTest?($0) } }
    @objc private func menuEdit() { actionForRow { onEdit?($0) } }
    @objc private func menuDelete() { actionForRow { onDelete?($0) } }

    func select(id: UUID?) {
        guard let id = id, let idx = servers.firstIndex(where: { $0.id == id }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        tableView.scrollRowToVisible(idx)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { servers.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < servers.count else { return nil }
        let s = servers[row]

        let id = NSUserInterfaceItemIdentifier("ServerCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = id

        // 新 cell 首次创建时构建子视图（复用时跳过，只更新内容）
        if cell.imageView == nil {
            let iv = NSImageView()
            iv.imageScaling = .scaleProportionallyDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(iv)
            cell.imageView = iv

            let tf = NSTextField(labelWithString: "")
            tf.isBordered = false
            tf.drawsBackground = false
            tf.isEditable = false
            tf.lineBreakMode = .byTruncatingTail
            tf.font = .systemFont(ofSize: 13, weight: .medium)
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf

            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 22),
                iv.heightAnchor.constraint(equalToConstant: 22),

                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            ])
        }

        // 更新内容
        cell.imageView?.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "服务器")
        cell.imageView?.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        cell.textField?.stringValue = s.name

        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 36 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        onSelect?(selectedServer)
    }

    // 右键菜单
    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int,
                   edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing, row < servers.count else { return [] }
        let edit = NSTableViewRowAction(style: .regular, title: "编辑") { [weak self] _, r in
            tableView.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            guard let self = self, r < self.servers.count else { return }
            self.onEdit?(self.servers[r])
        }
        edit.backgroundColor = .systemBlue
        let del = NSTableViewRowAction(style: .destructive, title: "删除") { [weak self] _, r in
            tableView.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            guard let self = self, r < self.servers.count else { return }
            self.onDelete?(self.servers[r])
        }
        return [del, edit]
    }

    // MARK: - 动作

    @objc private func addClicked() { onAdd?() }

    @objc private func rowDoubleClicked() {
        if let s = selectedServer { onConnect?(s) }
    }
}
