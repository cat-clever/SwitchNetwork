import Foundation

/// 应用日志。既写文件（排查"为什么没自动生效"），也在内存里保留最近若干条供 UI 展示。
final class Log: ObservableObject {

    static let shared = Log()

    enum Level: String {
        case info
        case success
        case warning
        case error

        var label: String {
            switch self {
            case .info: return L.t("信息")
            case .success: return L.t("成功")
            case .warning: return L.t("警告")
            case .error: return L.t("错误")
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    private let maximumEntries = 800
    private let queue = DispatchQueue(label: "com.CleverCat.SwitchNetwork.log")
    private let formatter: DateFormatter

    @Published private(set) var entries: [Entry] = []

    let fileURL: URL

    private init() {
        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter = stampFormatter

        let logsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        fileURL = logsDirectory.appendingPathComponent("SwitchNetwork.log")
    }

    func info(_ message: String) { write(.info, message) }
    func success(_ message: String) { write(.success, message) }
    func warning(_ message: String) { write(.warning, message) }
    func error(_ message: String) { write(.error, message) }

    func write(_ level: Level, _ message: String) {
        let entry = Entry(date: Date(), level: level, message: message)
        appendToFile(entry)

        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maximumEntries {
                self.entries.removeFirst(self.entries.count - self.maximumEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
        queue.async {
            try? "".write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func appendToFile(_ entry: Entry) {
        let line = "[\(formatter.string(from: entry.date))] [\(entry.level.label)] \(entry.message)\n"
        queue.async {
            let manager = FileManager.default
            if !manager.fileExists(atPath: self.fileURL.path) {
                try? manager.createDirectory(at: self.fileURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true,
                                             attributes: nil)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    return
                }
            } else {
                try? data.write(to: self.fileURL)
            }
        }
    }
}
