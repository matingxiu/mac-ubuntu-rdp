import Foundation

/// 一个 RDP 服务器配置
struct Server: Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var user: String
    var password: String
    var width: Int
    var height: Int
    var windowMode: String          // smart / fullscreen / both / fixed
    var trustedFingerprint: String?  // TLS 证书指纹（trust-on-first-use）
    /// 自动适配 Mac 屏幕逻辑分辨率：启动时自动取 Mac 主屏幕的 1x 逻辑分辨率，
    /// 避免 RDP 分辨率大于可用屏幕区域导致窗口越界、自动最大化、切换 Space
    var autoFitScreen: Bool
    /// 启用 smart-sizing：远程桌面按窗口大小缩放，不出现滚动条
    var smartSizing: Bool
    /// 交换 ⌃ 和 ⌘ 键：按 ⌘ 发送 ⌃，按 ⌃ 发送 ⌘
    var swapCtrlCmd: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, user, password
        case width, height
        case windowMode = "window_mode"
        case trustedFingerprint = "trusted_fingerprint"
        case autoFitScreen = "auto_fit_screen"
        case smartSizing = "smart_sizing"
        case swapCtrlCmd = "swap_ctrl_cmd"
    }

    init(id: UUID = UUID(),
         name: String,
         host: String,
         port: Int = 3389,
         user: String,
         password: String,
         width: Int = 1920,
         height: Int = 1080,
         windowMode: String = "smart",
         trustedFingerprint: String? = nil,
         autoFitScreen: Bool = true,
         smartSizing: Bool = true,
         swapCtrlCmd: Bool = true) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.width = width
        self.height = height
        self.windowMode = windowMode
        self.trustedFingerprint = trustedFingerprint
        self.autoFitScreen = autoFitScreen
        self.smartSizing = smartSizing
        self.swapCtrlCmd = swapCtrlCmd
    }

    // 兼容旧配置：id / autoFitScreen / smartSizing 可能缺失
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        user = try c.decode(String.self, forKey: .user)
        password = try c.decode(String.self, forKey: .password)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        windowMode = try c.decode(String.self, forKey: .windowMode)
        trustedFingerprint = try c.decodeIfPresent(String.self, forKey: .trustedFingerprint)
        autoFitScreen = try c.decodeIfPresent(Bool.self, forKey: .autoFitScreen) ?? true
        smartSizing = try c.decodeIfPresent(Bool.self, forKey: .smartSizing) ?? true
        swapCtrlCmd = try c.decodeIfPresent(Bool.self, forKey: .swapCtrlCmd) ?? true
    }

    var address: String { "\(host):\(port)" }
    var resolution: String { "\(width)x\(height)" }
    var isValid: Bool {
        !name.isEmpty && !host.isEmpty && !user.isEmpty && (1...65535).contains(port)
    }

    var isComplete: Bool {
        isValid && !password.isEmpty
    }

    var windowModeDescription: String {
        switch windowMode {
        case "smart": return "smart (可调整大小)"
        case "fullscreen": return "fullscreen (全屏)"
        case "both": return "both (全屏+可调整)"
        case "fixed": return "fixed (固定大小)"
        default: return windowMode
        }
    }
}

/// 应用配置（所有服务器列表）
struct AppConfig: Codable {
    var servers: [Server]
    var lastSelectedId: UUID?

    static let empty = AppConfig(servers: [], lastSelectedId: nil)
}
