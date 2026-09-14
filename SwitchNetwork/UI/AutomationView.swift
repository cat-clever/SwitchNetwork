import SwiftUI

struct AutomationView: View {
    @EnvironmentObject private var state: AppState

    /// 没有配置可选的接口，引导用户去「配置管理」建一份。
    let onNavigateToProfiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            masterSection
            interfaceSection
            permissionSection
        }
    }

    // MARK: - 总开关

    private var masterSection: some View {
        SectionGroup(title: L.t("自动应用"),
                     subtitle: L.t("只在接口「未连接 → 已连接」的那一刻触发，已经连着的接口不会被动改写")) {
            Card {
                CardRow(icon: Symbols.resolve("bolt.fill", fallback: "bolt"),
                        iconTint: Theme.accent,
                        title: L.t("启用自动应用"),
                        subtitle: L.t("总开关。关掉之后，所有标记为自动应用的配置都不会再自动生效"),
                        showsHover: false) {
                    SwitchToggle(isOn: $state.settings.autoApplyEnabled)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("clock.arrow.circlepath", fallback: "clock"),
                        title: L.t("启动时校正一次"),
                        subtitle: L.t("开机或重新打开应用后，把已连接接口的配置对齐到自动配置（等系统网络就绪约 5 秒后执行）"),
                        showsHover: false) {
                    SwitchToggle(isOn: $state.settings.reconcileOnLaunch)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("timer", fallback: "clock"),
                        title: L.t("连接事件防抖"),
                        subtitle: L.t("接口插上后系统还会陆续下发配置，等 %@ 再动手，避免打断系统自己的流程", debounceText),
                        showsHover: false) {
                    HStack(spacing: 10) {
                        Stepper(value: $state.settings.debounceSeconds, in: 0.5...10, step: 0.5) {
                            Text(debounceText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 46, alignment: .trailing)
                        }
                        .fixedSize()
                    }
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("arrow.triangle.2.circlepath", fallback: "arrow.clockwise"),
                        iconTint: Theme.accent,
                        title: L.t("立即按自动配置校正"),
                        subtitle: L.t("不用插拔网线，现在就把所有已连接接口对齐一遍")) {
                    SecondaryButton(title: L.t("现在校正"), symbol: "play.fill") {
                        state.reconcileNow(reason: L.t("手动校正"))
                    }
                }
            }
        }
    }

    // MARK: - 各接口的自动配置

    private var interfaceSection: some View {
        SectionGroup(title: L.t("各接口的自动配置"),
                     subtitle: L.t("每个接口最多只能有一份配置被标记为自动应用，互不影响")) {
            VStack(spacing: 12) {
                if state.interfaces.isEmpty {
                    Card {
                        EmptyHint(text: L.t("正在读取网络接口…"))
                    }
                } else {
                    ForEach(state.interfaces) { status in
                        automationCard(for: status)
                    }
                }
            }
        }
    }

    private func automationCard(for status: InterfaceStatus) -> some View {
        let owned = state.profiles(for: status.identifier)
        let auto = state.autoProfile(for: status.identifier)
        let accessory: AnyView? = auto == nil ? nil : AnyView(TagChip(text: L.t("自动")))

        return Card {
            VStack(alignment: .leading, spacing: 0) {
                CardRow(icon: status.type.symbolName,
                        iconTint: status.isConnected ? Theme.successColor : Color.secondary,
                        title: "\(status.identifier) · \(status.displayName)",
                        subtitle: status.isConnected ? L.t("已连接 · %@", status.currentIPLabel) : L.t("未连接"),
                        titleAccessory: accessory,
                        showsHover: false) {
                    if owned.isEmpty {
                        SecondaryButton(title: L.t("去新建"), symbol: "plus") {
                            onNavigateToProfiles()
                        }
                    } else {
                        Picker("", selection: autoSelectionBinding(for: status.identifier)) {
                            Text(L.t("不自动应用")).tag("")
                            ForEach(owned) { profile in
                                Text(profile.name).tag(profile.id.uuidString)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
                if let target = auto {
                    CardRowDivider()
                    autoDetailRow(status: status, target: target)
                }
            }
        }
    }

    private func autoDetailRow(status: InterfaceStatus, target: Profile) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stateSymbol(for: status, target: target))
                .font(.system(size: 12))
                .foregroundColor(stateTint(for: status, target: target))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(autoStateText(for: status, target: target))
                    .font(.system(size: 11.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(autoTargetText(target))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - 权限

    private var permissionSection: some View {
        SectionGroup(title: L.t("权限"),
                     subtitle: L.t("改 IP、增删路由都要 root 权限。装一次免密授权，之后自动应用才不会静默失败")) {
            Card {
                CardRow(icon: Symbols.resolve(state.privilegeGranted ? "checkmark.shield" : "lock.shield",
                                              fallback: "lock"),
                        iconTint: state.privilegeGranted ? Theme.successColor : Theme.warningColor,
                        title: state.privilegeGranted ? L.t("免密授权已就绪") : L.t("尚未安装免密授权"),
                        subtitle: state.privilegeGranted
                            ? L.t("networksetup 与 route 已可通过 sudo 免密执行")
                            : L.t("没有授权时，自动应用会因为没有权限而失败，配置也写不进去")) {
                    SecondaryButton(title: L.t("重新检测"), symbol: "arrow.clockwise") {
                        state.refreshPrivilegeStatus()
                    }
                }
            }
        }
    }

    // MARK: - 计算

    private var debounceText: String {
        if state.settings.debounceSeconds == state.settings.debounceSeconds.rounded() {
            return L.t("%d 秒", Int(state.settings.debounceSeconds))
        }
        return L.t("%.1f 秒", state.settings.debounceSeconds)
    }

    private func autoSelectionBinding(for identifier: String) -> Binding<String> {
        return Binding(get: {
            if let auto = state.autoProfile(for: identifier) { return auto.id.uuidString }
            return ""
        }, set: { newValue in
            for profile in state.profiles(for: identifier) {
                let shouldEnable = profile.id.uuidString == newValue
                if profile.autoApplyOnConnect != shouldEnable {
                    state.setAutoApply(profileID: profile.id, enabled: shouldEnable)
                }
            }
        })
    }

    private func stateSymbol(for status: InterfaceStatus, target: Profile) -> String {
        if !status.isConnected {
            return Symbols.resolve("moon.zzz", fallback: "clock")
        }
        if !state.privilegeGranted {
            return Symbols.resolve("lock.fill", fallback: "lock")
        }
        if status.matches(target) && !state.needsServicePromotion(target) {
            return Symbols.resolve("checkmark.circle.fill", fallback: "checkmark.circle")
        }
        return Symbols.resolve("exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
    }

    private func stateTint(for status: InterfaceStatus, target: Profile) -> Color {
        if !status.isConnected { return Color.secondary }
        if !state.privilegeGranted { return Theme.warningColor }
        return status.matches(target) && !state.needsServicePromotion(target) ? Theme.successColor : Theme.warningColor
    }

    private func autoTargetText(_ target: Profile) -> String {
        var parts = [L.t("目标：%@", target.ipSummary)]
        if let gateway = target.gatewaySummary { parts.append(gateway) }
        parts.append(target.dnsSummary)
        return parts.joined(separator: L.commaSeparator)
    }

    private func autoStateText(for status: InterfaceStatus, target: Profile) -> String {
        if !status.isConnected {
            return L.t("等待接口连接，连上后会自动写入「%@」", target.name)
        }
        if !state.privilegeGranted {
            return L.t("缺少 root 权限，无法自动应用「%@」", target.name)
        }
        if status.matches(target) {
            // IP/DNS/路由都对上了，但这份配置要求置顶而顺序没到位，不能算已生效。
            if state.needsServicePromotion(target) {
                return L.t("当前配置已符合「%@」，但还没排到服务顺序第一位", target.name)
            }
            return L.t("当前配置已符合「%@」", target.name)
        }
        return L.t("当前配置与「%@」不一致，插拔一次网线或点「现在校正」即可写入", target.name)
    }
}
