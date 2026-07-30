import Cocoa

/// 添加/编辑服务器的表单窗口控制器
final class ServerFormController: NSWindowController, NSTextFieldDelegate {

    private let stack = NSStackView()
    private var fields: [String: NSControl] = [:]

    var onComplete: ((Server?) -> Void)?

    let server: Server?
    private let isEdit: Bool

    init(server: Server? = nil) {
        self.server = server
        self.isEdit = server != nil

        let rect = NSRect(x: 0, y: 0, width: 460, height: 460)
        let win = NSWindow(contentRect: rect,
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = isEdit ? "编辑服务器" : "添加服务器"
        win.center()
        super.init(window: win)
        buildUI()
        populate()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI 构建

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cv.topAnchor),
            stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        addField("name", label: "名称", placeholder: "我的 Ubuntu 服务器")
        addField("host", label: "主机地址", placeholder: "192.168.1.100")
        addField("port", label: "端口", placeholder: "3389", numeric: true)
        addField("user", label: "用户名", placeholder: "username")
        addField("password", label: "密码", placeholder: "", secure: true)
        addField("width", label: "分辨率宽", placeholder: "1920", numeric: true)
        addField("height", label: "分辨率高", placeholder: "1080", numeric: true)

        // 窗口模式
        let modeLabel = NSTextField(labelWithString: "窗口模式")
        modeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for opt in ["smart (可调整大小)", "fixed (固定大小)"] {
            modePopup.addItem(withTitle: opt)
        }
        let modeRow = NSStackView(views: [modeLabel, modePopup])
        modeRow.orientation = .horizontal
        modeRow.spacing = 8
        fields["windowMode"] = modePopup
        stack.addArrangedSubview(modeRow)

        // 复选框：自动适配屏幕 + smart sizing
        let autoFitBtn = NSButton(checkboxWithTitle: "自动适配 Mac 屏幕（推荐：防止窗口越界切到其他桌面）",
                                  target: nil, action: nil)
        autoFitBtn.state = .on
        autoFitBtn.font = .systemFont(ofSize: 12)
        fields["autoFitScreen"] = autoFitBtn
        stack.addArrangedSubview(autoFitBtn)

        let smartBtn = NSButton(checkboxWithTitle: "智能缩放（实验性：与动态分辨率互斥，暂未生效）",
                                target: nil, action: nil)
        smartBtn.state = .on
        smartBtn.font = .systemFont(ofSize: 12)
        fields["smartSizing"] = smartBtn
        stack.addArrangedSubview(smartBtn)

        let swapBtn = NSButton(checkboxWithTitle: "交换 ⌃ 和 ⌘ 键（按 ⌘ 发送 ⌃，RDP 协议层，不影响 Mac 系统）",
                               target: nil, action: nil)
        swapBtn.state = .on
        swapBtn.font = .systemFont(ofSize: 12)
        fields["swapCtrlCmd"] = swapBtn
        stack.addArrangedSubview(swapBtn)

        // 提示文本
        let hint = NSTextField(labelWithString: "提示：禁用「自动适配」时才会使用上面的分辨率宽/高")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.isBezeled = false
        hint.drawsBackground = false
        hint.isEditable = false
        stack.addArrangedSubview(hint)

        // 按钮区
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.bezelColor = NSColor(srgbRed: 0.91, green: 0.33, blue: 0.13, alpha: 1)
        save.contentTintColor = .white
        let btnRow = NSStackView(views: [NSView(), cancel, save])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        stack.addArrangedSubview(btnRow)
    }

