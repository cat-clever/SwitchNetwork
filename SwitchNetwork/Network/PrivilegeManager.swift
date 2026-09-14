import Foundation

/// 安装免密授权的结果。
enum PrivilegeInstallOutcome {
    case installed
    /// 用户在系统密码框里点了取消。这不是故障。
    case cancelled
    case failed(String)
}

/// sudo 免密授权的探测与安装指引。
///
/// 改 IP 和路由需要 root。走特权 Helper（SMJobBless / SMAppService.daemon）需要
/// Developer ID 签名，本项目没有签名证书，因此采用需求文档给出的过渡方案：
/// 在 /etc/sudoers.d 里只给 networksetup 和 route 这两条命令开 NOPASSWD，
/// 之后所有自动化操作都不会再弹密码框。
enum PrivilegeManager {

    static let sudoersPath = "/etc/sudoers.d/switchnetwork"

    static let sudoersContent = """
    # SwitchNetwork：允许以 root 执行 networksetup 和 route，避免每次自动应用都弹密码框。
    # 只授权这两条命令，且仅限 admin 组成员，不涉及其他任何命令。
    Cmnd_Alias SWITCHNETWORK = /usr/sbin/networksetup, /sbin/route
    %admin ALL=(root) NOPASSWD: SWITCHNETWORK
    """

    /// 探测免密授权是否已生效。用一条只读命令试探，不会产生任何副作用。
    static func probe() -> Bool {
        do {
            let result = try Shell.run(Shell.networksetupPath, ["-listallhardwareports"], privileged: true)
            if result.succeeded {
                return true
            }
            if result.isPermissionDenied {
                Log.shared.warning(L.t("sudo 免密尚未配置：%@", result.combinedMessage))
            } else {
                Log.shared.error(L.t("探测 sudo 权限时出现异常：%@", result.combinedMessage))
            }
            return false
        } catch {
            Log.shared.error(L.t("探测 sudo 权限失败：%@", error.localizedDescription))
            return false
        }
    }

    static func currentUserName() -> String {
        return NSUserName()
    }

    static func isCurrentUserAdmin() -> Bool {
        return isAdmin(userName: currentUserName())
    }

    static func isAdmin(userName: String) -> Bool {
        // 通过 id -Gn 读取用户所属组，避免引入 Membership API 在不同版本上的差异。
        guard let result = try? Shell.run("/usr/bin/id", ["-Gn", userName]) else { return false }
        guard result.succeeded else { return false }
        let groups = result.standardOutput.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        return groups.contains("admin")
    }

    /// 用户需要自己执行的安装命令。
    /// 先写到一个带 `.tmp` 后缀的文件上：sudo 会忽略含 `.` 的文件名，
    /// 所以即使中途出错也不会留下半截配置把 sudo 弄坏。
    static let installCommand = """
    printf '%s\\n' 'Cmnd_Alias SWITCHNETWORK = /usr/sbin/networksetup, /sbin/route' '%admin ALL=(root) NOPASSWD: SWITCHNETWORK' \\
      | sudo tee /etc/sudoers.d/switchnetwork.tmp >/dev/null \\
      && sudo chown root:wheel /etc/sudoers.d/switchnetwork.tmp \\
      && sudo chmod 0440 /etc/sudoers.d/switchnetwork.tmp \\
      && sudo visudo -cf /etc/sudoers.d/switchnetwork.tmp \\
      && sudo mv /etc/sudoers.d/switchnetwork.tmp /etc/sudoers.d/switchnetwork \\
      && echo 'SwitchNetwork 免密授权安装成功'
    """

    static let uninstallCommand = "sudo rm -f /etc/sudoers.d/switchnetwork"

    static let verifyCommand = "sudo -n /usr/sbin/networksetup -listallhardwareports >/dev/null && echo '免密已生效'"

    // MARK: - 一键安装

    /// 安装脚本，与上面给用户看的 installCommand 完全等价，只是把 sudo 去掉了：
    /// 这段是交给 `do shell script ... with administrator privileges` 执行的，
    /// 它本身就以 root 身份运行。写成一行是为了塞进 AppleScript 字符串。
    static let installShellScript = [
        "/usr/bin/printf '%s\\n' 'Cmnd_Alias SWITCHNETWORK = /usr/sbin/networksetup, /sbin/route' '%admin ALL=(root) NOPASSWD: SWITCHNETWORK' > \(sudoersPath).tmp",
        "/usr/sbin/chown root:wheel \(sudoersPath).tmp",
        "/bin/chmod 0440 \(sudoersPath).tmp",
        "/usr/sbin/visudo -cf \(sudoersPath).tmp",
        "/bin/mv \(sudoersPath).tmp \(sudoersPath)",
        "/bin/echo SwitchNetwork sudoers installed"
    ].joined(separator: " && ")

    /// 走系统管理员授权对话框安装（会弹一次密码框），省得用户自己去终端粘贴命令。
    /// 对话框自动带上请求方应用名，不需要自定义 prompt。
    ///
    /// 只给安装做了按钮，卸载没有：撤销一份常驻授权这种事，
    /// 让用户显式敲一行命令比点一下按钮更合适。
    static func installWithAuthorization() -> PrivilegeInstallOutcome {
        let source = "do shell script \"\(appleScriptEscaped(installShellScript))\" with administrator privileges"
        let result: ShellResult
        do {
            // 用户要时间输密码，默认的 20 秒会把人打断在半路。
            result = try Shell.run("/usr/bin/osascript", ["-e", source], timeout: 180)
        } catch {
            return .failed(error.localizedDescription)
        }
        if result.succeeded {
            return .installed
        }
        let message = result.combinedMessage
        // 用户点「取消」时 osascript 报 error -128，这不是故障，别拿它吓人。
        if message.contains("-128") || message.lowercased().contains("cancel") {
            return .cancelled
        }
        return .failed(message)
    }

    /// AppleScript 字符串里的 `\n` 会被当成真换行，所以反斜杠必须先转义，顺序不能反。
    private static func appleScriptEscaped(_ text: String) -> String {
        let backslashed = text.replacingOccurrences(of: "\\", with: "\\\\")
        return backslashed.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
