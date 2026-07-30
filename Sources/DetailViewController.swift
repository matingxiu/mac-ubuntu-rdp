import Cocoa

/// 详情面板：选中服务器的预览 + 操作（上下左右居中）
final class DetailViewController: NSViewController {

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let addressLabel = NSTextField(labelWithString: "")
    private let infoStack = NSStackView()
    private let connectButton = NSButton()
    private let testButton = NSButton()
    private let editButton = NSButton(title: "编辑", target: nil, action: nil)
    private let placeholderLabel = NSTextField(labelWithString: "")

    var server: Server? {
        didSet { update() }
    }
    var onConnect: ((Server) -> Void)?
    var onTest: ((Server) -> Void)?
    var onEdit: ((Server) -> Void)?

    override func loadView() {
        view = NSView()
        buildUI()
        update()
    }

    private func buildUI() {
        // 内容容器：垂直堆叠，整体居中
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        // 大图标
        iconView.symbolConfiguration = .init(pointSize: 64, weight: .regular)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(iconView)
        container.setCustomSpacing(16, after: iconView)

        // 标题
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .center
        container.addArrangedSubview(titleLabel)
        container.setCustomSpacing(4, after: titleLabel)

        // 地址副标题
        addressLabel.font = .systemFont(ofSize: 13)
        addressLabel.textColor = .secondaryLabelColor
        addressLabel.alignment = .center
        container.addArrangedSubview(addressLabel)
        container.setCustomSpacing(24, after: addressLabel)

        // 信息表格
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 6
        container.addArrangedSubview(infoStack)
        container.setCustomSpacing(28, after: infoStack)

        // 按钮区
        connectButton.title = "连接"
        connectButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        connectButton.imagePosition = .imageLeading
        connectButton.bezelStyle = .rounded
        connectButton.controlSize = .large
        connectButton.target = self
        connectButton.action = #selector(connectClicked)
        connectButton.contentTintColor = .white

        testButton.title = "测试连接"
        testButton.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)
        testButton.imagePosition = .imageLeading
        testButton.bezelStyle = .rounded
        testButton.controlSize = .regular
        testButton.target = self
        testButton.action = #selector(testClicked)

        editButton.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        editButton.imagePosition = .imageLeading
        editButton.bezelStyle = .rounded
        editButton.controlSize = .regular
        editButton.target = self
        editButton.action = #selector(editClicked)

        let btnRow = NSStackView(views: [connectButton, testButton, editButton])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        container.addArrangedSubview(btnRow)

        // 空状态占位
        placeholderLabel.stringValue = "从左侧选择一个服务器"
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        // 容器居中于安全区域
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }

    private func update() {
        let s = server
        placeholderLabel.isHidden = s != nil
        containerVisible(s != nil)

        iconView.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "服务器")
        titleLabel.stringValue = s?.name ?? ""
        addressLabel.stringValue = s?.address ?? ""

        infoStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let s = s else {
            connectButton.isEnabled = false
            testButton.isEnabled = false
            editButton.isEnabled = false
            return
        }
        connectButton.isEnabled = true
        testButton.isEnabled = true
        editButton.isEnabled = true

        addInfoRow(label: "用户名", value: s.user)
        addInfoRow(label: "端口", value: String(s.port))
        addInfoRow(label: "分辨率", value: s.autoFitScreen ? "自动适配屏幕" : s.resolution)
        addInfoRow(label: "窗口模式", value: s.windowModeDescription)
        addInfoRow(label: "智能缩放", value: s.smartSizing ? "开启" : "关闭")
        addInfoRow(label: "⌃⌘ 交换", value: s.swapCtrlCmd ? "开启" : "关闭")
    }

    /// 切换内容容器和占位文字的显隐
    private func containerVisible(_ visible: Bool) {
        iconView.isHidden = !visible
        titleLabel.isHidden = !visible
        addressLabel.isHidden = !visible
        infoStack.isHidden = !visible
        connectButton.superview?.isHidden = !visible
    }

    private func addInfoRow(label: String, value: String) {
        let lab = NSTextField(labelWithString: label)
        lab.font = .systemFont(ofSize: 12)
        lab.textColor = .secondaryLabelColor
        lab.alignment = .right
        let val = NSTextField(labelWithString: value)
        val.font = .systemFont(ofSize: 12, weight: .medium)
        val.alignment = .left
        let row = NSStackView(views: [lab, val])
        row.orientation = .horizontal
        row.spacing = 12
        lab.widthAnchor.constraint(equalToConstant: 70).isActive = true
        val.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        infoStack.addArrangedSubview(row)
    }

    @objc private func connectClicked() { if let s = server { onConnect?(s) } }
    @objc private func testClicked() { if let s = server { onTest?(s) } }
    @objc private func editClicked() { if let s = server { onEdit?(s) } }
}
