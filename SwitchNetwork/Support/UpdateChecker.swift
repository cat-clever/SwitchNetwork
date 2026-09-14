import Foundation

/// 版本号与仓库地址。
///
/// 唯一的来源是仓库根的 `Config/SwitchNetwork.xcconfig`：构建设置把它展开进 Info.plist，
/// 运行时从这里读。所以换仓库、改版本号都不需要动 Swift 代码。
enum AppInfo {

    /// Info.plist 里没有这个键时用的兜底值。
    /// 万一 xcconfig 没生效（或有人手工改了 Info.plist），检查更新也该照常能用。
    private static let fallbackRepo = "cat-clever/SwitchNetwork"

    private static var infoDictionary: [String: Any]? {
        return Bundle.main.infoDictionary
    }

    static var version: String {
        if let info = infoDictionary,
           let value = info["CFBundleShortVersionString"] as? String,
           !value.isEmpty {
            return value
        }
        return "0.0.0"
    }

    static var build: String {
        if let info = infoDictionary,
           let value = info["CFBundleVersion"] as? String {
            return value
        }
        return ""
    }

    /// 界面上显示的版本，形如 `0.0.1 (1)`。
    static var displayVersion: String {
        let buildNumber = build
        if buildNumber.isEmpty { return version }
        return "\(version) (\(buildNumber))"
    }

    /// 形如 `owner/name`。
    static var githubRepo: String {
        if let info = infoDictionary,
           let value = info["SwitchNetworkGitHubRepo"] as? String,
           !value.isEmpty {
            return value
        }
        return fallbackRepo
    }

    static var releasesPageURL: URL? {
        return URL(string: "https://github.com/\(githubRepo)/releases")
    }

    static var latestReleaseAPIURL: URL? {
        return URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")
    }

    /// candidate 是不是比 current 新。
    ///
    /// 按数值逐段比，不能比字符串：字符串比较会把 `0.0.10` 判成小于 `0.0.9`。
    /// 段数不一样时短的补 0，所以 `0.1` 和 `0.1.0` 视为相同。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = numericParts(candidate)
        let right = numericParts(current)
        var index = 0
        while index < left.count || index < right.count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
            index += 1
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        // 预发布后缀（1.2.3-beta.1）不参与比较，按正式版看。
        let core = version.prefix { $0 != "-" }
        return core.split(separator: ".").map { segment in
            Int(segment.prefix { $0.isNumber }) ?? 0
        }
    }
}

/// 一次检查更新查到的内容。
struct UpdateInfo: Equatable {
    /// 版本号，已经去掉 tag 上的 `v` 前缀。
    let version: String
    /// Release 说明原文。
    let notes: String
    /// Release 附件里的 dmg。
    let dmgURL: URL?
    /// dmg 的校验和附件（同名再加 `.sha256`）。
    let checksumURL: URL?
    /// 发布页。拿不到附件时让用户自己去下。
    let pageURL: URL?
}

enum UpdateCheckOutcome {
    /// 已经是最新的（或本地版本比线上还新）。
    case upToDate(remote: String)
    /// 有新版本，而且能直接下 dmg。
    case available(UpdateInfo)
    /// 有新版本，但 Release 里没有 dmg 附件，只能去网页下。
    case noDownloadableAsset(UpdateInfo)
    case failed(String)
}

/// 查 GitHub 上最新一个 Release。
///
/// 用 Release 接口而不是自己维护一份清单文件：少一个要发布、要校验、还可能忘记更新的东西。
/// 代价是走 GitHub API（未认证时每小时 60 次），所以只在启动后查一次和用户手动点的时候查。
final class UpdateChecker {

    static let shared = UpdateChecker()

    /// 上次查到结果的时间。
    private(set) var lastCheckedAt: Date?

    private init() {}

    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: URL?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    /// 查一次。回调在主线程。
    func check(completion: @escaping (UpdateCheckOutcome) -> Void) {
        guard let url = AppInfo.latestReleaseAPIURL else {
            finish(.failed(L.t("更新地址不合法，检查更新暂时不可用")), completion)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // GitHub 要求带 User-Agent，不带就直接 403。
        request.setValue("SwitchNetwork/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let checker = self else { return }

            if let error = error {
                checker.finish(.failed(L.t("连不上 GitHub：%@", error.localizedDescription)), completion)
                return
            }

            var statusCode = 0
            if let http = response as? HTTPURLResponse {
                statusCode = http.statusCode
            }
            switch statusCode {
            case 200:
                break
            case 404:
                checker.finish(.failed(L.t("仓库 %@ 还没有发布过版本", AppInfo.githubRepo)), completion)
                return
            case 403, 429:
                checker.finish(.failed(L.t("GitHub 接口暂时不可用（多半是请求太频繁），过一会儿再试")), completion)
                return
            default:
                checker.finish(.failed(L.t("GitHub 返回了 %d", statusCode)), completion)
                return
            }

            guard let data = data else {
                checker.finish(.failed(L.t("GitHub 没有返回内容")), completion)
                return
            }
            do {
                let release = try JSONDecoder().decode(Release.self, from: data)
                checker.finish(checker.evaluate(release), completion)
            } catch {
                checker.finish(.failed(L.t("解析发布信息失败：%@", error.localizedDescription)), completion)
            }
        }
        task.resume()
    }

    private func evaluate(_ release: Release) -> UpdateCheckOutcome {
        lastCheckedAt = Date()

        var remote = release.tagName
        if remote.hasPrefix("v") {
            remote = String(remote.dropFirst())
        }

        var dmg: Asset?
        for asset in release.assets {
            if asset.name.lowercased().hasSuffix(".dmg") {
                dmg = asset
                break
            }
        }

        var checksum: Asset?
        if let dmgAsset = dmg {
            let wanted = dmgAsset.name + ".sha256"
            for asset in release.assets where asset.name == wanted {
                checksum = asset
                break
            }
        }

        var dmgURL: URL?
        if let dmgAsset = dmg { dmgURL = dmgAsset.browserDownloadURL }
        var checksumURL: URL?
        if let checksumAsset = checksum { checksumURL = checksumAsset.browserDownloadURL }

        let info = UpdateInfo(version: remote,
                              notes: release.body ?? "",
                              dmgURL: dmgURL,
                              checksumURL: checksumURL,
                              pageURL: release.htmlURL)

        guard AppInfo.isNewer(remote, than: AppInfo.version) else {
            return .upToDate(remote: remote)
        }
        if dmgURL == nil {
            return .noDownloadableAsset(info)
        }
        return .available(info)
    }

    private func finish(_ outcome: UpdateCheckOutcome,
                        _ completion: @escaping (UpdateCheckOutcome) -> Void) {
        DispatchQueue.main.async {
            completion(outcome)
        }
    }
}
