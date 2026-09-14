import SwiftUI
import Combine

struct ProfileEditorTarget: Identifiable {
    let id: UUID
    let profile: Profile
    let isNew: Bool

    init(profile: Profile, isNew: Bool) {
        self.id = profile.id
        self.profile = profile
        self.isNew = isNew
    }
}

struct ProfileManagerView: View {
    @EnvironmentObject private var state: AppState
    let searchText: String

    @State private var editorTarget: ProfileEditorTarget?

    var body: some View {
        let groups = visibleGroups

        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            SectionGroup(title: L.t("网卡配置"),
                         subtitle: L.t("每个接口下可以保存多份配置，其中最多只有一份能标记为「自动应用」")) {
                VStack(spacing: 18) {
                    if groups.isEmpty {
                        Card {
                            EmptyHint(text: state.interfaces.isEmpty
                                      ? L.t("正在读取网络接口…")
                                      : L.t("还没有保存任何配置，点下面的按钮新建一份"))
                        }
                    } else {
                        ForEach(groups, id: \.status.identifier) { group in
                            InterfaceProfileGroup(status: group.status,
                                                  profiles: group.profiles,
                                                  onCreate: { openEditor(interface: group.status) },
                                                  onEdit: { profile in
                                                      editorTarget = ProfileEditorTarget(profile: profile, isNew: false)
                                                  })
                        }
                    }

                    HStack {
                        SecondaryButton(title: L.t("新建配置"), symbol: "plus") {
                            openEditor(interface: defaultInterface())
                        }
                        Spacer()
                    }
                }
            }

            TrashSection()
        }
        .sheet(item: $editorTarget) { target in
            ProfileEditorView(original: target.profile, isNew: target.isNew) { saved in
                state.save(saved, checkRoutesAfterSave: true)
                editorTarget = nil
            } onCancel: {
                editorTarget = nil
            }
            .environmentObject(state)
        }
    }

    private var visibleGroups: [(status: InterfaceStatus, profiles: [Profile])] {
        let groups = state.profilesGroupedByInterface()
        if searchText.isEmpty { return groups }
        let keyword = searchText.lowercased()
        return groups.compactMap { group in
            let matched = group.profiles.filter { profile in
                profile.name.lowercased().contains(keyword)
            }
            if !matched.isEmpty { return (group.status, matched) }
            if group.status.identifier.lowercased().contains(keyword) { return group }
            if group.status.displayName.lowercased().contains(keyword) { return group }
            return nil
        }
    }

    private func defaultInterface() -> InterfaceStatus? {
        for status in state.interfaces where status.isConfigurable {
            return status
        }
        return nil
    }

    private func openEditor(interface: InterfaceStatus?) {
        var draft = Profile()
        if let status = interface {
            draft.interfaceIdentifier = status.identifier
            draft.interfaceDisplayName = status.displayName
        }
        editorTarget = ProfileEditorTarget(profile: draft, isNew: true)
    }
}

private struct InterfaceProfileGroup: View {
    @EnvironmentObject private var state: AppState

    let status: InterfaceStatus
    let profiles: [Profile]
    let onCreate: () -> Void
    let onEdit: (Profile) -> Void

