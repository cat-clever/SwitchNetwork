import SwiftUI

/// 路由表。读系统当前真正生效的 IPv4 路由，可以删单条、加临时路由、改已有路由。
///
/// 这里的操作直接改系统路由表，不进任何配置、也不落盘：路由是系统状态，
/// 重启之后系统本来就会按接口重新下发一遍。
struct RoutesView: View {
    @EnvironmentObject private var state: AppState
    let searchText: String

    @State private var editorTarget: RouteEditorTarget?
    /// 只在需要二次确认时才放东西进来，普通路由点了就删。
    @State private var pendingDelete: RouteEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            if let banner = state.routeBanner {
                RouteBannerBar(banner: banner)
            }

            if state.routeLoadFailed {
                loadFailureGroup
            } else if groups.isEmpty {
                emptyGroup
            } else {
                ForEach(groups) { group in
                    groupSection(group)
                }
            }

            if !state.deletedRoutes.isEmpty {
                DeletedRoutesSection()
            }

            footer

            if !state.privilegeGranted {
                PermissionHintGroup()
            }
        }
        .alert(item: $pendingDelete) { entry in
            Alert(title: Text(deleteTitle(for: entry)),
                  message: Text(deleteMessage(for: entry)),
                  primaryButton: .destructive(Text(L.t("仍要删除"))) {
                      state.deleteRoute(entry)
                  },
                  secondaryButton: .cancel(Text(L.t("取消"))))
        }
        .sheet(item: $editorTarget) { target in
            RouteEditorView(draft: target.route, replacing: target.replacing) { route in
                if let old = target.replacing {
                    state.updateRoute(route, replacing: old)
                } else {
                    state.addRoute(route)
                }
                editorTarget = nil
            } onCancel: {
                editorTarget = nil
            }
            .environmentObject(state)
        }
        .onAppear {
            state.loadRoutes()
        }
    }

    // MARK: - 分组

    private func groupSection(_ group: RouteGroup) -> some View {
        SectionGroup(title: group.title, subtitle: group.subtitle) {
            Card {
                ForEach(group.entries.indices, id: \.self) { index in
                    if index > 0 { CardRowDivider() }
                    row(for: group.entries[index])
                }
            }
        }
    }

    private func row(for entry: RouteEntry) -> some View {
        CardRow(icon: Symbols.resolve("arrow.triangle.branch", fallback: "arrow.triangle.merge"),
                iconTint: tint(for: entry),
                title: entry.networkLabel,
                subtitle: subtitle(for: entry),
                titleAccessory: accessory(for: entry)) {
            HStack(spacing: 2) {
                if canEdit(entry) {
                    IconButton(symbol: "pencil",
                               help: L.t("编辑"),
                               disabled: state.isRouteBusy) {
                        editorTarget = RouteEditorTarget(route: editableRoute(entry), replacing: entry)
                    }
                }
                IconButton(symbol: "trash",
                           help: L.t("移除这条路由"),
                           tint: Theme.dangerColor,
                           disabled: state.isRouteBusy) {
                    requestDelete(entry)
                }
            }
        }
    }

    // MARK: - 空态与失败态

    private var loadFailureGroup: some View {
        SectionGroup(title: L.t("路由表")) {
            Card {
                EmptyHint(text: L.t("读不到路由表，点下面的「刷新」重试"))
            }
        }
    }

    private var emptyGroup: some View {
        SectionGroup(title: L.t("路由表")) {
            Card {
                EmptyHint(text: emptyText)
            }
        }
    }

    private var emptyText: String {
        // 路由表不可能真是空的（至少还有 lo0 和接口直连），所以只剩「还在读」和「被搜索筛掉了」两种。
        if state.isLoadingRoutes { return L.t("正在读取路由表…") }
        return L.t("没有匹配的路由")
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: Symbols.resolve("info.circle", fallback: "questionmark.circle"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(L.t("只显示 IPv4 路由。这里加的路由是临时的，不会写进任何配置"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            SecondaryButton(title: L.t("刷新"),
                            symbol: "arrow.clockwise",
                            disabled: state.isRouteBusy) {
                state.loadRoutes()
            }
            PrimaryButton(title: state.isRouteBusy ? L.t("正在写入…") : L.t("新增路由"),
                          symbol: "plus",
                          disabled: state.isRouteBusy) {
                editorTarget = RouteEditorTarget(route: Route(), replacing: nil)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - 计算

    private var groups: [RouteGroup] {
        let all = filteredRoutes
        let ordered: [(RouteEntryOrigin, String, String)] = [
            (.defaultRoute, L.t("默认路由"), L.t("整机的出口。删掉之后，不匹配其他路由的流量会立刻中断")),
            (.staticRoute, L.t("静态路由"), L.t("下一跳是具体地址的路由：可能是手动加的，也可能是 VPN 下发的")),
            (.link, L.t("接口直连"), L.t("系统按接口地址自动生成的直连网段，一般不用管")),
            (.local, L.t("本机与组播"), L.t("回环、组播和广播，系统自带，删了通常马上重建"))
        ]
        return ordered.compactMap { origin, title, subtitle in
            let entries = entries(all, matching: origin)
            if entries.isEmpty { return nil }
            return RouteGroup(origin: origin, title: title, subtitle: subtitle, entries: entries)
        }
    }

    private func entries(_ all: [RouteEntry], matching origin: RouteEntryOrigin) -> [RouteEntry] {
        var seen = Set<String>()
        var result: [RouteEntry] = []
        for entry in all where entry.origin == origin {
            // id 撞了的话 ForEach 会错位，同一行只留一条。
            if seen.insert(entry.id).inserted {
                result.append(entry)
            }
        }
        // 按数值排，别按字符串排，否则 10.100 会排在 10.9 前面。
        return result.sorted { left, right in
            let leftValue = IPv4.addressToUInt32(left.destination) ?? 0
            let rightValue = IPv4.addressToUInt32(right.destination) ?? 0
            if leftValue != rightValue { return leftValue < rightValue }
            return (left.prefixLength ?? 0) < (right.prefixLength ?? 0)
        }
    }

    private var filteredRoutes: [RouteEntry] {
        if searchText.isEmpty { return state.systemRoutes }
        let keyword = searchText.lowercased()
        return state.systemRoutes.filter { entry in
            if entry.networkLabel.lowercased().contains(keyword) { return true }
            if entry.gateway.lowercased().contains(keyword) { return true }
            return entry.interface.lowercased().contains(keyword)
        }
    }

    private func tint(for entry: RouteEntry) -> Color {
        switch entry.origin {
        case .defaultRoute: return Theme.dangerColor
        case .staticRoute: return Theme.accent
        case .link, .local: return Color.secondary
        }
    }

    private func subtitle(for entry: RouteEntry) -> String {
        var parts = [L.t("下一跳 %@", entry.gateway), L.t("接口 %@", entry.interface)]
        if !entry.flags.isEmpty { parts.append(entry.flags) }
        return parts.joined(separator: " · ")
    }

    private func accessory(for entry: RouteEntry) -> AnyView? {
        if let name = state.profileName(owning: entry) {
            return AnyView(TagChip(text: L.t("来自配置「%@」", name)))
        }
        if entry.isTunnelInterface {
            return AnyView(TagChip(text: L.t("VPN"), tint: Theme.warningColor))
        }
        return nil
    }

    /// 哪些行可以「编辑」：只有下一跳是真实地址、又不是隧道下发的静态路由。
    /// 默认路由改网段等于删了再加；接口直连和本机/组播路由是系统自己生成的，改了没意义；
    /// VPN 的路由是隧道下发的，改完也会被写回来。
    private func canEdit(_ entry: RouteEntry) -> Bool {
        if entry.origin != .staticRoute { return false }
        if entry.isTunnelInterface { return false }
        guard let prefix = entry.prefixLength else { return false }
        return prefix > 0
    }

    private func editableRoute(_ entry: RouteEntry) -> Route {
        return Route(destination: entry.destination,
                     subnetMask: entry.mask,
                     gateway: entry.gateway)
    }

    // MARK: - 删除

    private func requestDelete(_ entry: RouteEntry) {
        if requiresConfirmation(entry) {
            pendingDelete = entry
        } else {
            state.deleteRoute(entry)
        }
    }

    /// 只有「下一跳是真实地址、又不走隧道」的路由可以随手删，反正删错了能撤回。
    /// 其余的先让用户看清后果。系统自带的那些删了通常没意义，甚至当场断网。
    private func requiresConfirmation(_ entry: RouteEntry) -> Bool {
        if entry.origin != .staticRoute { return true }
        return entry.isTunnelInterface
    }

    /// 判断顺序要和分组一致（先 default、再 local、最后 link）：
    /// 224.0.0.0/4 这种组播路由的网关也是 link#，先判 isInterfaceScope 会让它
    /// 明明列在「本机与组播」里、却弹出「删除接口直连路由」的文案。
    private func deleteTitle(for entry: RouteEntry) -> String {
        if entry.isDefault { return L.t("删除默认路由") }
        if entry.origin == .local { return L.t("删除系统路由") }
        if entry.isInterfaceScope { return L.t("删除接口直连路由") }
        return L.t("删除 VPN 路由")
    }

    private func deleteMessage(for entry: RouteEntry) -> String {
        if entry.isDefault {
            return L.t("default 是整机的默认出口，当前走 %@。删掉后所有不匹配其他路由的流量——上网、iCloud、App Store——会立刻中断。删除后可以在下面的「本次删除」里加回来。", entry.gateway)
        }
        if entry.origin == .local {
            return L.t("%@ 是系统自带的本机或组播路由，删掉通常没有意义，系统会自己重建。", entry.networkLabel)
        }
        if entry.isInterfaceScope {
            return L.t("%@ 是接口 %@ 的直连网段，由系统随接口地址自动生成。删掉后本机可能连该网段里的设备（包括网关）都访问不了；系统通常会在接口状态变化时重新生成它。", entry.networkLabel, entry.interface)
        }
        return L.t("%@ 走的是 %@ 隧道，多半由 VPN 下发。删掉后这个网段的流量会改走其他路由或直接失败。", entry.networkLabel, entry.interface)
    }
}

/// 一组路由。origin 借来当身份：一个分组只对应一个来源。
private struct RouteGroup: Identifiable {
    let origin: RouteEntryOrigin
    let title: String
    let subtitle: String
    let entries: [RouteEntry]

    var id: RouteEntryOrigin { return origin }
}

/// 顶部那条提示：刚删了什么、要不要撤回，或者刚才为什么失败。
private struct RouteBannerBar: View {
    @EnvironmentObject private var state: AppState

    let banner: AppState.RouteBanner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.isError
                    ? Symbols.resolve("exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
                    : Symbols.resolve("checkmark.circle.fill", fallback: "checkmark.circle"))
                .font(.system(size: 12))
                .foregroundColor(tint)

            Text(banner.text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if banner.undoID != nil {
                SecondaryButton(title: L.t("撤回"),
                                symbol: "arrow.uturn.backward",
                                disabled: state.isRouteBusy) {
                    state.undoDeletionFromBanner()
                }
            }
            IconButton(symbol: "xmark", help: L.t("关闭")) {
                state.dismissRouteBanner()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private var tint: Color {
        return banner.isError ? Theme.dangerColor : Theme.successColor
    }
}

/// 这次运行删掉的路由。关掉应用就没了——路由本身是系统状态，不值得落盘。
private struct DeletedRoutesSection: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let items = state.deletedRoutes
        SectionGroup(title: L.t("本次删除"),
                     subtitle: L.t("这次运行里删掉的路由，点「还原」加回去。关掉应用后这份记录就没了")) {
            Card {
                ForEach(items.indices, id: \.self) { index in
                    if index > 0 { CardRowDivider() }
                    row(for: items[index])
                }
            }
        }
    }

    private func row(for item: DeletedRoute) -> some View {
        var subtitle = restoreSubtitle(item)
        var accessory: AnyView?
        if let failure = item.restoreFailure {
            subtitle = L.t("还原失败：%@", failure)
            accessory = AnyView(TagChip(text: L.t("没能还原"), tint: Theme.dangerColor))
        }

        return CardRow(icon: Symbols.resolve("arrow.uturn.backward", fallback: "arrow.counterclockwise"),
                       iconTint: Color.secondary,
                       title: item.entry.networkLabel,
                       subtitle: subtitle,
                       titleAccessory: accessory,
                       showsHover: false) {
            SecondaryButton(title: L.t("还原"),
                            symbol: "arrow.uturn.backward",
                            disabled: state.isRouteBusy) {
                state.restoreRoute(id: item.id)
            }
        }
    }

    private func restoreSubtitle(_ item: DeletedRoute) -> String {
        var parts = [L.t("下一跳 %@", item.entry.gateway)]
        if !item.entry.interface.isEmpty {
            parts.append(L.t("接口 %@", item.entry.interface))
        }
        return parts.joined(separator: " · ")
    }
}
