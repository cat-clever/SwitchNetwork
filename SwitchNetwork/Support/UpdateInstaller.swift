import Foundation
import AppKit
import CryptoKit

/// 安装走到哪一步了，界面上显示用。
enum UpdateInstallStage {
    case downloading
    case verifying
    case installing
    case restarting

    var label: String {
        switch self {
        case .downloading: return L.t("正在下载新版本…")
        case .verifying: return L.t("正在校验安装包…")
        case .installing: return L.t("正在替换应用…")
        case .restarting: return L.t("正在重启…")
        }
    }
}

enum UpdateInstallOutcome {
    /// 已经装好并即将重启。version 是装上去的那一版。
    case installed(version: String)
    case failed(String)
}

/// 下载 dmg、校验、把「应用程序」里的自己换掉，然后重启。
///
/// 替换的做法：`ditto` 到同卷的暂存目录 → 旧 app 改名让位 → 暂存改名顶上。
/// **绝不先删再拷**：那样中途失败就一份都不剩了。这里任何一步失败都能退回原样。
enum UpdateInstaller {

    /// 正式安装位置。只有从这里运行才允许自我替换。
    static let installedAppURL = URL(fileURLWithPath: "/Applications/SwitchNetwork.app", isDirectory: true)

    /// 当前进程是不是从「应用程序」里跑起来的。
    /// 开发时产物在 DerivedData 里，替换它没有意义还会搞乱 Xcode 的产物。
    static var isRunningFromApplications: Bool {
        return comparablePath(Bundle.main.bundleURL) == comparablePath(installedAppURL)
    }

    /// 上一个版本放在本机 `Application Support` 下。
    /// 故意不放 iCloud：同步一整个 app 又慢又没意义，而且回退只需要本机有。
    static var previousAppURL: URL {
        return JSONStore.localDirectory
            .appendingPathComponent("previous", isDirectory: true)
            .appendingPathComponent("SwitchNetwork.app", isDirectory: true)
    }

    static var hasPreviousVersion: Bool {
        return FileManager.default.fileExists(atPath: previousAppURL.path)
    }