    private func addField(_ key: String, label: String, placeholder: String,
                          numeric: Bool = false, secure: Bool = false) {
        let lab = NSTextField(labelWithString: label)
        lab.font = .systemFont(ofSize: 11, weight: .medium)
        let field: NSControl
        if secure {
            field = NSSecureTextField()
            (field as! NSSecureTextField).placeholderString = placeholder
        } else if numeric {
            let nf = NSTextField()
            nf.placeholderString = placeholder
            nf.formatter = IntegerFormatter()
            field = nf
        } else {
            let tf = NSTextField()
            tf.placeholderString = placeholder
            field = tf
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true
        fields[key] = field

        let row = NSStackView(views: [lab, NSView(), field])
        row.orientation = .horizontal
        row.spacing = 8
        field.widthAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(row)
    }

    private func populate() {
        guard let s = server else {
            // 新建时用上次保存的默认值
            let d = UserDefaults.standard
            (fields["port"] as? NSTextField)?.stringValue = String(d.object(forKey: "formPort") as? Int ?? 3389)
            (fields["width"] as? NSTextField)?.stringValue = String(d.object(forKey: "formWidth") as? Int ?? 1920)
            (fields["height"] as? NSTextField)?.stringValue = String(d.object(forKey: "formHeight") as? Int ?? 1080)
            (fields["windowMode"] as? NSPopUpButton)?.selectItem(at: d.object(forKey: "formModeIdx") as? Int ?? 0)
            (fields["autoFitScreen"] as? NSButton)?.state = .on
            (fields["smartSizing"] as? NSButton)?.state = .on
            (fields["swapCtrlCmd"] as? NSButton)?.state = .on
            return
        }
        (fields["name"] as? NSTextField)?.stringValue = s.name
        (fields["host"] as? NSTextField)?.stringValue = s.host
        (fields["port"] as? NSTextField)?.stringValue = String(s.port)
        (fields["user"] as? NSTextField)?.stringValue = s.user
        (fields["password"] as? NSSecureTextField)?.stringValue = s.password
        (fields["width"] as? NSTextField)?.stringValue = String(s.width)
        (fields["height"] as? NSTextField)?.stringValue = String(s.height)
        let modes = ["smart", "fixed"]
        (fields["windowMode"] as? NSPopUpButton)?.selectItem(at: modes.firstIndex(of: s.windowMode) ?? 0)
        (fields["autoFitScreen"] as? NSButton)?.state = s.autoFitScreen ? .on : .off
        (fields["smartSizing"] as? NSButton)?.state = s.smartSizing ? .on : .off
        (fields["swapCtrlCmd"] as? NSButton)?.state = s.swapCtrlCmd ? .on : .off
    }

    // MARK: - 动作

    @objc private func cancel() {
        window?.close()
        NSApp.stopModal()
        onComplete?(nil)
    }

    @objc private func save() {
        let name = (fields["name"] as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let host = (fields["host"] as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let port = Int((fields["port"] as? NSTextField)?.stringValue ?? "") ?? 3389
        let user = (fields["user"] as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let pass = (fields["password"] as? NSSecureTextField)?.stringValue ?? ""
        let width = Int((fields["width"] as? NSTextField)?.stringValue ?? "") ?? 1920
        let height = Int((fields["height"] as? NSTextField)?.stringValue ?? "") ?? 1080
        let modes = ["smart", "fixed"]
        let modeIdx = (fields["windowMode"] as? NSPopUpButton)?.indexOfSelectedItem ?? 0
        let mode = modes[modeIdx]
        let autoFit = (fields["autoFitScreen"] as? NSButton)?.state == .on
        let smart = (fields["smartSizing"] as? NSButton)?.state == .on
        let swapCtrlCmd = (fields["swapCtrlCmd"] as? NSButton)?.state == .on

        // 简单校验
        guard !name.isEmpty else {
            showAlert("名称不能为空"); return
        }
        guard !host.isEmpty else {
            showAlert("主机地址不能为空"); return
        }
        guard !user.isEmpty else {
            showAlert("用户名不能为空"); return
        }

        // 记住默认值（下次新建时复用）
        let d = UserDefaults.standard
        d.set(port, forKey: "formPort")
        d.set(width, forKey: "formWidth")
        d.set(height, forKey: "formHeight")
        d.set(modeIdx, forKey: "formModeIdx")

        // 编辑时复用原 server（保留 id），新建时创建空壳再统一赋值
        var result = server ?? Server(name: "", host: "", user: "", password: "")
        result.name = name
        result.host = host
        result.port = port
        result.user = user
        result.password = pass
        result.width = width
        result.height = height
        result.windowMode = mode
        result.autoFitScreen = autoFit
        result.smartSizing = smart
        result.swapCtrlCmd = swapCtrlCmd

        window?.close()
        NSApp.stopModal()
        onComplete?(result)
    }

    private func showAlert(_ msg: String) {
        let a = NSAlert()
        a.messageText = "输入无效"
        a.informativeText = msg
        a.alertStyle = .warning
        a.addButton(withTitle: "好")
        a.beginSheetModal(for: window!, completionHandler: nil)
    }
}

/// 仅允许整数的格式化器
final class IntegerFormatter: Formatter {
    override func isPartialStringValid(_ partialString: String,
                                      newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                      errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        if partialString.isEmpty { return true }
        return partialString.allSatisfy { $0.isNumber }
    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                for string: String,
                                errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = Int(string) as NSNumber? ?? 0 as NSNumber
        return true
    }

    override func string(for obj: Any?) -> String? {
        if let n = obj as? NSNumber { return String(n.intValue) }
        return ""
    }
}
