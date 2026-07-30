import Cocoa

/// 应用名称
let appName = "Ubuntu RDP"

// 应用入口（main.swift 顶层代码即为入口）
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

/// 应用代理
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("启动 \(appName)")

        setupMenu()

        // 检查 FreeRDP 是否安装
        if !ConnectionManager.shared.freerdpInstalled {
            showFreeRDPMissingAlert()
        }

        windowController = MainWindowController()
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 菜单栏

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App 菜单
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他",
                                          action: #selector(NSApplication.hideOtherApplications(_:)),
                                          keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // 文件菜单
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "新建服务器", action: Selector(("newServerAction")), keyEquivalent: "n")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "导入配置…", action: Selector(("importConfig")), keyEquivalent: "i")
        let exportItem = fileMenu.addItem(withTitle: "导出配置…", action: Selector(("exportConfig")), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "关闭窗口",
                        action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // 服务器菜单
        let serverItem = NSMenuItem()
        let serverMenu = NSMenu(title: "服务器")
        serverMenu.addItem(withTitle: "连接", action: Selector(("connectAction")), keyEquivalent: "\r")
        serverMenu.addItem(withTitle: "测试连接", action: Selector(("testAction")), keyEquivalent: "t")
        serverMenu.addItem(NSMenuItem.separator())
        serverMenu.addItem(withTitle: "编辑服务器", action: Selector(("editAction")), keyEquivalent: "e")
        let deleteItem = serverMenu.addItem(withTitle: "删除", action: Selector(("deleteAction")), keyEquivalent: "\u{8}")
        deleteItem.keyEquivalentModifierMask = []
        serverItem.submenu = serverMenu
        mainMenu.addItem(serverItem)

        // 编辑菜单（提供标准复制粘贴支持）
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("退出应用")
        ConnectionManager.shared.terminateCurrentProcess()
        Logger.shared.close()
    }

    private func showFreeRDPMissingAlert() {
        let a = NSAlert()
        a.messageText = "未检测到 FreeRDP"
        a.informativeText = "DMG 安装包应已内置 FreeRDP，如缺失请重新下载安装。\n\n自行构建时需运行：\nbrew install freerdp"
        a.alertStyle = .warning
        a.addButton(withTitle: "我知道了")
        a.runModal()
    }
}
