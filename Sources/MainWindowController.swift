import Cocoa

/// 主窗口控制器：Finder 风格双栏布局（侧边栏 + 详情面板）
final class MainWindowController: NSWindowController, NSWindowDelegate,
                                  NSSearchFieldDelegate, NSToolbarDelegate {

    private let splitViewController = NSSplitViewController()
    private let sidebarVC = SidebarViewController()
    private let detailVC = DetailViewController()

    private var servers: [Server] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private var connectingIndicator: NSProgressIndicator?

    private let searchItem = NSSearchField()
    private var currentSelectionId: UUID?
    private var lastPersistedSelectionId: UUID?

    // MARK: - 初始化

    init() {
        let rect = NSRect(x: 0, y: 0, width: 780, height: 480)
        let win = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                      .fullSizeContentView, .unifiedTitleAndToolbar],
                          backing: .buffered, defer: false)
        win.title = "Ubuntu RDP"
        win.titlebarAppearsTransparent = true
        win.minSize = NSSize(width: 600, height: 360)
        win.center()
        super.init(window: win)
        win.delegate = self

        setupSplitView()
        setupToolbar()
        setupSidebarCallbacks()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 窗口大小/位置持久化

    /// 是否已恢复保存的 frame
    private var hasRestoredFrame = false
    /// 是否正在恢复（恢复期间触发的 resize/move 不保存）
    private var isRestoring = false
    private var savedFrame: NSRect?
    private var restoreAttempts = 0
    private let maxRestoreAttempts = 10

    /// 窗口首次成为 key 后恢复保存的 frame。
    /// NSSplitViewController 在 showWindow 后会执行初始 layout，可能覆盖 setFrame，
    /// 所以需要在下一 runloop 反复应用，直到 frame 与保存值一致（即 layout 稳定）。
    func windowDidBecomeKey(_ notification: Notification) {
        guard !hasRestoredFrame else { return }
        hasRestoredFrame = true
        beginRestore()
    }

    private func beginRestore() {
        if let saved = UserDefaults.standard.string(forKey: "mainWindowFrame") {
            savedFrame = NSRectFromString(saved)
            isRestoring = true
            restoreAttempts = 0
            DispatchQueue.main.async { [weak self] in
                self?.applySavedFrame()
            }
        }
    }

    private func applySavedFrame() {
        guard isRestoring, let frame = savedFrame, let win = window else { return }
        guard restoreAttempts < maxRestoreAttempts else {
            isRestoring = false
            return
        }
        restoreAttempts += 1
        if win.frame != frame {
            win.setFrame(frame, display: true)
            DispatchQueue.main.async { [weak self] in
                self?.applySavedFrame()
            }
        } else {
            isRestoring = false
        }
    }

    func windowDidMove(_ notification: Notification) {
        if hasRestoredFrame && !isRestoring { saveFrame() }
    }

    func windowDidResize(_ notification: Notification) {
        if hasRestoredFrame && !isRestoring { saveFrame() }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if !isRestoring { saveFrame() }
    }

    private func saveFrame() {
        guard let w = window else { return }
        UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: "mainWindowFrame")
    }

    // MARK: - 双栏布局

    private func setupSplitView() {
        // 左侧 sidebar（自动获得 vibrancy 外观）
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = false

        // 右侧详情
        let detailItem = NSSplitViewItem(viewController: detailVC)
        detailItem.minimumThickness = 360

        splitViewController.splitViewItems = [sidebarItem, detailItem]
        splitViewController.splitView.dividerStyle = .thin
        splitViewController.splitView.autosaveName = "main.split"

        // 底部状态栏（覆盖整个窗口底部）
        let indicator = makeIndicator()
        connectingIndicator = indicator
        let container = StatusbarContainerController(contentViewController: splitViewController,
                                                       statusLabel: statusLabel,
                                                       indicator: indicator)
        window?.contentViewController = container
    }

    private func makeIndicator() -> NSProgressIndicator {
        let i = NSProgressIndicator()
        i.style = .spinning
        i.controlSize = .small
        i.isDisplayedWhenStopped = false
        return i
    }

    // MARK: - 工具栏

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "main.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar

        searchItem.placeholderString = "搜索服务器"
        searchItem.delegate = self
        searchItem.controlSize = .small
    }

    private func setupSidebarCallbacks() {
        sidebarVC.onSelect = { [weak self] server in
            self?.currentSelectionId = server?.id
            self?.detailVC.server = server
            self?.rememberSelection(server?.id)
        }
        sidebarVC.onAdd = { [weak self] in self?.addServer() }
        sidebarVC.onEdit = { [weak self] s in
            self?.sidebarVC.select(id: s.id)
            self?.detailVC.server = s
            self?.editServer(s)
        }
        sidebarVC.onDelete = { [weak self] s in self?.deleteServer(s) }
        sidebarVC.onConnect = { [weak self] s in self?.connect(to: s) }
        sidebarVC.onTest = { [weak self] s in self?.testConnection(to: s) }

        detailVC.onConnect = { [weak self] s in self?.connect(to: s) }
        detailVC.onTest = { [weak self] s in self?.testConnection(to: s) }
        detailVC.onEdit = { [weak self] s in self?.editServer(s) }

        // 活跃连接变化时更新状态栏和窗口菜单
        ConnectionManager.shared.onConnectionsChanged = { [weak self] in
            self?.updateStatus()
            self?.updateWindowMenu()
        }
    }

    // MARK: - 数据

    func reload() {
        do {
            let config = try ConfigStore.shared.load()
            servers = config.servers
            sidebarVC.servers = servers
            lastPersistedSelectionId = config.lastSelectedId
            sidebarVC.select(id: config.lastSelectedId ?? servers.first?.id)
            updateStatus()
        } catch {
            showError("加载配置失败", error.localizedDescription)
        }
    }

    private func rememberSelection(_ id: UUID?) {
        guard let id = id, id != lastPersistedSelectionId else { return }
        lastPersistedSelectionId = id
        if var c = try? ConfigStore.shared.load() {
            c.lastSelectedId = id
            try? ConfigStore.shared.write(c)
        }
    }

    private func updateStatus() {
        let active = ConnectionManager.shared.activeServers
        if active.isEmpty {
            statusLabel.stringValue = "共 \(servers.count) 个服务器"
        } else {
            let names = active.map { $0.name }.joined(separator: "、")
            statusLabel.stringValue = "活跃连接 (\(active.count))：\(names)"
        }
    }

    /// 更新菜单栏「窗口」菜单，显示活跃连接
    func updateWindowMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        // 找到「窗口」菜单
        guard let winItem = mainMenu.items.first(where: { $0.submenu?.title == "窗口" }),
              let winMenu = winItem.submenu else { return }

        // 清除旧的连接项（保留标准项在前）
        let stdCount = 3  // 最小化、缩放、分隔线
        while winMenu.items.count > stdCount {
            winMenu.removeItem(at: winMenu.items.count - 1)
        }

        let active = ConnectionManager.shared.activeServers
        if active.isEmpty { return }

        for s in active {
            let item = winMenu.addItem(withTitle: s.name,
                                       action: #selector(windowMenuItemClicked(_:)),
                                       keyEquivalent: "")
            item.target = self
            item.representedObject = s.id
            item.state = .on
        }
    }

    @objc private func windowMenuItemClicked(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        ConnectionManager.shared.activateWindow(serverId: serverId)
    }

    // MARK: - 连接

    private func connect(to s: Server) {
        statusLabel.stringValue = "正在连接 \(s.name)…"
        connectingIndicator?.startAnimation(nil)
        switch ConnectionManager.shared.connect(to: s) {
        case .success:
            statusLabel.stringValue = "已启动连接：\(s.name)"
        case .failure(let err):
            showError("连接失败", err.localizedDescription)
            updateStatus()
        }
        connectingIndicator?.stopAnimation(nil)
        rememberSelection(s.id)
    }

    private func testConnection(to s: Server) {
        statusLabel.stringValue = "测试连接 \(s.name)…"
        connectingIndicator?.startAnimation(nil)
        ConnectionManager.shared.testConnection(to: s) { [weak self] result in
            DispatchQueue.main.async {
                self?.connectingIndicator?.stopAnimation(nil)
                switch result {
                case .success: self?.statusLabel.stringValue = "\(s.name) 可达 ✓"
                case .failure(let err):
                    self?.showError("测试失败", err.localizedDescription)
                    self?.updateStatus()
                }
            }
        }
    }

    // MARK: - 增删改

    private func addServer() {
        let form = ServerFormController(server: nil)
        form.onComplete = { [weak self] newServer in
            // stopModal 已在 ServerFormController 内调用
            guard let s = newServer else { return }
            do {
                _ = try ConfigStore.shared.update(server: s)
                self?.reload()
            } catch {
                self?.showError("保存失败", error.localizedDescription)
            }
        }
        guard let formWindow = form.window else { return }
        form.showWindow(nil)
        NSApp.runModal(for: formWindow)
    }

    private func editServer(_ server: Server) {
        let form = ServerFormController(server: server)
        form.onComplete = { [weak self] updated in
            guard let u = updated else { return }
            do {
                _ = try ConfigStore.shared.update(server: u)
                self?.reload()
            } catch {
                self?.showError("保存失败", error.localizedDescription)
            }
        }
        guard let formWindow = form.window else { return }
        form.showWindow(nil)
        NSApp.runModal(for: formWindow)
    }

    private func deleteServer(_ s: Server) {
        let a = NSAlert()
        a.messageText = "删除服务器"
        a.informativeText = "确定要删除「\(s.name)」吗？"
        a.alertStyle = .warning
        a.addButton(withTitle: "删除")
        a.addButton(withTitle: "取消")
        // 记住删除前位置，删除后选中相邻项
        let oldIndex = servers.firstIndex(where: { $0.id == s.id }) ?? 0
        a.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            do {
                _ = try ConfigStore.shared.delete(id: s.id)
                self?.reload()
                self?.selectAdjacent(oldIndex: oldIndex)
            } catch {
                self?.showError("删除失败", error.localizedDescription)
            }
        }
    }

    /// 删除后选中相邻项（同位置或最后一项）
    private func selectAdjacent(oldIndex: Int) {
        let list = sidebarVC.servers
        guard !list.isEmpty else { return }
        let idx = min(oldIndex, list.count - 1)
        sidebarVC.select(id: list[idx].id)
    }

    // MARK: - 菜单/快捷键 action（无参，供菜单 responder chain 调用）

    @objc func newServerAction() { addServer() }
    @objc func connectAction() { if let s = sidebarVC.selectedServer { connect(to: s) } }
    @objc func editAction() { if let s = sidebarVC.selectedServer { editServer(s) } }
    @objc func deleteAction() { if let s = sidebarVC.selectedServer { deleteServer(s) } }
    @objc func testAction() { if let s = sidebarVC.selectedServer { testConnection(to: s) } }

    // MARK: - 导入导出 / 日志

    @objc private func exportConfig() {
        let panel = NSSavePanel()
        panel.title = "导出配置"
        panel.nameFieldStringValue = "ubuntu-rdp-servers.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try ConfigStore.shared.export(to: url) }
            catch { showError("导出失败", error.localizedDescription) }
        }
    }

    @objc private func importConfig() {
        let panel = NSOpenPanel()
        panel.title = "导入配置"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try ConfigStore.shared.importConfig(from: url)
                reload()
            } catch {
                showError("导入失败", error.localizedDescription)
            }
        }
    }

    @objc private func openLogFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            Logger.shared.logFileURL,
            ConnectionManager.shared.freerdpLogURL,
        ])
    }

    // MARK: - 搜索

    func controlTextDidChange(_ obj: Notification) {
        let q = searchItem.stringValue.lowercased()
        if q.isEmpty {
            sidebarVC.servers = servers
        } else {
            sidebarVC.servers = servers.filter {
                $0.name.lowercased().contains(q) ||
                $0.address.lowercased().contains(q) ||
                $0.user.lowercased().contains(q)
            }
        }
        updateStatus()
    }

    // MARK: - 错误

    private func showError(_ title: String, _ msg: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.alertStyle = .warning
        a.addButton(withTitle: "好")
        a.beginSheetModal(for: window!, completionHandler: nil)
    }
}

