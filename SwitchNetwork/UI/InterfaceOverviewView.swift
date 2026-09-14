import SwiftUI

struct InterfaceOverviewView: View {
    @EnvironmentObject private var state: AppState
    let searchText: String

    var body: some View {
        SectionGroup(title: L.t("网络接口"),
                     subtitle: L.t("绿色圆点表示链路已建立：网线已插入并完成协商，或 Wi-Fi 已关联到网络")) {
            if visibleInterfaces.isEmpty {
                Card {
                    EmptyHint(text: state.interfaces.isEmpty ? L.t("正在读取网络接口…") : L.t("没有匹配的接口"))
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(visibleInterfaces) { status in
                        InterfaceCard(status: status)
                    }
                }
            }
        }

        ServiceOrderSection()

        if !state.privilegeGranted {
            PermissionHintGroup()
        }
    }

    private var visibleInterfaces: [InterfaceStatus] {
        if searchText.isEmpty { return state.interfaces }
        let keyword = searchText.lowercased()
        return state.interfaces.filter { status in
            if status.identifier.lowercased().contains(keyword) { return true }
            if status.displayName.lowercased().contains(keyword) { return true }
            if let service = status.serviceName, service.lowercased().contains(keyword) { return true }
            return false
        }
    }
}

struct InterfaceCard: View {
    @EnvironmentObject private var state: AppState
    let status: InterfaceStatus

