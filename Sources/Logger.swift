import Foundation

/// 日志级别
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

/// 线程安全的文件日志器
final class Logger {
    static let shared = Logger()

    static let logDirectory: URL = {
        let home = NSHomeDirectory()
        let dir = (home as NSString).appendingPathComponent("Library/Logs/ubuntu-rdp")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return URL(fileURLWithPath: dir)
    }()

    private let logFile: String
    private let queue = DispatchQueue(label: "com.mtx.ubuntu-rdp.logger")
    private let dateFormatter: ISO8601DateFormatter
    private var fileHandle: FileHandle?

    private init() {
        logFile = (Logger.logDirectory.appendingPathComponent("app.log")).path
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        openHandle()
    }

    var logFileURL: URL { URL(fileURLWithPath: logFile) }

    /// 打开（或重新打开）文件句柄，定位到末尾
    private func openHandle() {
        if !FileManager.default.fileExists(atPath: logFile) {
            FileManager.default.createFile(atPath: logFile, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFile))
        fileHandle?.seekToEndOfFile()
    }

    func log(_ level: LogLevel, _ message: String, file: String = #file, line: Int = #line) {
        let ts = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let line = "[\(ts)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            // 若句柄失效（文件被删/轮转），重新打开
            if self.fileHandle == nil {
                self.openHandle()
            }
            self.fileHandle?.write(data)
        }
        #if DEBUG
        Swift.print(line, terminator: "")
        #endif
    }

    func debug(_ m: String, file: String = #file, line: Int = #line) { log(.debug, m, file: file, line: line) }
    func info(_ m: String, file: String = #file, line: Int = #line) { log(.info, m, file: file, line: line) }
    func warn(_ m: String, file: String = #file, line: Int = #line) { log(.warn, m, file: file, line: line) }
    func error(_ m: String, file: String = #file, line: Int = #line) { log(.error, m, file: file, line: line) }

    func readAll() -> String {
        (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
    }

    func clear() {
        queue.sync {
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
            fileHandle = nil
            try? Data().write(to: logFileURL)
            openHandle()
        }
    }

    /// 关闭日志文件句柄（App 退出时调用）
    func close() {
        queue.sync {
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
            fileHandle = nil
        }
    }
}
