import SwiftUI
import AppKit

/// 设置页的「更新」分组：版本、检查更新、下载安装、回退。
///
/// 这里只负责展示。所有网络和替换的动作都交给 UpdateChecker / UpdateInstaller，
/// 失败一律变成这一行里的一句提示，不影响任何主功能。
struct UpdateSection: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var controller = UpdateController()

    var body: some View {
        SectionGroup(title: L.t("更新"),
                     subtitle: L.t("启动后自动查一次，也可以随时手动查。只是向 GitHub 问一下版本号，不上传任何东西")) {
            Card {
                CardRow(icon: Symbols.resolve("app.badge", fallback: "app"),
                        title: L.t("SwitchNetwork %@", AppInfo.displayVersion),
                        subtitle: L.t("配置共 %d 份", state.profiles.count),
                        showsHover: false) {
                    HStack(spacing: 8) {
                        if UpdateInstaller.hasPreviousVersion {
                            SecondaryButton(title: L.t("回退到上一个版本"),
                                            symbol: "arrow.uturn.backward",
                                            disabled: controller.isBusy) {
                                controller.rollback()
                            }
                        }
                        SecondaryButton(title: L.t("检查更新"),
                                        symbol: "arrow.triangle.2.circlepath",
                                        disabled: controller.isBusy) {
                            controller.check { info in
                                state.recordUpdateCheck(available: info)
                            }
                        }
                    }
                }

                CardRowDivider()
                statusRow
            }
        }
    }

    // MARK: - 状态行

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.system(size: 11))
                .foregroundColor(statusTint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = statusDetail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notes = releaseNotes {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let info = installableUpdate {
                    PrimaryButton(title: L.t("下载并安装"),
                                  symbol: "arrow.down.circle",
                                  disabled: controller.isBusy) {
                        controller.install(info)
                    }
                }
                if showsReleasePageButton {
                    SecondaryButton(title: L.t("打开发布页"), symbol: "arrow.up.forward.app") {
                        controller.openReleasePage()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var statusSymbol: String {
        switch controller.status {
        case .checking, .installing:
            return Symbols.resolve("arrow.triangle.2.circlepath", fallback: "arrow.clockwise")
        case .failed, .noAsset:
            return Symbols.resolve("exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
        case .upToDate:
            return Symbols.resolve("checkmark.circle.fill", fallback: "checkmark.circle")
        case .available:
            return Symbols.resolve("arrow.down.circle.fill", fallback: "arrow.down.circle")
        case .idle:
            if pendingUpdate != nil {
                return Symbols.resolve("arrow.down.circle.fill", fallback: "arrow.down.circle")
            }
            return Symbols.resolve("info.circle", fallback: "info")
        }
    }

    private var statusTint: Color {
        switch controller.status {
        case .failed, .noAsset:
            return Theme.warningColor
        case .upToDate:
            return Theme.successColor
        case .available:
            return Theme.accent
        case .idle:
            return pendingUpdate == nil ? Color.secondary : Theme.accent
        case .checking, .installing:
            return Color.secondary
        }
    }

    private var statusTitle: String {
        switch controller.status {
        case .idle:
            if let info = pendingUpdate {
                return L.t("发现新版本 %@", info.version)
            }
            if let last = UpdateChecker.shared.lastCheckedAt {
                return L.t("已经是最新版本（检查于 %@）", UpdateSection.timeText(last))
            }
            return L.t("还没检查过")
        case .checking:
            return L.t("正在检查有没有新版本…")
        case .installing(let stage):
            return stage.label
        case .upToDate(let remote):
            return L.t("已经是最新版本（线上是 %@）", remote)
        case .available(let info), .noAsset(let info):
            return L.t("发现新版本 %@", info.version)
        case .failed(let message):
            return message
        }
    }

    private var statusDetail: String? {
        switch controller.status {
        case .idle:
            if pendingUpdate != nil {
                return L.t("启动时查到有新版本，点右边的按钮可以下载安装")
            }
            return nil
        case .checking:
            return nil
        case .upToDate:
            if let last = UpdateChecker.shared.lastCheckedAt {
                return L.t("检查于 %@", UpdateSection.timeText(last))
            }
            return nil
        case .available:
            if !UpdateInstaller.isRunningFromApplications {
                return L.t("当前不是从「应用程序」里运行的，不能自动替换，请到发布页下载")
            }
            return L.t("当前是 %@，装完会自动重新打开", AppInfo.displayVersion)
        case .noAsset:
            return L.t("这个版本没有提供 dmg 附件，请到发布页下载")
        case .installing:
            return L.t("替换过程中请不要退出应用")
        case .failed:
            return nil
        }
    }

    private var releaseNotes: String? {
        guard let info = pendingUpdate else { return nil }
        let notes = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty { return nil }
        return notes
    }

    // MARK: - 计算

    /// 手动查的结果优先；这一轮没手动查过就用启动时静默查到的。
    private var pendingUpdate: UpdateInfo? {
        switch controller.status {
        case .available(let info):
            return info
        case .noAsset(let info):
            return info
        default:
            return state.availableUpdate
        }
    }

    /// 能直接下载安装的那一个。没带 dmg 附件、或不是从「应用程序」里运行的都算不能。
    private var installableUpdate: UpdateInfo? {
        guard UpdateInstaller.isRunningFromApplications else { return nil }
        switch controller.status {
        case .available(let info):
            return info
        case .noAsset:
            return nil
        default:
            break
        }
        if let info = state.availableUpdate, info.dmgURL != nil {
            return info
        }
        return nil
    }

    private var showsReleasePageButton: Bool {
        if !UpdateInstaller.isRunningFromApplications { return true }
        switch controller.status {
        case .failed, .noAsset:
            return true
        default:
            return false
        }
    }

    private static func timeText(_ date: Date) -> String {
        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

/// 这次检查/安装走到哪了。只在设置页里用，所以不放进 AppState。
final class UpdateController: ObservableObject {

    enum Status {
        case idle
        case checking
        case upToDate(remote: String)
        case available(UpdateInfo)
        /// 有新版本但没有 dmg 附件。
        case noAsset(UpdateInfo)
        case installing(UpdateInstallStage)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    var isBusy: Bool {
        switch status {
        case .checking, .installing:
            return true
        default:
            return false
        }
    }

    /// 查一次。completion 带出查到的可安装版本（没有就是 nil）。
    func check(completion: @escaping (UpdateInfo?) -> Void) {
        status = .checking
        UpdateChecker.shared.check { outcome in
            switch outcome {
            case .upToDate(let remote):
                self.status = .upToDate(remote: remote)
                completion(nil)
            case .available(let info):
                self.status = .available(info)
                completion(info)
            case .noDownloadableAsset(let info):
                self.status = .noAsset(info)
                completion(info)
            case .failed(let message):
                self.status = .failed(message)
                completion(nil)
            }
        }
    }

    func install(_ info: UpdateInfo) {
        UpdateInstaller.install(info, progress: { stage in
            self.status = .installing(stage)
        }, completion: { outcome in
            // 成功的话应用马上就会退出，用户看不到提示；失败要留在界面上。
            if case .failed(let message) = outcome {
                self.status = .failed(message)
            }
        })
    }

    func rollback() {
        UpdateInstaller.rollback(progress: { stage in
            self.status = .installing(stage)
        }, completion: { outcome in
            if case .failed(let message) = outcome {
                self.status = .failed(message)
            }
        })
    }

    func openReleasePage() {
        guard let url = AppInfo.releasesPageURL else { return }
        NSWorkspace.shared.open(url)
    }
}
