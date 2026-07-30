import Foundation

/// 配置读写错误
enum ConfigError: LocalizedError {
    case parseError(String)
    case writeError(String)
    case readError(String)

    var errorDescription: String? {
        switch self {
        case .parseError(let m): return "配置解析失败：\(m)"
        case .writeError(let m): return "配置写入失败：\(m)"
        case .readError(let m): return "配置读取失败：\(m)"
        }
    }
}

/// 配置存储：负责 JSON 读写、旧格式迁移、导入导出
final class ConfigStore {
    static let shared = ConfigStore()

    private let configDir: String
    private let configPath: String
    private let legacyPath: String

    private init() {
        let home = NSHomeDirectory()
        configDir = (home as NSString).appendingPathComponent(".config/ubuntu-rdp")
        configPath = (configDir as NSString).appendingPathComponent("servers.json")
        legacyPath = (configDir as NSString).appendingPathComponent("config")
    }

    var configURL: URL { URL(fileURLWithPath: configPath) }
    var configDirURL: URL { URL(fileURLWithPath: configDir) }

    private func ensureDir() {
        try? FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)
    }

    // MARK: - 读写

    /// 加载配置（自动迁移旧格式）
    func load() throws -> AppConfig {
        ensureDir()
        guard FileManager.default.fileExists(atPath: configPath) else {
            if FileManager.default.fileExists(atPath: legacyPath) {
                Logger.shared.info("检测到旧配置，开始迁移")
                return try migrateFromLegacy()
            }
            let empty = AppConfig.empty
            try write(empty)
            return empty
        }

        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            Logger.shared.info("加载配置成功，共 \(config.servers.count) 个服务器")
            return config
        } catch {
            Logger.shared.error("配置解析失败：\(error)")
            throw ConfigError.parseError(error.localizedDescription)
        }
    }

    /// 保存配置
    func write(_ config: AppConfig) throws {
        ensureDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw ConfigError.writeError(error.localizedDescription)
        }
    }

    /// 原子更新单个服务器
    func update(server: Server) throws -> AppConfig {
        var config = try load()
        if let idx = config.servers.firstIndex(where: { $0.id == server.id }) {
            config.servers[idx] = server
        } else {
            config.servers.append(server)
        }
        try write(config)
        return config
    }

    /// 删除服务器
    func delete(id: UUID) throws -> AppConfig {
        var config = try load()
        config.servers.removeAll { $0.id == id }
        if config.lastSelectedId == id { config.lastSelectedId = nil }
        try write(config)
        return config
    }

    // MARK: - 导入导出

    func export(to url: URL) throws {
        let config = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    func importConfig(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        try write(config)
        return config
    }

    // MARK: - 旧格式迁移

    private func migrateFromLegacy() throws -> AppConfig {
        let content = (try? String(contentsOfFile: legacyPath, encoding: .utf8)) ?? ""
        func extract(_ key: String) -> String? {
            guard let range = content.range(of: "^\(key)=.*", options: .regularExpression) else { return nil }
            let line = String(content[range])
            var value = String(line.dropFirst(key.count + 1))
            if value.hasPrefix("'") { value.removeFirst() }
            if value.hasSuffix("'") { value.removeLast() }
            return value.isEmpty ? nil : value
        }

        let serverStr = extract("SERVER") ?? "192.168.1.100:3389"
        let parts = serverStr.split(separator: ":")
        let host = String(parts.first ?? "")
        let port = parts.count > 1 ? (Int(parts[1]) ?? 3389) : 3389

        let server = Server(
            name: "Ubuntu 主机",
            host: host,
            port: port,
            user: extract("USER") ?? "username",
            password: extract("PASS") ?? "",
            width: Int(extract("WIDTH") ?? "1920") ?? 1920,
            height: Int(extract("HEIGHT") ?? "1080") ?? 1080,
            windowMode: extract("WINDOW_MODE") ?? "smart"
        )
        let config = AppConfig(servers: [server], lastSelectedId: server.id)
        try write(config)
        Logger.shared.info("迁移完成：\(server.name) @ \(server.address)")
        return config
    }
}