    private struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { return message }
    }

    // MARK: - 安装 / 回退

    /// 下载并安装新版本。progress 和 completion 都在主线程回调。
    static func install(_ info: UpdateInfo,
                        progress: @escaping (UpdateInstallStage) -> Void,
                        completion: @escaping (UpdateInstallOutcome) -> Void) {
        // 真正干活在后台队列上，但回调要回到主线程——界面状态只能在主线程改。
        let report: (UpdateInstallStage) -> Void = { stage in
            DispatchQueue.main.async { progress(stage) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = performInstall(info, progress: report)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// 换回上一个版本。装回去之后，刚才用着的那一版就成了「上一个版本」，
    /// 所以按钮会一直在，可以来回切。
    static func rollback(progress: @escaping (UpdateInstallStage) -> Void,
                         completion: @escaping (UpdateInstallOutcome) -> Void) {
        let report: (UpdateInstallStage) -> Void = { stage in
            DispatchQueue.main.async { progress(stage) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = performRollback(progress: report)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private static func performInstall(_ info: UpdateInfo,
                                       progress: @escaping (UpdateInstallStage) -> Void) -> UpdateInstallOutcome {
        guard isRunningFromApplications else {
            return .failed(L.t("当前不是从「应用程序」里运行的，不能自我替换。请到发布页下载 dmg 手动安装。"))
        }
        guard let dmgURL = info.dmgURL else {
            return .failed(L.t("这个版本没有提供 dmg 附件，请到发布页下载。"))
        }

        let manager = FileManager.default
        let cache = cacheDirectory
        let dmgFile = cache.appendingPathComponent("SwitchNetwork-\(info.version).dmg")
        // 挂载点必须是已存在的空目录，hdiutil 不会自己建。
        // 放在应用自己的缓存目录里，不用系统临时目录。
        let mountPoint = cache.appendingPathComponent("mnt", isDirectory: true)

        do {
            try manager.createDirectory(at: cache, withIntermediateDirectories: true, attributes: nil)
            try? manager.removeItem(at: mountPoint)
            try manager.createDirectory(at: mountPoint, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return .failed(L.t("准备下载目录失败：%@", error.localizedDescription))
        }

        progress(.downloading)
        do {
            try download(dmgURL, to: dmgFile)
        } catch {
            return .failed(L.t("下载失败：%@", error.localizedDescription))
        }
        // 不管后面成败，都不该在缓存里留一个几十 MB 的 dmg。
        defer { try? manager.removeItem(at: dmgFile) }

        progress(.verifying)
        do {
            try verifyChecksum(of: dmgFile, info: info)
            try attach(dmgFile, at: mountPoint)
        } catch {
            detach(mountPoint)
            return .failed(error.localizedDescription)
        }
        defer {
            detach(mountPoint)
            try? manager.removeItem(at: mountPoint)
        }

        let sourceApp = mountPoint.appendingPathComponent("SwitchNetwork.app", isDirectory: true)
        guard manager.fileExists(atPath: sourceApp.path) else {
            return .failed(L.t("安装包里没有找到 SwitchNetwork.app"))
        }
        do {
            try verifyApp(at: sourceApp, expectedVersion: info.version)
        } catch {
            return .failed(error.localizedDescription)
        }

        progress(.installing)
        do {
            try swapIn(sourceApp)
        } catch {
            return .failed(L.t("替换应用失败：%@", error.localizedDescription))
        }
        // 新 app 不该带隔离属性。URLSession 下载的 dmg 本来就没有，
        // 这一步是兜底，失败了也不影响使用。
        _ = try? clearQuarantine(installedAppURL)
        refreshLaunchServices()

        progress(.restarting)
        relaunchAndQuit()
        return .installed(version: info.version)
    }

    private static func performRollback(progress: @escaping (UpdateInstallStage) -> Void) -> UpdateInstallOutcome {
        guard isRunningFromApplications else {
            return .failed(L.t("当前不是从「应用程序」里运行的，不能回退。"))
        }

        let source = previousAppURL
        guard let bundle = Bundle(url: source) else {
            return .failed(L.t("上一个版本的备份读不出来，回退已取消。"))
        }
        // 回退前先确认备份还是本应用：宁可留在当前版本，也别把好的那版换成一个坏的。
        if bundle.bundleIdentifier != Bundle.main.bundleIdentifier {
            return .failed(L.t("上一个版本的备份不是完整的 SwitchNetwork，回退已取消。"))
        }
        var version = ""
        let info = bundle.infoDictionary
        if let info = info, let value = info["CFBundleShortVersionString"] as? String {
            version = value
        }

        progress(.installing)
        do {
            try swapIn(source)
        } catch {
            return .failed(L.t("回退失败：%@", error.localizedDescription))
        }
        _ = try? clearQuarantine(installedAppURL)
        refreshLaunchServices()

        progress(.restarting)
        relaunchAndQuit()
        return .installed(version: version)
    }

    // MARK: - 替换

    /// 把 source 里的 app 换到「应用程序」里，替掉正在运行的这一份。
    private static func swapIn(_ source: URL) throws {
        let manager = FileManager.default
        let apps = installedAppURL.deletingLastPathComponent()
        let staging = apps.appendingPathComponent(".SwitchNetwork.new.app", isDirectory: true)
        let aside = apps.appendingPathComponent(".SwitchNetwork.old.app", isDirectory: true)

        // admin 组的成员对 /Applications 通常直接可写，不需要弹密码框。
        // 不可写就老实说，让用户手动装——用 root 脚本搬一个正在运行的 bundle
        // 风险比这大得多。
        guard manager.isWritableFile(atPath: apps.path) else {
            throw InstallError(message: L.t("没有权限写入「应用程序」文件夹，请下载 dmg 手动安装。"))
        }

        // 上一轮失败留下的残骸先清掉。只动这两个自己命名的临时目录。
        try? manager.removeItem(at: staging)
        try? manager.removeItem(at: aside)

        try runDitto(from: source, to: staging)

        do {
            try manager.moveItem(at: installedAppURL, to: aside)
        } catch {
            try? manager.removeItem(at: staging)
            throw InstallError(message: L.t("腾出原来那份应用失败：%@", error.localizedDescription))
        }

        do {
            try manager.moveItem(at: staging, to: installedAppURL)
        } catch {
            try? manager.moveItem(at: aside, to: installedAppURL)
            try? manager.removeItem(at: staging)
            throw InstallError(message: L.t("放入新版本失败：%@", error.localizedDescription))
        }

        keepPreviousVersion(from: aside)
    }

    /// 把让位下来的旧版本收进本机备份目录，供「回退」用。
    /// 收不进去也不算更新失败，只是没有回退可用。
    private static func keepPreviousVersion(from aside: URL) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: previousAppURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true,
                                        attributes: nil)
            try? manager.removeItem(at: previousAppURL)
            try manager.moveItem(at: aside, to: previousAppURL)
        } catch {
            Log.shared.warning(L.t("旧版本没能留成备份，这次没有回退可用：%@", error.localizedDescription))
            try? manager.removeItem(at: aside)
        }
    }

    /// 用 ditto 而不是 FileManager 拷贝：它会把符号链接、扩展属性一起原样带过去，
    /// 拷出来的 bundle 签名才不会被破坏。
    private static func runDitto(from source: URL, to destination: URL) throws {
        let result = try Shell.run("/usr/bin/ditto", [source.path, destination.path], timeout: 180)
        guard result.succeeded else {
            throw InstallError(message: L.t("复制新版本失败：%@", result.combinedMessage))
        }
    }

    // MARK: - 镜像

    private static func attach(_ dmg: URL, at mountPoint: URL) throws {
        let result = try Shell.run("/usr/bin/hdiutil",
                                   ["attach", dmg.path,
                                    "-nobrowse", "-readonly", "-noverify",
                                    "-mountpoint", mountPoint.path],
                                   timeout: 180)
        guard result.succeeded else {
            throw InstallError(message: L.t("打开安装包失败：%@", result.combinedMessage))
        }
    }

    private static func detach(_ mountPoint: URL) {
        // 卸载失败不影响已经装好的版本，最多留一个挂载点。
        guard let result = try? Shell.run("/usr/bin/hdiutil",
                                          ["detach", mountPoint.path, "-force"],
                                          timeout: 60) else { return }
        if !result.succeeded {
            Log.shared.warning(L.t("卸载安装包失败：%@", result.combinedMessage))
        }
    }

    /// 确认镜像里的 app 就是本应用、版本对得上、签名完整。
    /// 防的是「下到别的文件」和「下到半截的文件」。
    private static func verifyApp(at url: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: url) else {
            throw InstallError(message: L.t("安装包里的 app 读不出来"))
        }
        if bundle.bundleIdentifier != Bundle.main.bundleIdentifier {
            throw InstallError(message: L.t("安装包里的不是 SwitchNetwork"))
        }
        var version = ""
        let info = bundle.infoDictionary
        if let info = info, let value = info["CFBundleShortVersionString"] as? String {
            version = value
        }
        guard version == expectedVersion else {
            throw InstallError(message: L.t("安装包里的版本是 %@，和要装的 %@ 对不上", version, expectedVersion))
        }
        let result = try Shell.run("/usr/bin/codesign",
                                   ["--verify", "--deep", "--strict", url.path],
                                   timeout: 180)
        guard result.succeeded else {
            throw InstallError(message: L.t("签名校验没通过：%@", result.combinedMessage))
        }
    }

    // MARK: - 下载与校验

    /// 校验 SHA256。Release 里没带 `.sha256` 附件就跳过，只写日志。
    private static func verifyChecksum(of file: URL, info: UpdateInfo) throws {
        guard let checksumURL = info.checksumURL else {
            Log.shared.warning(L.t("这个版本没带校验和附件，跳过 SHA256 校验"))
            return
        }
        let text = try fetchText(checksumURL)
        // shasum 的格式是「<hash>  <文件名>」，只取第一段。
        let fields = text.split { character in
            character == " " || character == "\n" || character == "\t" || character == "\r"
        }
        guard let first = fields.first else {
            throw InstallError(message: L.t("校验和附件是空的"))
        }
        let expected = String(first).lowercased()
        guard expected == sha256Hex(of: file) else {
            throw InstallError(message: L.t("下载到的文件校验和不一致，已放弃安装（多半是没下完）"))
        }
    }

    private static func sha256Hex(of file: URL) -> String {
        let data = (try? Data(contentsOf: file)) ?? Data()
        return SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }

    private static func download(_ url: URL, to destination: URL) throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        request.setValue("SwitchNetwork/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var failure: String?
        var statusCode = 0

        let task = URLSession.shared.downloadTask(with: request) { location, response, error in
            defer { semaphore.signal() }
            if let error = error {
                failure = error.localizedDescription
                return
            }
            if let http = response as? HTTPURLResponse {
                statusCode = http.statusCode
            }
            guard let location = location else {
                failure = L.t("下载没有返回文件")
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                failure = error.localizedDescription
            }
        }
        task.resume()
        semaphore.wait()

        if let failure = failure {
            throw InstallError(message: failure)
        }
        guard statusCode == 200 else {
            throw InstallError(message: L.t("下载返回了 %d", statusCode))
        }
        var size = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let number = attributes[.size] as? Int {
            size = number
        }
        if size == 0 {
            throw InstallError(message: L.t("下载到的文件是空的"))
        }
    }

    private static func fetchText(_ url: URL) throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("SwitchNetwork/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var text: String?
        var failure: String?

        let task = URLSession.shared.downloadTask(with: request) { location, response, error in
            defer { semaphore.signal() }
            if let error = error {
                failure = error.localizedDescription
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = L.t("取校验和失败：HTTP %d", http.statusCode)
                return
            }
            guard let location = location else {
                failure = L.t("取校验和没有返回内容")
                return
            }
            do {
                let data = try Data(contentsOf: location)
                text = String(decoding: data, as: UTF8.self)
            } catch {
                failure = error.localizedDescription
            }
        }
        task.resume()
        semaphore.wait()

        if let failure = failure {
            throw InstallError(message: failure)
        }
        guard let text = text else {
            throw InstallError(message: L.t("取校验和失败"))
        }
        return text
    }

    // MARK: - 收尾

    private static func clearQuarantine(_ app: URL) throws {
        try Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path], timeout: 60)
    }

    /// 让 LaunchServices 立刻认到新的 bundle，否则图标和「打开方式」还可能是旧的。
    private static func refreshLaunchServices() {
        let tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard FileManager.default.fileExists(atPath: tool) else { return }
        _ = try? Shell.run(tool, ["-f", installedAppURL.path], timeout: 60)
    }

    /// 等自己退干净再重新打开。
    /// 用绝对路径加 `-n`：`open -a` 是按名字解析的，可能又命中刚被换掉的那份。
    private static func relaunchAndQuit() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.3; done; "
            + "/usr/bin/open -n '\(installedAppURL.path)'"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            Log.shared.error(L.t("重启失败，请手动打开应用：%@", error.localizedDescription))
            return
        }
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    // MARK: - 路径

    private static var cacheDirectory: URL {
        let manager = FileManager.default
        let base = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
        var root: URL
        if let base = base {
            root = base
        } else {
            root = manager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches", isDirectory: true)
        }
        return root.appendingPathComponent("SwitchNetwork", isDirectory: true)
    }

    /// 比较路径时去掉结尾的斜杠：bundle 的 URL 有时带、有时不带。
    private static func comparablePath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
