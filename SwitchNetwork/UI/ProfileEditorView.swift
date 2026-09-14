import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject private var state: AppState

    let isNew: Bool
    let onSave: (Profile) -> Void
    let onCancel: () -> Void

    @State private var draft: Profile

    init(original: Profile,
         isNew: Bool,
         onSave: @escaping (Profile) -> Void,
         onCancel: @escaping () -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: original)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.groupSpacing) {
                    basicSection
                    ipSection
                    dnsSection
                    routeSection
                    automationSection
                    prioritySection
                }
                .padding(Theme.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 680)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: Symbols.resolve("doc.badge.gearshape", fallback: "doc.text"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.accent)
            Text(isNew ? L.t("新建配置") : L.t("编辑配置"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - 基本信息

    private var basicSection: some View {
        SectionGroup(title: L.t("基本信息"), subtitle: L.t("配置会写入所绑定的这个网络接口")) {
            Card {
                CardRow(icon: Symbols.resolve("tag", fallback: "textformat"),
                        title: L.t("名称"),
                        subtitle: L.t("给这套配置起个好认的名字"),
                        showsHover: false) {
                    TextField(L.t("例如：公司内网"), text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 220)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("network", fallback: "cable.connector"),
                        title: L.t("绑定接口"),
                        subtitle: L.t("配置文件里用 BSD 设备名匹配，如 en0"),
                        showsHover: false) {
                    Picker("", selection: $draft.interfaceIdentifier) {
                        if draft.interfaceIdentifier.isEmpty {
                            Text(L.t("请选择")).tag("")
                        }
                        if isCurrentInterfaceMissing {
                            Text(L.t("%@（当前不在系统中）", draft.interfaceIdentifier))
                                .tag(draft.interfaceIdentifier)
                        }
                        ForEach(state.interfaces) { status in
                            Text("\(status.identifier) · \(status.displayName)")
                                .tag(status.identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                    .onChange(of: draft.interfaceIdentifier) { newValue in
                        syncInterfaceDisplayName(newValue)
                    }
                }
            }
        }
    }

    // MARK: - IP 配置

    private var ipSection: some View {
        SectionGroup(title: L.t("IP 配置"), subtitle: L.t("选择地址是手工填写还是由 DHCP 服务器下发")) {
            Card {
                CardRow(icon: Symbols.resolve("arrow.triangle.branch", fallback: "arrow.right"),
                        title: L.t("IP 获取方式"),
                        subtitle: draft.ipMode.detail,
                        showsHover: false) {
                    Picker("", selection: $draft.ipMode) {
                        ForEach(IPMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 170)
                }
                CardRowDivider()
                if draft.ipMode == .manual {
                    textFieldRow(icon: Symbols.resolve("number", fallback: "textformat"),
                                 title: L.t("IP 地址"),
                                 placeholder: "192.168.1.100",
                                 text: $draft.ipAddress,
                                 error: { value in
                                     if value.isEmpty { return L.t("必填") }
                                     return IPv4.isValidAddress(value) ? nil : L.t("格式不正确")
                                 })
                    CardRowDivider()
                    textFieldRow(icon: Symbols.resolve("rectangle.split.3x1", fallback: "square.grid.3x1"),
                                 title: L.t("子网掩码"),
                                 placeholder: "255.255.255.0",
                                 text: $draft.subnetMask,
                                 error: { value in
                                     IPv4.isValidMask(value) ? nil : L.t("必须是连续的网络位，如 255.255.255.0")
                                 })
                    CardRowDivider()
                    textFieldRow(icon: Symbols.resolve("arrow.turn.down.right", fallback: "arrow.right"),
                                 title: L.t("网关"),
                                 placeholder: "192.168.1.1",
                                 text: $draft.gateway,
                                 error: { value in
                                     IPv4.isValidGateway(value) ? nil : L.t("格式不正确")
                                 })
                } else {
                    CardRow(icon: Symbols.resolve("wand.and.stars", fallback: "sparkles"),
                            title: L.t("由 DHCP 服务器分配"),
                            subtitle: L.t("应用时执行 networksetup -setdhcp：IP、掩码、网关全部由服务器决定，本机填的值不参与。上面填过的值会保留，切回「手动」时还能用"),
                            showsHover: false)
                }
            }
        }
    }

    // MARK: - DNS

    private var dnsSection: some View {
        SectionGroup(title: "DNS",
                     subtitle: L.t("DNS 和 IP 的来源相互独立：用 DHCP 拿地址，同样可以指定固定 DNS")) {
            Card {
                CardRow(icon: Symbols.resolve("arrow.triangle.branch", fallback: "arrow.right"),
                        title: L.t("DNS 获取方式"),
                        subtitle: draft.dnsMode.detail,
                        showsHover: false) {
                    Picker("", selection: $draft.dnsMode) {
                        ForEach(DNSMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 200)
                }
                CardRowDivider()

                if draft.dnsMode == .automatic {
                    CardRow(icon: Symbols.resolve("globe", fallback: "network"),
                            title: L.t("交给系统获取"),
                            subtitle: L.t("应用时会清空手动 DNS 列表（networksetup -setdnsservers <服务> Empty）。已填写的地址会保留，切回「手动指定」时还能用"),
                            showsHover: false)
                    if draft.ipMode == .manual {
                        CardRowDivider()
                        noticeRow(symbol: Symbols.resolve("exclamationmark.triangle.fill",
                                                          fallback: "exclamationmark.triangle"),
                                  tint: Theme.warningColor,
                                  text: L.t("IP 是手动填写的，DHCP 服务器不会下发 DNS。这个组合下系统没有任何 DNS 服务器，域名解析会失败，建议改成「手动指定」。"))
                    }
                } else if draft.dnsServers.isEmpty {
                    CardRow(icon: Symbols.resolve("globe", fallback: "network"),
                            title: L.t("还没有 DNS 地址"),
                            subtitle: L.t("手动指定至少要填一个，否则应用时会失败"),
                            showsHover: false)
                    CardRowDivider()
                    dnsAddRow
                } else {
                    ForEach(Array(draft.dnsServers.indices), id: \.self) { index in
                        if index > 0 { CardRowDivider() }
                        dnsRow(index: index)
                    }
                    CardRowDivider()
                    dnsAddRow
                }
            }
        }
    }

    private var dnsAddRow: some View {
        return footerButton(title: L.t("添加 DNS"), symbol: "plus") {
            draft.dnsServers.append("")
        }
    }

    private func dnsRow(index: Int) -> some View {
        return CardRow(icon: Symbols.resolve("globe", fallback: "network"),
                       title: "DNS \(index + 1)",
                       showsHover: false) {
            HStack(spacing: 8) {
                TextField("8.8.8.8", text: dnsBinding(index))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 180)
                if !isValidDNS(index) {
                    Text(L.t("格式不正确"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.dangerColor)
                }
                IconButton(symbol: Symbols.resolve("minus.circle", fallback: "minus"),
                           help: L.t("移除这条 DNS"),
                           tint: Theme.dangerColor) {
                    removeDNS(at: index)
                }
            }
        }
    }

    // MARK: - 静态路由

    private var routeSection: some View {
        SectionGroup(title: L.t("静态路由"),
                     subtitle: L.t("应用时会先查路由表：不存在就添加，下一跳不一致就先删除再加")) {
            Card {
                ForEach(Array(draft.routes.indices), id: \.self) { index in
                    if index > 0 { CardRowDivider() }
                    routeEditor(index: index)
                }
                if draft.routes.isEmpty {
                    CardRow(icon: Symbols.resolve("arrow.triangle.branch", fallback: "arrow.triangle.merge"),
                            title: L.t("没有静态路由"),
                            subtitle: L.t("如果只是切换 IP 和网关，这里可以留空"),
                            showsHover: false)
                }
                CardRowDivider()
                footerButton(title: L.t("添加路由"), symbol: "plus") {
                    draft.routes.append(Route())
                }
            }
        }
    }

    private func routeEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                fieldLabel(L.t("目的网段"))
                TextField("10.0.0.0", text: routeBinding(index, \.destination))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 132)
                fieldLabel(L.t("掩码"))
                TextField("255.255.255.0", text: routeBinding(index, \.subnetMask))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 132)
                Spacer(minLength: 0)
                IconButton(symbol: Symbols.resolve("minus.circle", fallback: "minus"),
                           help: L.t("移除这条路由"),
                           tint: Theme.dangerColor) {
                    removeRoute(at: index)
                }
            }
            HStack(spacing: 8) {
                fieldLabel(L.t("下一跳"))
                TextField("192.168.1.1", text: routeBinding(index, \.gateway))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 132)
                fieldLabel("metric")
                TextField(L.t("可选"), text: metricBinding(index))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 60)
                if let message = routeError(index: index) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.dangerColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 自动化

    private var automationSection: some View {
        SectionGroup(title: L.t("自动化")) {
            Card {
                CardRow(icon: Symbols.resolve("bolt.badge.clock", fallback: "bolt"),
                        iconTint: Theme.accent,
                        title: L.t("设为该接口的自动应用配置"),
                        subtitle: automationSubtitle,
                        titleAccessory: draft.autoApplyOnConnect ? AnyView(TagChip(text: L.t("自动"))) : nil,
                        showsHover: false) {
                    SwitchToggle(isOn: $draft.autoApplyOnConnect)
                }
            }
        }
    }

    // MARK: - 网络优先级

    private var prioritySection: some View {
        SectionGroup(title: L.t("网络优先级"),
                     subtitle: L.t("系统按「网络服务优先级」决定用哪条链路收发数据。这份配置置顶后，插上网线就走它，不必先关掉 Wi-Fi")) {
            Card {
                CardRow(icon: Symbols.resolve("arrow.up.to.line", fallback: "arrow.up"),
                        iconTint: draft.promoteServiceToTop ? Theme.accent : Color.secondary,
                        title: L.t("应用时把该接口提到最前面"),
                        subtitle: prioritySubtitle,
                        titleAccessory: draft.promoteServiceToTop ? AnyView(TagChip(text: L.t("置顶"))) : nil,
                        showsHover: false) {
                    SwitchToggle(isOn: $draft.promoteServiceToTop)
                }
            }
        }
    }

    private var prioritySubtitle: String {
        if !draft.promoteServiceToTop {
            return L.t("关闭时不动系统的服务顺序，只写 IP、DNS 和路由")
        }
        let target = draft.interfaceDisplayName.isEmpty ? draft.interfaceIdentifier : draft.interfaceDisplayName
        if target.isEmpty {
            return L.t("还没绑定接口，绑定之后才知道要把哪一项排到最前面")
        }
        return L.t("应用时把「%@」排到服务顺序第一位，其他服务的相对顺序不变", target)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if !draft.validationErrors.isEmpty {
                Image(systemName: Symbols.resolve("exclamationmark.triangle.fill",
                                                  fallback: "exclamationmark.triangle"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.warningColor)
                Text(L.t("还有 %d 项需要修正，否则应用时会失败", draft.validationErrors.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            SecondaryButton(title: L.t("取消"), action: onCancel)
            PrimaryButton(title: isNew ? L.t("创建") : L.t("保存"),
                          symbol: "checkmark",
                          disabled: !canSave) {
                onSave(draft)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 计算

    private var canSave: Bool {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return !draft.interfaceIdentifier.isEmpty
    }

    private var isCurrentInterfaceMissing: Bool {
        if draft.interfaceIdentifier.isEmpty { return false }
        for status in state.interfaces where status.identifier == draft.interfaceIdentifier {
            return false
        }
        return true
    }

    private var conflictingAutoProfile: Profile? {
        for profile in state.profiles
        where profile.interfaceIdentifier == draft.interfaceIdentifier
            && profile.id != draft.id
            && profile.autoApplyOnConnect {
            return profile
        }
        return nil
    }

    private var automationSubtitle: String {
        if !draft.autoApplyOnConnect {
            return L.t("开启后，接口从「未连接」变为「已连接」时会自动写入这套配置")
        }
        if let conflict = conflictingAutoProfile {
            return L.t("保存后会同时关闭同一接口下「%@」的自动应用（每个接口只能有一份）", conflict.name)
        }
        return L.t("已开启：接口连上时自动应用这套配置")
    }

    // MARK: - 绑定与操作

    private func textFieldRow(icon: String,
                              title: String,
                              placeholder: String,
                              text: Binding<String>,
                              error: @escaping (String) -> String?) -> some View {
        return CardRow(icon: icon, title: title, showsHover: false) {
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 180)
                if let message = error(text.wrappedValue) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.dangerColor)
                }
            }
        }
    }

    private func footerButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        return HStack {
            SecondaryButton(title: title, symbol: symbol, action: action)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func fieldLabel(_ text: String) -> some View {
        return Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 48, alignment: .leading)
    }

    private func noticeRow(symbol: String, tint: Color, text: String) -> some View {
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundColor(tint)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func dnsBinding(_ index: Int) -> Binding<String> {
        return Binding(get: {
            if index < draft.dnsServers.count { return draft.dnsServers[index] }
            return ""
        }, set: { newValue in
            if index < draft.dnsServers.count { draft.dnsServers[index] = newValue }
        })
    }

    private func isValidDNS(_ index: Int) -> Bool {
        if index >= draft.dnsServers.count { return true }
        let value = draft.dnsServers[index]
        if value.isEmpty { return true }
        return IPv4.isValidAddress(value)
    }

    private func removeDNS(at index: Int) {
        if index < draft.dnsServers.count {
            draft.dnsServers.remove(at: index)
        }
    }

    private func routeBinding(_ index: Int, _ keyPath: WritableKeyPath<Route, String>) -> Binding<String> {
        return Binding(get: {
            if index < draft.routes.count { return draft.routes[index][keyPath: keyPath] }
            return ""
        }, set: { newValue in
            if index < draft.routes.count {
                draft.routes[index][keyPath: keyPath] = newValue
            }
        })
    }

    private func metricBinding(_ index: Int) -> Binding<String> {
        return Binding(get: {
            if index < draft.routes.count, let metric = draft.routes[index].metric {
                return String(metric)
            }
            return ""
        }, set: { newValue in
            guard index < draft.routes.count else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                draft.routes[index].metric = nil
            } else if let value = Int(trimmed) {
                draft.routes[index].metric = value
            }
        })
    }

    private func routeError(index: Int) -> String? {
        if index >= draft.routes.count { return nil }
        return draft.routes[index].validationError
    }

    private func removeRoute(at index: Int) {
        if index < draft.routes.count {
            draft.routes.remove(at: index)
        }
    }

    private func syncInterfaceDisplayName(_ identifier: String) {
        for status in state.interfaces where status.identifier == identifier {
            draft.interfaceDisplayName = status.displayName
            return
        }
    }
}
