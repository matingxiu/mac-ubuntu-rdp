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

/// FreeRDP 连接管理器
final class ConnectionManager {
    static let shared = ConnectionManager()

    // 统一日志/脚本路径到 ~/Library/Logs/ubuntu-rdp/
    private let runnerPath: String
    private let freerdpLogPath: String
    private var currentProcess: Process?

    private init() {
        let dir = Logger.logDirectory
        runnerPath = dir.appendingPathComponent("runner.sh").path
        freerdpLogPath = dir.appendingPathComponent("freerdp.log").path
    }

    var freerdpLogURL: URL { URL(fileURLWithPath: freerdpLogPath) }
    var runnerURL: URL { URL(fileURLWithPath: runnerPath) }

    /// FreeRDP 可执行文件路径（自动检测）
    var freerdpPath: String {
        let candidates = [
            "/opt/homebrew/bin/sdl-freerdp",   // Apple Silicon
            "/usr/local/bin/sdl-freerdp",       // Intel
            "/opt/homebrew/bin/xfreerdp",
            "/usr/local/bin/xfreerdp"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "/opt/homebrew/bin/sdl-freerdp"
    }

    var freerdpInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: freerdpPath)
    }

    // MARK: - 连接

    /// 启动 RDP 连接
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

        // 防止并发启动多个 FreeRDP：若旧进程仍在运行，先终止
        if let p = currentProcess, p.isRunning {
            Logger.shared.info("终止旧 FreeRDP 进程 PID=\(p.processIdentifier)，准备重连")
            p.terminate()
            p.waitUntilExit()
            currentProcess = nil
        }

        let script = buildRunnerScript(for: server)
        do {
            try script.write(toFile: runnerPath, atomically: true, encoding: .utf8)
            chmod(runnerPath, 0o755)
        } catch {
            return .failure(.scriptWriteFailed(error.localizedDescription))
        }

        // 用 bash -l 启动（登录 shell，解决 winpr dylib 加载）
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-l", runnerPath]
        process.qualityOfService = .userInteractive

        // 重定向输出到日志文件
        FileManager.default.createFile(atPath: freerdpLogPath, contents: nil)
        if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: freerdpLogPath)) {
            process.standardOutput = fh
            process.standardError = fh
        }

        do {
            try process.run()
            currentProcess = process
            Logger.shared.info("FreeRDP 已启动，PID=\(process.processIdentifier)，⌃⌘交换=\(server.swapCtrlCmd ? "开" : "关")")
            return .success(())
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }

    // MARK: - ⌃⌘ 键位交换

    /// 构建 FreeRDP /kbd:remap 参数（RDP 协议层重映射，仅影响远程桌面，不碰 macOS 系统）
    /// 交换 Left Ctrl↔Win(Cmd)、Right Ctrl↔Win（用十进制，FreeRDP hex 解析对部分扩展扫描码有 bug）：
    ///   LCtrl(29)↔LWin(347)  RCtrl(285)↔RWin(348)
    private static let kbdRemapArg = "/kbd:remap:29=347,remap:347=29,remap:285=348,remap:348=285"

    /// 测试连接（仅检查端口可达性，约 3 秒）
    func testConnection(to server: Server,
                        completion: @escaping (Result<Void, ConnectionError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.launchPath = "/bin/bash"
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

    /// 读取 FreeRDP 运行日志
    func readFreeRDPLog() -> String {
        (try? String(contentsOf: freerdpLogURL, encoding: .utf8)) ?? ""
    }

    // MARK: - 构建脚本

    private func buildRunnerScript(for s: Server) -> String {
        var opts = ""
        switch s.windowMode {
        case "smart": opts = "+dynamic-resolution"
        case "fullscreen": opts = "/f +dynamic-resolution"
        case "both": opts = "/f +dynamic-resolution"
        default: opts = ""
        }

        // 证书：trust-on-first-use，首次连接记录指纹
        let certArg: String
        if let fp = s.trustedFingerprint, !fp.isEmpty {
            certArg = "/cert:tofu:fingerprint:\(fp)"
        } else {
            certArg = "/cert:tofu"
        }

        // ⌃⌘ 交换：在 RDP 协议层重映射扫描码，仅影响远程桌面，不影响 macOS 系统
        let kbdArg = s.swapCtrlCmd ? Self.kbdRemapArg : ""

        // 自动适配屏幕：取 Mac 主屏逻辑分辨率作为远程桌面尺寸，避免越界
        let (w, h) = effectiveResolution(for: s)

        return """
#!/bin/bash
# 由 Ubuntu RDP 客户端自动生成
# 服务器：\(s.name) @ \(s.address)
# ⌃⌘交换：\(s.swapCtrlCmd ? "开（RDP 协议层）" : "关")
# 分辨率：\(w)x\(h)\(s.autoFitScreen ? "（自动适配屏幕）" : "（固定）")
exec \(freerdpPath) \\
    /v:\(s.host):\(s.port) \\
    /u:"\(s.user)" \\
    /p:"\(s.password)" \\
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

    /// 计算实际连接分辨率：autoFitScreen 时取主屏可见区域逻辑分辨率
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
    /// 用于 shell 的安全主机名（仅允许字母数字、点、横线）
    var shellSafeHost: String {
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-")
        return host.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) }.map { String($0) }.joined()
    }
}
