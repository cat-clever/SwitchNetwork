import SwiftUI

/// 要编辑的那一行。`replacing` 非 nil 表示修改，nil 表示新增。
struct RouteEditorTarget: Identifiable {
    let id: UUID
    let route: Route
    let replacing: RouteEntry?

    init(route: Route, replacing: RouteEntry?) {
        self.id = route.id
        self.route = route
        self.replacing = replacing
    }

    var isNew: Bool { return replacing == nil }
}

/// 新增 / 修改一条系统路由。
///
/// 用 `Route` 装数据只是为了少写一个结构，校验也直接复用 `Route.validationError`。
/// 它不允许前缀 0，也就是默认路由在这里既加不了也改不了——这是有意的：
/// 默认网关归「系统设置 → 网络」或「配置管理」管，在一个临时路由表单里改它太危险。
struct RouteEditorView: View {
    @EnvironmentObject private var state: AppState

    let draft: Route
    let replacing: RouteEntry?
    let onSave: (Route) -> Void
    let onCancel: () -> Void

    @State private var destination: String
    @State private var mask: String
    @State private var gateway: String
    @State private var metric: String

    init(draft: Route,
         replacing: RouteEntry?,
         onSave: @escaping (Route) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.replacing = replacing
        self.onSave = onSave
        self.onCancel = onCancel
        _destination = State(initialValue: draft.destination)
        _mask = State(initialValue: draft.subnetMask)
        _gateway = State(initialValue: draft.gateway)
        if let value = draft.metric {
            _metric = State(initialValue: String(value))
        } else {
            _metric = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.groupSpacing) {
                    formSection
                }
                .padding(Theme.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if let message = shownError {
                errorBar(message)
            }
            footer
        }
        .frame(width: 580, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: Symbols.resolve("arrow.triangle.branch", fallback: "arrow.triangle.merge"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.accent)
            Text(isNew ? L.t("新增路由") : L.t("修改路由"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - 表单

    private var formSection: some View {
        SectionGroup(title: L.t("路由"), subtitle: subtitle) {
            Card {
                CardRow(icon: Symbols.resolve("point.topleft.down.curvedto.point.bottomright.up",
                                               fallback: "arrow.triangle.branch"),
                        title: L.t("目的网段"),
                        subtitle: L.t("要写进路由表的目标地址，如 10.100.0.0"),
                        showsHover: false) {
                    TextField("10.0.0.0", text: $destination)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 150)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("square.grid.3x3", fallback: "square.grid.2x2"),
                        title: L.t("子网掩码"),
                        subtitle: L.t("可以填 255.255.255.0，也可以只填前缀长度 24"),
                        showsHover: false) {
                    HStack(spacing: 8) {
                        TextField("255.255.255.0", text: $mask)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 150)
                        Text(maskHint)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("arrow.turn.down.right", fallback: "arrow.right"),
                        title: L.t("下一跳"),
                        subtitle: L.t("这个网段的流量交给谁，通常是本机所在网段的网关"),
                        showsHover: false) {
                    TextField("192.168.1.1", text: $gateway)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 150)
                }
                CardRowDivider()
                CardRow(icon: Symbols.resolve("dial.medium", fallback: "gauge"),
                        title: L.t("metric"),
                        subtitle: L.t("留空表示不设置。路由表里看不到当前跃点数，这里填的是这次要写进去的值"),
                        showsHover: false) {
                    TextField(L.t("可选"), text: $metric)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 70)
                }
                CardRowDivider()
                noticeRow
            }
        }
    }

    private var noticeRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: Symbols.resolve("info.circle", fallback: "questionmark.circle"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 1)
            Text(L.t("前缀长度只能是 1–32。默认路由（前缀 0）不能在这里增删改，要换默认网关请到「系统设置 → 网络」或「配置管理」里改。"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 底栏

    private func errorBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: Symbols.resolve("exclamationmark.triangle.fill",
                                              fallback: "exclamationmark.triangle"))
                .font(.system(size: 11))
                .foregroundColor(Theme.dangerColor)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Theme.dangerColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Theme.dangerColor.opacity(0.08))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            SecondaryButton(title: L.t("取消"), action: onCancel)
            PrimaryButton(title: isNew ? L.t("新增") : L.t("保存"),
                          symbol: "checkmark",
                          disabled: !canSubmit) {
                onSave(candidate)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 计算

    private var isNew: Bool {
        return replacing == nil
    }

    private var subtitle: String {
        if let old = replacing {
            return L.t("会先删掉现在的 %@，再按下面的值加一条", old.networkLabel)
        }
        return L.t("临时写进系统路由表，不会保存到任何配置里")
    }

    private var candidate: Route {
        var route = draft
        route.destination = destination.trimmingCharacters(in: .whitespaces)
        route.subnetMask = normalizedMask
        route.gateway = gateway.trimmingCharacters(in: .whitespaces)
        route.metric = parsedMetric
        return route
    }

    private var parsedMetric: Int? {
        let text = metric.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        return Int(text)
    }

    /// 掩码框里允许填 `255.255.255.0`、`24` 或 `/24`，这里统一成点分写法。
    /// 归一化就地做，没有为它单开一个 IPv4 工具——只有这个表单用得上。
    private var normalizedMask: String {
        let text = mask.trimmingCharacters(in: .whitespaces)
        let digits = text.hasPrefix("/") ? String(text.dropFirst()) : text
        if let prefix = Int(digits), prefix >= 0, prefix <= 32 {
            return IPv4.prefixToMask(prefix)
        }
        return text
    }

    /// 掩码框旁边的回显：能算出前缀就给 `/24`，算不出来就提示怎么写。
    private var maskHint: String {
        if let prefix = IPv4.maskToPrefix(normalizedMask) {
            return "/\(prefix)"
        }
        return L.t("或填 24")
    }

    /// 第一条错误。nil 表示可以提交。
    private var validationError: String? {
        if !metric.trimmingCharacters(in: .whitespaces).isEmpty && parsedMetric == nil {
            return L.t("metric 要填一个整数，留空表示不设置")
        }
        if let prefix = candidate.prefixLength, prefix == 0 {
            // 默认路由的掩码是 0.0.0.0，走不到 Route.validationError 那句提示，这里单独说清楚。
            return L.t("不支持在这里设置前缀 0（默认路由），要换默认网关请到「系统设置 → 网络」或「配置管理」里改。")
        }
        return candidate.validationError
    }

    /// 底栏上显示的错误。还没开始填就不显示，免得一打开表单就一片红。
    private var shownError: String? {
        if isPristine { return nil }
        return validationError
    }

    /// 除了掩码（有默认值）之外一个字段都没动过。
    private var isPristine: Bool {
        let destinationText = destination.trimmingCharacters(in: .whitespaces)
        let gatewayText = gateway.trimmingCharacters(in: .whitespaces)
        let metricText = metric.trimmingCharacters(in: .whitespaces)
        return destinationText.isEmpty && gatewayText.isEmpty && metricText.isEmpty
    }

    private var canSubmit: Bool {
        return validationError == nil && !state.isRouteBusy
    }
}