// MARK: - 状态栏容器

private final class StatusbarContainerController: NSViewController {
    private let content: NSViewController
    private let statusLabel: NSTextField
    private let indicator: NSProgressIndicator

    init(contentViewController: NSViewController, statusLabel: NSTextField, indicator: NSProgressIndicator) {
        self.content = contentViewController
        self.statusLabel = statusLabel
        self.indicator = indicator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(statusLabel)

        indicator.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(indicator)

        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 24),

            statusLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            indicator.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            indicator.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    var progressIndicator: NSProgressIndicator { indicator }
}

// MARK: - 工具栏项

extension MainWindowController {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.importConfig, .exportConfig, .flexibleSpace, .search, .logs]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id.rawValue {
        case "import":
            let item = NSToolbarItem(itemIdentifier: .importConfig)
            item.label = "导入"; item.paletteLabel = "导入配置"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
            item.action = #selector(importConfig); item.target = self
            return item
        case "export":
            let item = NSToolbarItem(itemIdentifier: .exportConfig)
            item.label = "导出"; item.paletteLabel = "导出配置"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            item.action = #selector(exportConfig); item.target = self
            return item
        case "logs":
            let item = NSToolbarItem(itemIdentifier: .logs)
            item.label = "日志"; item.paletteLabel = "打开日志"
            item.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
            item.action = #selector(openLogFolder); item.target = self
            return item
        case "search":
            let item = NSSearchToolbarItem(itemIdentifier: .search)
            item.searchField = searchItem
            return item
        default: return nil
        }
    }
}

extension NSToolbarItem.Identifier {
    static let importConfig = NSToolbarItem.Identifier("import")
    static let exportConfig = NSToolbarItem.Identifier("export")
    static let logs         = NSToolbarItem.Identifier("logs")
    static let search       = NSToolbarItem.Identifier("search")
}