    @State private var isConfirmingRestore = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                header
                CardRowDivider()
                details
                if status.isConfigurable {
                    CardRowDivider()
                    quickSwitchRow
                } else {
                    CardRowDivider()
                    CardRow(icon: Symbols.resolve("exclamationmark.triangle", fallback: "questionmark.circle"),
                            iconTint: Theme.warningColor,
                            title: L.t("无法写入配置"),
                            subtitle: L.t("接口 %@ 在系统里没有对应的网络服务，请先到「系统设置 → 网络」里添加", status.identifier))
                }
                if let report = state.report(for: status.identifier) {
                    CardRowDivider()
                    ApplyReportRow(report: report)
                }
            }
        }
        .alert(isPresented: $isConfirmingRestore) {
            Alert(title: Text(L.t("不使用配置")),
                  message: Text(L.t("会把 %@ 交还系统：IP 切回 DHCP、DNS 改自动获取，并删掉本应用写进去的静态路由。该接口的自动应用也会一起关掉。", status.identifier)),
                  primaryButton: .destructive(Text(L.t("交还系统"))) {
                      state.restoreToSystem(identifier: status.identifier)
                  },
                  secondaryButton: .cancel(Text(L.t("取消"))))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.iconCornerRadius, style: .continuous)
                .fill(iconTint.opacity(0.15))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: status.type.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(iconTint)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(status.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    if let secondary = status.secondaryIdentifier {
                        Text(secondary)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        StatusDot(isOn: status.isConnected)
                        Text(status.connectionLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(status.isConnected ? Theme.successColor : Color.secondary)
                    }
                }
                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var details: some View {
        HStack(alignment: .top, spacing: 20) {
            DetailItem(label: L.t("当前 IP"), value: status.currentIPLabel)
            DetailItem(label: L.t("网关"), value: gatewayText)
            DetailItem(label: "DNS", value: dnsText)
            DetailItem(label: L.t("配置方式"), value: status.configurationMode.label)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var quickSwitchRow: some View {
        CardRow(icon: Symbols.resolve("slider.horizontal.3", fallback: "gearshape"),
                iconTint: Theme.accent,
                title: currentProfileTitle,
                subtitle: currentProfileSubtitle,
                titleAccessory: isAutoInEffect ? AnyView(TagChip(text: L.t("自动"))) : nil) {
            Menu {
                let owned = state.profiles(for: status.identifier)
                if owned.isEmpty {
                    Text(L.t("还没有为该接口保存的配置"))
                } else {
                    ForEach(owned) { profile in
                        Button(action: {
                            state.apply(profileID: profile.id, requireConnected: false)
                        }) {
                            if isCurrent(profile) {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                    Divider()
                    Button(action: { isConfirmingRestore = true }) {
                        if currentProfile == nil {
                            Label(L.t("不使用配置（交还系统）"), systemImage: "checkmark")
                        } else {
                            Text(L.t("不使用配置（交还系统）"))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(L.t("切换配置"))
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: Symbols.resolve("chevron.up.chevron.down", fallback: "chevron.down"))
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.accent.opacity(0.14))
                )
                .foregroundColor(Theme.accent)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .fixedSize()
        }
    }

    // MARK: - 计算

    private var iconTint: Color {
        if !status.isConfigurable { return Color.secondary }
        return status.isConnected ? Theme.successColor : Color.secondary
    }

    private var subtitleLine: String {
        var parts: [String] = [L.t("类型 %@", status.type.label)]
        if let service = status.serviceName {
            parts.append(L.t("网络服务 %@", service))
        }
        return parts.joined(separator: " · ")
    }

    private var gatewayText: String {
        if let gateway = status.currentGateway, !gateway.isEmpty { return gateway }
        return L.t("未设置")
    }

    private var dnsText: String {
        if status.currentDNS.isEmpty { return L.t("未设置") }
        return status.currentDNS.joined(separator: ", ")
    }

    private var currentProfile: Profile? {
        return state.currentProfile(for: status)
    }

    private var currentProfileTitle: String {
        if let profile = currentProfile { return profile.name }
        if !status.isConnected { return L.t("接口未连接") }
        return L.t("未匹配到已保存的配置")
    }

    private var currentProfileSubtitle: String? {
        if let profile = currentProfile {
            var parts = [profile.ipSummary]
            if let gateway = profile.gatewaySummary { parts.append(gateway) }
            parts.append(profile.dnsSummary)
            return parts.joined(separator: " · ")
        }
        if status.isConnected {
            return L.t("当前 %@，可在下面新增一份配置来固化这套参数", status.currentIPLabel)
        }
        return nil
    }

    private var isAutoInEffect: Bool {
        guard let current = currentProfile else { return false }
        guard let auto = state.autoProfile(for: status.identifier) else { return false }
        return auto.id == current.id
    }

    private func isCurrent(_ profile: Profile) -> Bool {
        guard let current = currentProfile else { return false }
        return current.id == profile.id
    }
}

/// 网络服务优先级（macOS 的「服务顺序」）。
/// 系统据此决定用哪条链路收发数据：排在前面的优先，这也决定了没写静态路由时走哪个网关。
struct ServiceOrderSection: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        SectionGroup(title: L.t("网络服务优先级"),
                     subtitle: L.t("系统按这个顺序决定用哪条链路收发数据，排在上面的优先。改完点「应用顺序」写入；插拔网卡带出新服务后要再应用一次")) {
            Card {
                if state.serviceOrder.isEmpty {
                    EmptyHint(text: L.t("正在读取网络服务…"))
                } else {
                    let entries = state.desiredServiceOrder
                    ForEach(entries) { entry in
                        if position(of: entry, in: entries) > 1 {
                            CardRowDivider()
                        }
                        row(entry: entry, entries: entries)
                    }
                    CardRowDivider()
                    footer
                }
            }
        }
    }

    /// 第几位，从 1 开始。顺序列表里服务名不重复，可以直接按值找。
    private func position(of entry: ServiceOrderEntry, in entries: [ServiceOrderEntry]) -> Int {
        return (entries.firstIndex(of: entry) ?? 0) + 1
    }

    private func row(entry: ServiceOrderEntry, entries: [ServiceOrderEntry]) -> some View {
        var parts = [L.t("第 %d 位", position(of: entry, in: entries))]
        parts.append(entry.device.isEmpty ? L.t("无对应设备") : entry.device)
        if !entry.isEnabled { parts.append(L.t("已停用")) }

        return CardRow(icon: Symbols.resolve("arrow.up.arrow.down.circle", fallback: "arrow.up.arrow.down"),
                       iconTint: entry.isEnabled ? Theme.accent : Color.secondary,
                       title: entry.name,
                       subtitle: parts.joined(separator: " · "),
                       showsHover: false) {
            HStack(spacing: 2) {
                IconButton(symbol: "chevron.up",
                           help: L.t("上移"),
                           disabled: position(of: entry, in: entries) == 1) {
                    state.moveServiceOrder(name: entry.name, offset: -1)
                }
                IconButton(symbol: "chevron.down",
                           help: L.t("下移"),
                           disabled: position(of: entry, in: entries) == entries.count) {
                    state.moveServiceOrder(name: entry.name, offset: 1)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: state.isServiceOrderOutOfSync
                    ? Symbols.resolve("exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
                    : Symbols.resolve("checkmark.circle.fill", fallback: "checkmark.circle"))
                .font(.system(size: 12))
                .foregroundColor(state.isServiceOrderOutOfSync ? Theme.warningColor : Theme.successColor)
            Text(state.isServiceOrderOutOfSync
                    ? L.t("与系统当前顺序不一致，点「应用顺序」写入")
                    : L.t("与系统当前顺序一致"))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            if !state.settings.serviceOrder.isEmpty {
                SecondaryButton(title: L.t("放弃自定义顺序"), symbol: "arrow.uturn.backward") {
                    state.resetServiceOrder()
                }
            }
            PrimaryButton(title: state.isApplying ? L.t("正在写入…") : L.t("应用顺序"),
                          symbol: "square.and.arrow.down",
                          disabled: state.isApplying) {
                state.applyServiceOrder()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// 权限没装好时，在概览页顶部给一条醒目的提示。
struct PermissionHintGroup: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        SectionGroup(title: L.t("需要授权"),
                     subtitle: L.t("修改 IP 和路由需要 root 权限，装一次免密授权之后就不会再弹密码框")) {
            Card {
                CardRow(icon: Symbols.resolve("lock.shield", fallback: "lock"),
                        iconTint: Theme.warningColor,
                        title: L.t("尚未安装 sudo 免密授权"),
                        subtitle: L.t("没有它的话，自动应用会因为权限不足而失败。装一次即可，之后开关机都不再需要密码。"),
                        titleAccessory: AnyView(TagChip(text: L.t("未完成"), tint: Theme.warningColor))) {
                    HStack(spacing: 8) {
                        SecondaryButton(title: L.t("重新检测"), symbol: "arrow.clockwise") {
                            state.refreshPrivilegeStatus()
                        }
                        PrimaryButton(title: state.isInstallingPrivilege ? L.t("等待授权…") : L.t("一键安装授权"),
                                      symbol: "lock.open",
                                      disabled: state.isInstallingPrivilege) {
                            state.installPrivilegeAuthorization()
                        }
                    }
                }
            }
        }
    }
}
