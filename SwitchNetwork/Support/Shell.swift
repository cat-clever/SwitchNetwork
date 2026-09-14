import Foundation

struct ShellResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool { return exitCode == 0 }

    /// sudo 未配置免密时，sudo 会把错误写在 stderr 里，用它区分"权限不足"和"命令本身失败"。
    var isPermissionDenied: Bool {
        let text = standardError.lowercased()
        return text.contains("a password is required")
            || text.contains("no tty present")
            || text.contains("not allowed to execute")
            || text.contains("a terminal is required")
    }

    var combinedMessage: String {
        let err = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return err }
        return standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ShellError: LocalizedError {
    case launchFailed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let tool):
            return L.t("无法启动 %@", tool)
        case .timedOut(let tool):
            return L.t("%@ 执行超时", tool)
        }
    }
}

/// 命令执行封装。所有需要 root 的操作都通过 `sudo -n` 走，
/// 配合 /etc/sudoers.d 里的 NOPASSWD 规则实现不弹密码框。
enum Shell {

    static let sudoPath = "/usr/bin/sudo"
    static let networksetupPath = "/usr/sbin/networksetup"
    static let routePath = "/sbin/route"
    static let netstatPath = "/usr/sbin/netstat"
    static let ifconfigPath = "/sbin/ifconfig"
    static let launchctlPath = "/bin/launchctl"

    /// GUI App 由 launchd 启动，不会继承登录 shell 的环境变量。
    /// 这里显式固定一批变量，保证 networksetup 输出不被本地化、可稳定解析。
    private static var fixedEnvironment: [String: String] {
        var environment: [String: String] = [
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        let home = NSHomeDirectory()
        if !home.isEmpty {
            environment["HOME"] = home
        }
        let user = NSUserName()
        if !user.isEmpty {
            environment["USER"] = user
            environment["LOGNAME"] = user
        }
        return environment
    }

    @discardableResult
    static func run(_ tool: String,
                    _ arguments: [String],
                    privileged: Bool = false,
                    timeout: TimeInterval = 20) throws -> ShellResult {
        let process = Process()
        if privileged {
            process.executableURL = URL(fileURLWithPath: sudoPath)
            process.arguments = ["-n", tool] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
        }
        process.environment = fixedEnvironment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let box = OutputBox()
        let group = DispatchGroup()
        let readers = DispatchQueue.global(qos: .userInitiated)

        // 必须在 waitUntilExit 之前把管道读干，否则输出超过管道缓冲区时会死锁。
        group.enter()
        readers.async {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            box.setOutput(String(decoding: data, as: UTF8.self))
            group.leave()
        }
        group.enter()
        readers.async {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            box.setError(String(decoding: data, as: UTF8.self))
            group.leave()
        }

        do {
            try process.run()
        } catch {
            group.leave()
            group.leave()
            throw ShellError.launchFailed(tool)
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            throw ShellError.timedOut(tool)
        }

        process.waitUntilExit()
        let captured = box.snapshot()
        return ShellResult(exitCode: process.terminationStatus,
                           standardOutput: captured.output,
                           standardError: captured.error)
    }

    private final class OutputBox {
        private let lock = NSLock()
        private var output = ""
        private var error = ""

        func setOutput(_ text: String) {
            lock.lock()
            output = text
            lock.unlock()
        }

        func setError(_ text: String) {
            lock.lock()
            error = text
            lock.unlock()
        }

        func snapshot() -> (output: String, error: String) {
            lock.lock()
            defer { lock.unlock() }
            return (output, error)
        }
    }
}
