import Foundation
import ServiceManagement
import AppKit

enum LoginItemState: Equatable {
    case enabled
    case disabled
    /// macOS 13+ 注册后需要用户在「系统设置 → 通用 → 登录项」里手动批准。
    case requiresApproval
    case failed(String)

    var label: String {
        switch self {
        case .enabled: return L.t("已开启")
        case .disabled: return L.t("已关闭")
        case .requiresApproval: return L.t("等待你在系统设置里批准")
        case .failed(let message): return L.t("设置失败：%@", message)
        }
    }

    var isOn: Bool {
        return self == .enabled
    }
}

/// 系统版本差异的统一入口。
///
/// 核心网络 API（SCNetworkConfiguration / SCDynamicStore / IOKit 链路状态）自 10.14 起就稳定，
/// 只有「开机启动注册」这一处需要分版本：macOS 13 起用 SMAppService，更早的系统降级为
/// 写 LaunchAgent plist + launchctl。业务代码只调这里，不让 `#available` 散落到各处。
enum SystemCompat {

    static let launchAgentLabel = "com.CleverCat.SwitchNetwork"

    static var launchAgentURL: URL {
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    static var usesModernLoginItemAPI: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    // MARK: - 开机启动

    static func loginItemState() -> LoginItemState {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            switch status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                return .disabled
            @unknown default:
                return .disabled
            }
        }
        let exists = FileManager.default.fileExists(atPath: launchAgentURL.path)
        return exists ? .enabled : .disabled
    }

    static func setLoginItem(enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            try setModernLoginItem(enabled: enabled)
        } else {
            try setLegacyLoginItem(enabled: enabled)
        }
    }

    @available(macOS 13.0, *)
    private static func setModernLoginItem(enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .enabled { return }
            try service.register()
        } else {
            if service.status == .notRegistered { return }
            try service.unregister()
        }
    }

    /// macOS 11 / 12：写一个 Aqua 会话级的 LaunchAgent，再用 launchctl 加载。
    private static func setLegacyLoginItem(enabled: Bool) throws {
        let path = launchAgentURL.path
        if enabled {
            guard let executable = Bundle.main.executablePath, !executable.isEmpty else {
                throw SystemCompatError.missingExecutable
            }
            let plist: [String: Any] = [
                "Label": launchAgentLabel,
                "ProgramArguments": [executable, "--launched-at-login"],
                "RunAtLoad": NSNumber(value: true),
                "KeepAlive": NSNumber(value: false),
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                         format: .xml,
                                                         options: 0)
            try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true,
                                                   attributes: nil)
            try data.write(to: launchAgentURL)

            // 先卸掉可能存在的旧注册，否则 launchctl load 会报 already loaded。
            _ = try? Shell.run(Shell.launchctlPath, ["unload", path])
            let result = try Shell.run(Shell.launchctlPath, ["load", "-w", path])
            guard result.succeeded else {
                throw SystemCompatError.launchctlFailed(result.combinedMessage)
            }
        } else {
            _ = try? Shell.run(Shell.launchctlPath, ["unload", "-w", path])
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
        }
    }

    /// 把 App 提到前台。macOS 14 起 activate(ignoringOtherApps:) 被弃用。
    static func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func openLoginItemsSettings() {        // macOS 13+ 才有独立的「登录项」面板，旧系统退回到「用户与群组」。
        if #available(macOS 13.0, *) {
            let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            if let target = url {
                NSWorkspace.shared.open(target)
                return
            }
        }
        let url = URL(string: "x-apple.systempreferences:com.apple.preferences.users")
        if let target = url {
            NSWorkspace.shared.open(target)
        }
    }
}

enum SystemCompatError: LocalizedError {
    case missingExecutable
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return L.t("读不到 App 的可执行文件路径，无法注册开机启动")
        case .launchctlFailed(let message):
            return L.t("launchctl 注册失败：%@", message)
        }
    }
}

/// 浅色 / 深色 / 跟随系统。
///
/// 用 NSApp.appearance 而不是 SwiftUI 的 preferredColorScheme：
/// 后者只影响 SwiftUI 视图层级，管不到菜单栏面板、右键菜单和窗口标题栏。
enum AppearanceManager {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
