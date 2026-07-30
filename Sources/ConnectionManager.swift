import Foundation
import AppKit

/// 连接错误
enum ConnectionError: LocalizedError {
    case invalidConfig
    case scriptWriteFailed(String)
    case launchFailed(String)
    case unreachable
    case testFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig: return "服务器配置无效（检查名称、地址、用户名、端口）"
        case .scriptWriteFailed(let m): return "无法写入运行脚本：\(m)"
        case .launchFailed(let m): return "启动 FreeRDP 失败：\(m)"
        case .unreachable: return "无法连接到服务器（端口不可达）"
        case .testFailed(let m): return "测试连接失败：\(m)"
        }
    }
}

/// 活跃连接信息
struct ActiveConnection {
    let server: Server
    let process: Process
    let logPath: String
}

/// FreeRDP 连接管理器（支持多连接并行）
final class ConnectionManager {
    static let shared = ConnectionManager()

    private let baseDir: URL
    /// 活跃连接：serverId → 连接信息
    private(set) var activeConnections: [String: ActiveConnection] = [:]

    /// 活跃连接变化时的回调（主线程）
    var onConnectionsChanged: (() -> Void)?

    private init() {
        baseDir = Logger.logDirectory
    }

    // MARK: - 缓存的 FreeRDP 路径