    var body: some View {
        SectionGroup(title: status.displayName, subtitle: subtitle) {
            VStack(spacing: 10) {
                ForEach(profiles) { profile in
                    ProfileCard(profile: profile, status: status, onEdit: { onEdit(profile) })
                }
                HStack {
                    SecondaryButton(title: L.t("新建配置"), symbol: "plus", action: onCreate)
                    Spacer()
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let secondary = status.secondaryIdentifier {
            parts.append(secondary)
        }
        if let service = status.serviceName {
            parts.append(L.t("网络服务 %@", service))
        } else {
            parts.append(L.t("无可写入的网络服务"))
        }
        let auto = state.autoProfile(for: status.identifier)
        if let auto = auto {
            parts.append(L.t("自动配置：%@", auto.name))
        } else {
            parts.append(L.t("未指定自动配置"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProfileCard: View {
    @EnvironmentObject private var state: AppState

    let profile: Profile
    let status: InterfaceStatus
    let onEdit: () -> Void

    @State private var pendingDelete: Profile?
    @State private var routeChecks: [RouteCheckResult]?
    @State private var isCheckingRoutes = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                mainRow
                if !profile.validationErrors.isEmpty {
                    CardRowDivider()
                    validationRow
                }
                if !profile.routes.isEmpty || routeChecks != nil {
                    CardRowDivider()
                    routeSection
                }
            }
        }
        .alert(item: $pendingDelete) { target in
            Alert(title: Text(L.t("删除配置")),
                  message: Text(L.t("确定要把「%@」移入回收站吗？%d 天后会自动彻底删除。",
                                    target.name, state.settings.trashRetentionDays)),
                  primaryButton: .destructive(Text(L.t("移入回收站"))) {
                      state.delete(profileID: target.id)
                  },
                  secondaryButton: .cancel(Text(L.t("取消"))))
        }
        .onAppear {
            if !profile.routes.isEmpty && routeChecks == nil && !isCheckingRoutes {
                checkRoutes()
            }
        }
        .onReceive(state.profileSaved) { identifier in
            // 刚编辑完这份配置，重新查一遍路由表，让用户立刻看到是否已生效。
            if identifier == profile.id {
                checkRoutes()
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.iconCornerRadius, style: .continuous)
                .fill(iconTint.opacity(0.15))
                .frame(width: Theme.iconSize, height: Theme.iconSize)
                .overlay(
                    Image(systemName: Symbols.resolve("doc.text", fallback: "doc"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(iconTint)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 13, weight: .semibold))
                    if profile.autoApplyOnConnect {
                        TagChip(text: L.t("自动应用"))
                    }
                    if profile.promoteServiceToTop {
                        TagChip(text: L.t("置顶"))
                    }
                    if isInEffect {
                        TagChip(text: L.t("生效中"), tint: Theme.successColor)
                    }
                    if !profile.validationErrors.isEmpty {
                        TagChip(text: L.t("配置有误"), tint: Theme.dangerColor)
                    }
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            SwitchToggle(isOn: autoApplyBinding)
                .help(L.t("接口连上时自动应用这套配置。同一接口下只能有一份开启。"))
            IconButton(symbol: "play.fill", help: L.t("立即应用这套配置"), tint: Theme.successColor) {
                state.apply(profileID: profile.id, requireConnected: false)
            }
            IconButton(symbol: "arrow.triangle.2.circlepath", help: L.t("检查静态路由是否已生效"), tint: Theme.accent) {
                checkRoutes()
            }
            IconButton(symbol: "pencil", help: L.t("编辑")) {
                onEdit()
            }
            IconButton(symbol: "doc.on.doc", help: L.t("克隆一份")) {
                state.clone(profileID: profile.id)
            }
            IconButton(symbol: "trash", help: L.t("移入回收站"), tint: Theme.dangerColor) {
                pendingDelete = profile
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var validationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(profile.validationErrors, id: \.self) { error in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: Symbols.resolve("exclamationmark.triangle.fill",
                                                      fallback: "exclamationmark.triangle"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.dangerColor)
                        .padding(.top, 1)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.dangerColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(L.t("静态路由"))
                    .font(.system(size: 11, weight: .semibold))
                if isCheckingRoutes {
                    Text(L.t("正在检查…"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 5)

            if profile.routes.isEmpty {
                Text(L.t("没有配置静态路由"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 9)
            } else {
                ForEach(routeRows) { row in
                    RouteCheckRow(result: row)
                }
                .padding(.bottom, 5)
            }
        }
    }

    private var routeRows: [RouteCheckResult] {
        if let checks = routeChecks { return checks }
        // 检查要真的去查系统路由表（每条一次 route -n get），只能在后台跑，
        // 所以没检查过的时候只展示配置内容，不显示结论。
        return profile.routes.map { RouteCheckResult(route: $0, status: RouteCheckStatus.notChecked) }
    }

    // MARK: - 计算

    private var iconTint: Color {
        if !profile.validationErrors.isEmpty { return Theme.dangerColor }
        if profile.autoApplyOnConnect { return Theme.accent }
        return Color.secondary
    }

    private var isInEffect: Bool {
        guard let current = state.currentProfile(for: status) else { return false }
        return current.id == profile.id
    }

    private var summary: String {
        var parts = [profile.ipSummary]
        if let gateway = profile.gatewaySummary { parts.append(gateway) }
        parts.append(profile.dnsSummary)
        parts.append(profile.routes.isEmpty ? L.t("无静态路由") : L.t("%d 条静态路由", profile.routes.count))
        return parts.joined(separator: " · ")
    }

    private var autoApplyBinding: Binding<Bool> {
        return Binding(get: {
            profile.autoApplyOnConnect
        }, set: { newValue in
            state.setAutoApply(profileID: profile.id, enabled: newValue)
        })
    }

    private func checkRoutes() {
        if profile.routes.isEmpty {
            // 路由被删光了，收起结论区，别留一份过期结果。
            routeChecks = nil
            return
        }
        guard !isCheckingRoutes else { return }
        isCheckingRoutes = true
        let target = profile
        DispatchQueue.global(qos: .userInitiated).async {
            let results = RouteManager.check(target)
            DispatchQueue.main.async {
                isCheckingRoutes = false
                routeChecks = results
            }
        }
    }
}
