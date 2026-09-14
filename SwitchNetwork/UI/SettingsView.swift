import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    /// 打开日志查看器（由主窗口以 sheet 形式呈现）。
    let showLog: () -> Void

    @State private var isShowingSudoersDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            appearanceSection
            generalSection
            permissionSection
            dataSection
            UpdateSection()
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        SectionGroup(title: L.t("外观"),
                     subtitle: L.t("跟随系统时会随系统的浅色/深色切换自动变化，菜单栏面板也一并生效")) {
            Card {
                CardRow(icon: Symbols.resolve("circle.lefthalf.filled", fallback: "circle"),
                        title: L.t("主题"),
                        subtitle: L.t("切换后立即生效，不需要重启"),
                        showsHover: false) {
                    Picker("", selection: $state.settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 220)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("dock.rectangle", fallback: "square"),
                        title: L.t("在 Dock 中显示图标"),
                        subtitle: L.t("关掉之后应用只驻留在菜单栏，不会占用 Dock 和 ⌘Tab（这是默认行为）"),
                        showsHover: false) {
                    SwitchToggle(isOn: $state.settings.showInDock)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("globe", fallback: "network"),
                        title: L.t("界面语言"),
                        subtitle: L.t("默认跟随系统语言。切换后界面立即重建，不需要重启"),
                        showsHover: false) {
                    Picker("", selection: $state.settings.language) {
                        ForEach(LanguageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 260)
                }
            }
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        SectionGroup(title: L.t("启动")) {
            Card {
                CardRow(icon: Symbols.resolve("power", fallback: "bolt"),
                        title: L.t("开机自动启动"),
                        subtitle: loginSubtitle,
                        showsHover: false) {
                    HStack(spacing: 8) {
                        if needsLoginItemApproval {
                            SecondaryButton(title: L.t("打开登录项设置"), symbol: "arrow.up.forward.app") {
                                SystemCompat.openLoginItemsSettings()
                            }
                        }
                        SwitchToggle(isOn: $state.settings.launchAtLogin)
                    }
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("arrow.clockwise.circle", fallback: "arrow.clockwise"),
                        title: L.t("登录后立即刷新接口状态"),
                        subtitle: L.t("刷新会重新读取接口、链路状态和当前 IP，可随时手动执行")) {
                    SecondaryButton(title: L.t("刷新"), symbol: "arrow.clockwise") {
                        state.refreshAll()
                    }
                }
            }
        }
    }

    // MARK: - 权限

    private var permissionSection: some View {
        SectionGroup(title: L.t("权限"),
                     subtitle: L.t("改 IP、增删路由必须以 root 身份执行。安装一次免密授权后，自动应用才不会因为权限不足而失败")) {
            Card {
                CardRow(icon: Symbols.resolve(state.privilegeGranted ? "checkmark.shield" : "lock.shield",
                                              fallback: "lock"),
                        iconTint: state.privilegeGranted ? Theme.successColor : Theme.warningColor,
                        title: state.privilegeGranted ? L.t("免密授权已生效") : L.t("免密授权未安装"),
                        subtitle: state.privilegeGranted
                            ? L.t("已授权：/usr/sbin/networksetup、/sbin/route")
                            : L.t("只授权这两条命令、仅限 admin 组成员，改动范围比输入密码更可控"),
                        titleAccessory: AnyView(TagChip(text: state.privilegeGranted ? L.t("已就绪") : L.t("未完成"),
                                                        tint: state.privilegeGranted ? Theme.successColor : Theme.warningColor))) {
                    HStack(spacing: 8) {
                        if !state.privilegeGranted {
                            PrimaryButton(title: state.isInstallingPrivilege ? L.t("等待授权…") : L.t("一键安装授权"),
                                          symbol: "lock.open",
                                          disabled: state.isInstallingPrivilege) {
                                state.installPrivilegeAuthorization()
                            }
                        }
                        SecondaryButton(title: L.t("重新检测"), symbol: "arrow.clockwise") {
                            state.refreshPrivilegeStatus()
                        }
                        SecondaryButton(title: isShowingSudoersDetail ? L.t("收起命令") : L.t("查看安装命令"),
                                        symbol: isShowingSudoersDetail ? "chevron.up" : "chevron.down") {
                            isShowingSudoersDetail.toggle()
                        }
                    }
                }

                if isShowingSudoersDetail {
                    CardRowDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        if !PrivilegeManager.isCurrentUserAdmin() {
                            hintLine(symbol: Symbols.resolve("exclamationmark.triangle.fill",
                                                             fallback: "exclamationmark.triangle"),
                                     tint: Theme.dangerColor,
                                     text: L.t("当前用户 %@ 不在 admin 组，这条规则对它不生效。", PrivilegeManager.currentUserName()))
                        }
                        hintLine(symbol: Symbols.resolve("info.circle", fallback: "info"),
                                 tint: Color.secondary,
                                 text: L.t("上面的按钮会弹一次系统密码框，输完即装好。不想用按钮，就在「终端」里粘贴执行下面这行，效果完全一样，也只需做一次。"))
                        CopyableCommand(command: PrivilegeManager.installCommand)

                        Divider()

                        hintLine(symbol: Symbols.resolve("trash", fallback: "trash"),
                                 tint: Color.secondary,
                                 text: L.t("想撤销授权就执行这行："))
                        CopyableCommand(command: PrivilegeManager.uninstallCommand)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        SectionGroup(title: L.t("数据")) {
            Card {
                CardRow(icon: Symbols.resolve("doc.text", fallback: "doc"),
                        title: L.t("运行日志"),
                        subtitle: L.t("记录每次应用配置的逐项结果，排查「为什么没自动生效」时看这里")) {
                    SecondaryButton(title: L.t("查看日志"), symbol: "list.bullet.rectangle", action: showLog)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("folder", fallback: "folder"),
                        title: L.t("配置文件位置"),
                        subtitle: "\(state.storageLocationLabel) · \(state.storageLocationPath)") {
                    SecondaryButton(title: L.t("在访达中打开"), symbol: "arrow.up.forward.app") {
                        let path = state.storageLocationPath
                        // 一份配置都还没存过时目录还不存在，先建出来再去，免得访达报找不到。
                        try? FileManager.default.createDirectory(atPath: path,
                                                                 withIntermediateDirectories: true,
                                                                 attributes: nil)
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("gearshape", fallback: "gear"),
                        title: L.t("设置文件位置"),
                        subtitle: L.t("开机启动、Dock 图标、网络服务顺序这些都跟具体机器绑定，所以设置留在本机：%@",
                                      JSONStore.directory(for: .local).path),
                        showsHover: false)
                CardRowDivider()
                CardRow(icon: Symbols.resolve("trash", fallback: "trash"),
                        title: L.t("回收站保留天数"),
                        subtitle: L.t("删除的配置先放回收站，超过这个天数才真的从磁盘上删掉"),
                        showsHover: false) {
                    Stepper(value: $state.settings.trashRetentionDays, in: 1...365) {
                        Text(L.t("%d 天", state.settings.trashRetentionDays))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(width: 110)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("doc.zipper", fallback: "doc"),
                        title: L.t("日志文件位置"),
                        subtitle: Log.shared.fileURL.path) {
                    SecondaryButton(title: L.t("在访达中显示"), symbol: "arrow.up.forward.app") {
                        NSWorkspace.shared.activateFileViewerSelecting([Log.shared.fileURL])
                    }
                }
            }
        }
    }

    // MARK: - 计算

    private var loginSubtitle: String {
        switch state.loginItemState {
        case .enabled:
            return L.t("已开启。开机后会驻留在菜单栏，接口连上时自动应用配置")
        case .disabled:
            return L.t("开启后开机自动驻留菜单栏")
        case .requiresApproval:
            return L.t("系统还要求在「登录项」里手动允许一次，点右边按钮去打开")
        case .failed(let message):
            return L.t("设置失败：%@", message)
        }
    }

    private var needsLoginItemApproval: Bool {
        switch state.loginItemState {
        case .requiresApproval, .failed:
            return true
        case .enabled, .disabled:
            return false
        }
    }

    private func hintLine(symbol: String, tint: Color, text: String) -> some View {
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundColor(tint)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