    private static let cachedFreerdpPath: String = {
        let wrapperPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/FreeRDP.app/Contents/MacOS/sdl-freerdp").path
        if FileManager.default.isExecutableFile(atPath: wrapperPath) {
            return wrapperPath
        }
        let candidates = [
            "/opt/homebrew/bin/sdl-freerdp",
            "/usr/local/bin/sdl-freerdp",
            "/opt/homebrew/bin/xfreerdp",
            "/usr/local/bin/xfreerdp"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "/opt/homebrew/bin/sdl-freerdp"
    }()

    var freerdpPath: String { Self.cachedFreerdpPath }

    var freerdpInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: freerdpPath)
    }

    var isFreeRDPBundled: Bool {
        freerdpPath.contains(Bundle.main.bundlePath)
    }

    private var opensslModulesPath: String {
        URL(fileURLWithPath: freerdpPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("ossl-modules")
            .path
    }

    // MARK: - 多连接管理

    /// 当前活跃的服务器列表（用于 Dock 菜单和窗口菜单）
    var activeServers: [Server] {
        activeConnections.values.map { $0.server }.sorted { $0.name < $1.name }
    }

    /// 指定服务器是否已连接
    func isConnected(_ serverId: String) -> Bool {
        activeConnections[serverId]?.process.isRunning ?? false
    }

    // MARK: - 连接

    /// 启动 RDP 连接（支持同时打开多个）
    @discardableResult
    func connect(to server: Server) -> Result<Void, ConnectionError> {
        Logger.shared.info("开始连接：\(server.name) @ \(server.address)")

        guard server.isValid else {
            Logger.shared.error("配置无效")
            return .failure(.invalidConfig)
        }

        guard freerdpInstalled else {
            Logger.shared.error("FreeRDP 未安装：\(freerdpPath)")
            return .failure(.launchFailed("FreeRDP 未安装，请运行：brew install freerdp"))
        }

        // 如果该服务器已连接，直接激活窗口
        let serverId = server.id.uuidString
        if let existing = activeConnections[serverId], existing.process.isRunning {
            Logger.shared.info("\(server.name) 已连接，激活窗口")
            activateWindow(serverId: serverId)
            return .success(())
        }

        // 每个连接使用独立的脚本/env/日志文件（以 serverId 区分）
        let runnerPath = baseDir.appendingPathComponent("runner_\(serverId).sh").path
        let envPath = baseDir.appendingPathComponent(".rdp_env_\(serverId)").path
        let logPath = baseDir.appendingPathComponent("freerdp_\(serverId).log").path

        let script = buildRunnerScript(for: server, runnerPath: runnerPath, envPath: envPath)
        do {
            try script.write(toFile: runnerPath, atomically: true, encoding: .utf8)
            chmod(runnerPath, 0o600)
            let envContent = "RDP_USER='\(server.user)'\nRDP_PASS='\(server.password)'\n"
            try envContent.write(toFile: envPath, atomically: true, encoding: .utf8)
            chmod(envPath, 0o600)
        } catch {
            return .failure(.scriptWriteFailed(error.localizedDescription))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", runnerPath]
        process.qualityOfService = .userInteractive

        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            process.standardOutput = fh
            process.standardError = fh
        }

        let serverName = server.name
        process.terminationHandler = { [weak self] proc in
            Logger.shared.info("FreeRDP 进程退出：\(serverName)，PID=\(proc.processIdentifier)")
            DispatchQueue.main.async {
                self?.activeConnections.removeValue(forKey: serverId)
                self?.onConnectionsChanged?()
            }
        }

        do {
            try process.run()
            activeConnections[serverId] = ActiveConnection(server: server, process: process, logPath: logPath)
            onConnectionsChanged?()
            Logger.shared.info("FreeRDP 已启动：\(server.name)，PID=\(process.processIdentifier)，⌃⌘交换=\(server.swapCtrlCmd ? "开" : "关")")

            // SDL 客户端固有行为：连接前创建占位窗口（~0.1s）、连接建立后重建会话窗口（~1.1s），
            // 两个窗口初始都是黑色，造成“先闪黑窗口再出正常窗口”（已验证与参数无关）。
            // 解决：0.12s~2.04s 内每 120ms 重复 hide，确保两个窗口一出现就被立即隐藏；
            // 3s 后连接已建立、首帧已渲染，再 unhide 显示有内容的窗口。
            let pid = process.processIdentifier
            for i in 1...17 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) { [weak self] in
                    guard let self = self,
                          let conn = self.activeConnections[serverId], conn.process.isRunning else { return }
                    if let app = NSRunningApplication(processIdentifier: pid) {
                        app.hide()
                    }
                }
            }
            Logger.shared.info("已开始隐藏 FreeRDP 窗口（轮询，等待连接建立）")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self,
                      let conn = self.activeConnections[serverId], conn.process.isRunning else { return }
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.unhide()
                    app.activate(options: [.activateAllWindows])
                    Logger.shared.info("已显示 FreeRDP 窗口（连接就绪）")
                }
            }

            return .success(())
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }

    /// 断开指定连接
    func disconnect(serverId: String) {
        guard let conn = activeConnections[serverId], conn.process.isRunning else { return }
        Logger.shared.info("断开连接：\(conn.server.name)")
        conn.process.terminate()
    }

    /// 终止所有 FreeRDP 进程（App 退出时调用）
    func terminateAll() {
        for (id, conn) in activeConnections {
            if conn.process.isRunning {
                Logger.shared.info("终止 FreeRDP：\(conn.server.name)，PID=\(conn.process.processIdentifier)")
                conn.process.terminate()
            }
            activeConnections.removeValue(forKey: id)
        }
    }

    /// 激活指定连接的 FreeRDP 窗口（带到前台）
    func activateWindow(serverId: String) {
        guard let conn = activeConnections[serverId], conn.process.isRunning else { return }
        let pid = conn.process.processIdentifier
        // 用 NSRunningApplication 激活后台进程
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
        }
        // 双保险：用 AppleScript 强制设为前台
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", "tell application \"System Events\" to set frontmost of (first process whose unix id is \(pid)) to true"]
            try? task.run()
            task.waitUntilExit()
        }
    }

    /// 读取指定连接的 FreeRDP 日志（无参数时取最后一个）
    func readFreeRDPLog(serverId: String? = nil) -> String {
        let path: String
        if let sid = serverId, let conn = activeConnections[sid] {
            path = conn.logPath
        } else if let last = Array(activeConnections.values.suffix(1)).first {
            path = last.logPath
        } else {
            return ""
        }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    /// 最近一次连接的日志 URL（兼容旧接口）
    var freerdpLogURL: URL {
        if let last = Array(activeConnections.values.suffix(1)).first {
            return URL(fileURLWithPath: last.logPath)
        }
        return baseDir.appendingPathComponent("freerdp.log")
    }

    // MARK: - ⌃⌘ 键位交换

    private static let kbdRemapArg = "/kbd:remap:29=347,remap:347=29,remap:285=348,remap:348=285"

    // MARK: - 测试连接

    func testConnection(to server: Server,
                        completion: @escaping (Result<Void, ConnectionError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "nc -z -w 3 \(server.shellSafeHost) \(server.port) 2>&1 && echo OK || echo FAIL"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if output.contains("OK") {
                    Logger.shared.info("测试连接成功：\(server.address)")
                    completion(.success(()))
                } else {
                    completion(.failure(.unreachable))
                }
            } catch {
                completion(.failure(.testFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - 构建脚本

    private func buildRunnerScript(for s: Server, runnerPath: String, envPath: String) -> String {
        // 窗口模式参数（只支持 smart/fixed；旧 fullscreen/both 配置自动按 smart 处理）：
        //   smart：+dynamic-resolution 窗口调整时远程分辨率自适应（清晰，非拉伸缩放）
        //     黑窗口闪烁由 SDL 固有双窗口导致、与参数无关，已在 connect 中用 hide 轮询消除
        //     想要真全屏：连接后手动点 sdl-freerdp 窗口的绿色全屏按钮（效果稳定）
        //   fixed：无额外参数，固定 /size
        var opts = ""
        switch s.windowMode {
        case "fixed": opts = ""
        default: opts = "+dynamic-resolution"  // smart 及旧 fullscreen/both
        }

        let certArg: String
        if let fp = s.trustedFingerprint, !fp.isEmpty {
            certArg = "/cert:tofu:fingerprint:\(fp)"
        } else {
            certArg = "/cert:tofu"
        }

        let kbdArg = s.swapCtrlCmd ? Self.kbdRemapArg : ""
        let (w, h) = effectiveResolution(for: s)

        let opensslLine = isFreeRDPBundled
            ? "export OPENSSL_MODULES=\"\(opensslModulesPath)\""
            : "# OPENSSL_MODULES: brew 模式无需设置"

        let sdlBgLine = "export SDL_MAC_BACKGROUND_APP=1  # 后台运行，FreeRDP 不单独占 Dock 图标"

        return """
#!/bin/bash
# 由 Ubuntu RDP 客户端自动生成
# 服务器：\(s.name) @ \(s.address)
# ⌃⌘交换：\(s.swapCtrlCmd ? "开（RDP 协议层）" : "关")
# 分辨率：\(w)x\(h)\(s.autoFitScreen ? "（自动适配屏幕）" : "（固定）")
# 凭据从 .rdp_env 加载（0o600），加载后立即删除，不出现在本脚本中
\(opensslLine)
\(sdlBgLine)
source "\(envPath)"
rm -f "\(envPath)"
exec "\(freerdpPath)" \\
    /v:\(s.host):\(s.port) \\
    /u:"${RDP_USER}" \\
    /p:"${RDP_PASS}" \\
    /sec:nla \\
    -gfx -rfx -nsc -jpeg \\
    /bpp:24 \\
    /size:\(w)x\(h) \\
    \(opts) \\
    \(certArg) \\
    \(kbdArg) \\
    /t:"\(s.name)" \\
    +clipboard \\
    -wallpaper -themes
"""
    }

    private func effectiveResolution(for s: Server) -> (Int, Int) {
        guard s.autoFitScreen, let screen = NSScreen.main else {
            return (s.width, s.height)
        }
        let vf = screen.visibleFrame
        let w = max(640, Int(vf.width))
        let h = max(480, Int(vf.height))
        return (w, h)
    }
}

extension Server {
    var shellSafeHost: String {
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-")
        return host.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) }.map { String($0) }.joined()
    }
}
