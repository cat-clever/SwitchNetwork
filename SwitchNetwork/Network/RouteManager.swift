import Foundation

enum RouteError: LocalizedError {
    case invalidRoute(String)
    case conflict(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoute(let message): return message
        case .conflict(let message): return message
        case .commandFailed(let message): return message
        }
    }
}

/// 一次删除的结果。
///
/// 不能只看 route 的退出码：它遇到「表里本来就没有这条」时只打印一句 not in table，
/// 退出码仍是 0。所以「到底删掉了没有」得单独告诉调用方——没真删掉的那条不能进
/// 「本次删除」，否则用户一点撤回，就会把一条早就不存在、也不会再出现的路由加进表里。
struct RouteRemoval {
    let message: String
    let removed: Bool
}

enum RouteCheckStatus: Equatable {
    case ok
    case missing
    case wrongGateway(expected: String, actual: String)
    case maskMismatch(expected: String, actual: String)
    /// 该网段本来就是接口的直连网段，系统自带的路由优先级更高，静态路由覆盖不了。
    case connectedConflict(gateway: String)
    /// 还没点"检查"。
    case notChecked

    var label: String {
        switch self {
        case .ok:
            return L.t("已生效")
        case .missing:
            return L.t("路由表中不存在，需要添加")
        case .wrongGateway(let expected, let actual):
            return L.t("下一跳不符：期望 %@，实际 %@", expected, actual)
        case .maskMismatch(let expected, let actual):
            return L.t("掩码不符：期望 %@，实际 %@", expected, actual)
        case .connectedConflict(let gateway):
            return L.t("系统已存在直连路由（%@），静态路由无法覆盖", gateway)
        case .notChecked:
            return L.t("尚未检查")
        }
    }

    var isProblem: Bool {
        return self != .ok
    }
}

struct RouteCheckResult: Identifiable {
    var id: String { return route.id.uuidString }
    let route: Route
    let status: RouteCheckStatus
}

enum RouteManager {

    // MARK: - 读取

    static func currentRoutes() -> [RouteEntry] {
        return readRoutes().routes
    }

    /// 读整张 IPv4 路由表，并且告诉调用方这次到底读成功没有。
    ///
    /// macOS 的路由表不可能真的为空（至少有 lo0 和各接口的直连路由），
    /// 所以解析结果为空只可能是读失败。界面要能把「读失败」和「表是空的」分开显示，
    /// 否则一次 netstat 失败会让用户以为路由全没了。
    static func readRoutes() -> (routes: [RouteEntry], failed: Bool) {
        guard let result = try? Shell.run(Shell.netstatPath, ["-rn", "-f", "inet"]) else {
            Log.shared.error(L.t("执行 netstat 失败"))
            return ([], true)
        }
        guard result.succeeded else {
            Log.shared.error(L.t("读取路由表失败：%@", result.combinedMessage))
            return ([], true)
        }
        let routes = parseNetstat(result.standardOutput)
        return (routes, routes.isEmpty)
    }

    /// 解析 macOS 的 netstat 输出。注意它是 BSD 经典记法：
    /// 尾部为 0 的八位组会被省略，掩码要么写成 `/前缀`，要么由地址类别推断。
    /// ```
    /// default            192.168.137.1      UGScg          en0
    /// 10.188/24          10.188.0.10        UGSc           utun5
    /// 192.168.137        link#7             UCS            en0
    /// 127                127.0.0.1          UCS            lo0
    /// 224.0.0/4          link#7             UmCS           en0
    /// ```
    static func parseNetstat(_ text: String) -> [RouteEntry] {
        var entries: [RouteEntry] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("Routing tables") || line.hasPrefix("Internet:") { continue }
            if line.hasPrefix("Destination") { continue }

            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 4 else { continue }

            // 跳过 ARP / 链路层条目（`192.168.137.1 0:e0:4c:29:b:28 UHLWIir en0` 这种）。
            // 它们的「下一跳」是硬件地址而不是 IP，不归 route 命令管：删或改都会失败，
            // 摆在页面上还会被当成静态路由、给出一排点不动的按钮。
            // 硬件地址有两种写法（点分 `ff.ff.ff.ff.ff.ff`、冒号 `0:e0:4c:29:b:28`），
            // 所以判据是「不是 IPv4」，而不是「含冒号」——link#N 也是非 IPv4，但它要留着。
            if !tokens[1].hasPrefix("link#") && !IPv4.isValidAddress(tokens[1]) { continue }

            guard let interpreted = interpretDestination(tokens[0]) else { continue }
            entries.append(RouteEntry(destination: interpreted.network,
                                      mask: interpreted.mask,
                                      gateway: tokens[1],
                                      interface: tokens[3],
                                      flags: tokens[2]))
        }
        return entries
    }

    static func interpretDestination(_ token: String) -> (network: String, mask: String)? {
        if token == "default" {
            return ("0.0.0.0", "0.0.0.0")
        }

        var addressPart = token
        var prefix: Int?
        if let slashIndex = token.firstIndex(of: "/") {
            addressPart = String(token[token.startIndex..<slashIndex])
            let suffix = String(token[token.index(after: slashIndex)...])
            guard let value = Int(suffix), value >= 0, value <= 32 else { return nil }
            prefix = value
        }

        var octets = addressPart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard octets.count >= 1, octets.count <= 4 else { return nil }
        for octet in octets {
            guard let value = Int(octet), value >= 0, value <= 255 else { return nil }
        }

        if prefix == nil {
            // 没有显式前缀时按 A/B/C 类推断，这是 BSD 路由表的默认写法。
            switch octets.count {
            case 1: prefix = 8
            case 2: prefix = 16
            case 3: prefix = 24
            default: prefix = 32
            }
        }
        while octets.count < 4 {
            octets.append("0")
        }

        guard let prefixValue = prefix else { return nil }
        guard let value = IPv4.addressToUInt32(octets.joined(separator: ".")) else { return nil }
        let maskValue: UInt32 = prefixValue == 0 ? 0 : ~UInt32(0) << (32 - prefixValue)
        return (IPv4.string(from: value & maskValue), IPv4.prefixToMask(prefixValue))
    }

    /// 用 route -n get 精确查询某个目的网段当前走的是哪条路由。
    /// 查不到具体路由时系统会退回默认路由，据此可以判断"这条静态路由不存在"。
    static func lookup(destination: String) -> RouteEntry? {
        guard let result = try? Shell.run(Shell.routePath, ["-n", "get", destination]) else {
            return nil
        }
        guard result.succeeded else { return nil }
        return parseRouteGet(result.standardOutput)
    }

    static func parseRouteGet(_ text: String) -> RouteEntry? {
        var destination: String?
        var mask: String?
        var gateway = ""
        var interfaceName = ""
        var flags = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("route to:") { continue }

            if let value = value(after: "destination:", in: line) {
                destination = value
            } else if let value = value(after: "mask:", in: line) {
                mask = value
            } else if let value = value(after: "gateway:", in: line) {
                gateway = value
            } else if let value = value(after: "interface:", in: line) {
                interfaceName = value
            } else if let value = value(after: "flags:", in: line) {
                flags = value
            }
        }

        guard let rawDestination = destination, let rawMask = mask else { return nil }
        let resolvedDestination = rawDestination == "default" ? "0.0.0.0" : rawDestination
        let resolvedMask = rawMask == "default" ? "0.0.0.0" : rawMask
        return RouteEntry(destination: resolvedDestination,
                          mask: resolvedMask,
                          gateway: gateway,
                          interface: interfaceName,
                          flags: flags)
    }

    // MARK: - 检查

    static func check(_ profile: Profile) -> [RouteCheckResult] {
        var results: [RouteCheckResult] = []
        for route in profile.routes {
            results.append(RouteCheckResult(route: route, status: status(of: route)))
        }
        return results
    }

    static func status(of route: Route) -> RouteCheckStatus {
        guard let network = route.normalizedNetwork, let prefix = route.prefixLength else {
            return .missing
        }
        guard let entry = lookup(destination: "\(network)/\(prefix)") else {
            return .missing
        }
        if entry.isDefault && prefix != 0 {
            return .missing
        }
        if entry.destination != network {
            return .missing
        }
        if entry.gateway.hasPrefix("link#") {
            // 直连网段由系统自动生成路由，静态路由插不进去。
            return .connectedConflict(gateway: entry.gateway)
        }
        if entry.mask != route.subnetMask {
            return .maskMismatch(expected: route.subnetMask, actual: entry.mask)
        }
        if !route.gateway.isEmpty && entry.gateway != route.gateway {
            return .wrongGateway(expected: route.gateway, actual: entry.gateway)
        }
        return .ok
    }

    // MARK: - 写入

    /// 不存在则添加；存在但下一跳不同则先删除再添加做修正。
    @discardableResult
    static func apply(_ route: Route) throws -> String {
        guard let network = route.normalizedNetwork, let prefix = route.prefixLength else {
            throw RouteError.invalidRoute(L.t("路由参数不完整或格式错误，已跳过"))
        }
        if prefix == 0 {
            throw RouteError.invalidRoute(L.t("不支持用静态路由覆盖默认网关，请直接设置「网关」字段"))
        }

        let query = "\(network)/\(prefix)"
        if let existing = lookup(destination: query), !existing.isDefault {
            if existing.gateway.hasPrefix("link#") {
                throw RouteError.conflict(L.t("%@ 是系统直连路由（%@），静态路由无法覆盖，已跳过", query, existing.gateway))
            }
            if existing.gateway == route.gateway && existing.mask == route.subnetMask {
                return L.t("%@ 已存在且下一跳一致，跳过", query)
            }
            let removed = try delete(network: network, prefix: prefix, gateway: existing.gateway)
            let added = try add(route, network: network, prefix: prefix)
            return L.t("%@，%@", removed, added)
        }

        return try add(route, network: network, prefix: prefix)
    }

    @discardableResult
    static func remove(_ route: Route) throws -> String {
        guard let network = route.normalizedNetwork, let prefix = route.prefixLength else {
            throw RouteError.invalidRoute(L.t("路由参数不完整或格式错误，已跳过"))
        }
        var gateway = route.gateway
        if let existing = lookup(destination: "\(network)/\(prefix)"), !existing.isDefault {
            if existing.gateway.hasPrefix("link#") {
                throw RouteError.conflict(L.t("%@/%d 是系统直连路由，不属于静态路由，未做删除", network, prefix))
            }
            // 用路由表里真实的下一跳去删，否则 route delete 会报 not in table。
            gateway = existing.gateway
        }
        return try delete(network: network, prefix: prefix, gateway: gateway)
    }

    // MARK: - 路由表：按整行操作

    /// 删除路由表里的任意一条，包括系统自带的默认路由和接口直连路由。
    ///
    /// 和 `remove(_ route:)` 的分工：那个只处理「配置里的静态路由」，遇到 link# 直连
    /// 会主动拒绝。这个页面用户是直接对着路由表点的，所以照做，只把命令参数拼对。
    static func delete(entry: RouteEntry) throws -> RouteRemoval {
        guard let prefix = entry.prefixLength else {
            throw RouteError.invalidRoute(L.t("%@ 的掩码 %@ 不是合法掩码，无法删除这条路由",
                                              entry.destination, entry.mask))
        }
        let label = destinationLabel(entry, prefix: prefix)

        // 界面上显示的是上一次读的快照，这中间系统可能已经把这条撤了
        // （拔网线、DHCP 续约、VPN 断开都会）。用户的目的已经达到，不算失败，
        // 但也确实没删掉什么，所以要如实告诉调用方。
        guard isPresent(entry) else {
            return RouteRemoval(message: L.t("%@ 已经不在路由表里了", label), removed: false)
        }

        var arguments = ["-n", "delete"] + scopeArguments(entry)
            + destinationArguments(entry, prefix: prefix)
        // link#N 是 netstat 的内部链路表示，不是下一跳地址，传给 route 会被当成地址解析而失败，
        // 省略网关才删得掉；带真实网关的路由反过来必须带上，否则报 not in table。
        if !entry.isInterfaceScope && !entry.gateway.isEmpty {
            arguments.append(entry.gateway)
        }

        let result = try Shell.run(Shell.routePath, arguments, privileged: true)
        guard result.succeeded else {
            throw RouteError.commandFailed(L.t("route delete %@ 失败：%@", label, result.combinedMessage))
        }
        // route 删不掉时也可能给 0（例如写 routing socket 失败），所以不信退出码，读一次表确认。
        if isPresent(entry) {
            throw RouteError.commandFailed(L.t("route delete %@ 没有生效，这条路由还在表里", label))
        }
        return RouteRemoval(message: L.t("已删除 %@", label), removed: true)
    }

    /// 把删掉的一整行加回去（撤回用）。
    ///
    /// 用 RouteEntry 而不是 Route 作参数：`Route` 的校验不允许前缀 0，默认路由就永远还原不回来。
    /// 另外只有 RouteEntry 带接口名，link# 直连路由要靠它才能重建。
    @discardableResult
    static func restore(entry: RouteEntry) throws -> String {
        guard let prefix = entry.prefixLength else {
            throw RouteError.invalidRoute(L.t("%@ 的掩码 %@ 不是合法掩码，无法还原这条路由",
                                              entry.destination, entry.mask))
        }
        let label = destinationLabel(entry, prefix: prefix)

        // 系统可能已经把这一条重建了（接口路由很常见），那就没什么好还原的。
        // 比的是整行而不是网段：default 这种每个接口各有一条，只看网段会拿别的那条
        // 当自己，真正要还原的这一条反而漏掉。
        if isPresent(entry) {
            return L.t("%@ 已被系统重新生成，无需还原", label)
        }

        var arguments = ["-n", "add"] + scopeArguments(entry)
            + destinationArguments(entry, prefix: prefix)
        if entry.isInterfaceScope {
            guard !entry.interface.isEmpty else {
                throw RouteError.invalidRoute(L.t("%@ 是接口直连路由，但路由表里没给出接口名，无法还原", label))
            }
            // -interface 必须是最后一段修饰符（见 man route），所以放在网关的位置上。
            arguments.append(contentsOf: ["-interface", entry.interface])
        } else if !entry.gateway.isEmpty {
            arguments.append(entry.gateway)
        } else {
            throw RouteError.invalidRoute(L.t("%@ 在路由表里没有下一跳，无法还原", label))
        }

        let result = try Shell.run(Shell.routePath, arguments, privileged: true)
        guard result.succeeded else {
            throw RouteError.commandFailed(L.t("route add %@ 失败：%@", label, result.combinedMessage))
        }
        if !isPresent(entry) {
            throw RouteError.commandFailed(L.t("route add %@ 没有生效，这条路由不在表里", label))
        }
        return L.t("已还原 %@", label)
    }

    /// 这一行还在不在路由表里。
    ///
    /// 比网段、掩码、下一跳三样，不能只比网段：同一个网段可能并排好几条（下一跳不同，
    /// default 最典型——en0 一条、每个 bridge 各一条），只比网段会把「删掉其中一条」
    /// 看成「一条都没少」。
    static func isPresent(_ entry: RouteEntry) -> Bool {
        return currentRoutes().contains { item in
            return item.destination == entry.destination
                && item.mask == entry.mask
                && item.gateway == entry.gateway
        }
    }

    // MARK: - 私有

    /// 把操作范围钉在某个接口上，只用于默认路由。
    ///
    /// 一个接口可能各有一条 default（en0 一条、每个 bridge 一条），`route delete default`
    /// 不带限定删的是匹配到的第一条——用户点的是 bridge 那条，掉的很可能是 en0 的主出口。
    /// 这些 default 的网关又是 link#N，本来就不能靠网关区分，只剩 -ifscope 可用。
    ///
    /// -ifscope 是精确匹配，不是「缩小搜索范围」：它只认本身就绑定了接口的路由
    /// （flags 里那个 I，例如 `UCSIg`）。实测拿它去删一条不带 I 的普通路由，
    /// 命令返回 0 但路由纹丝不动。这个代价是有意接受的——最坏结果是「删不掉并明确报错」，
    /// 比「删错一条、当场断网」好得多，而且真删不动时 delete 的后置读表会把它变成失败提示。
    private static func scopeArguments(_ entry: RouteEntry) -> [String] {
        if entry.isDefault && entry.isInterfaceScope && !entry.interface.isEmpty {
            return ["-ifscope", entry.interface]
        }
        return []
    }

    /// route 命令里描述"哪条路由"的那一段。
    /// 默认路由用 `default` 这个写法：写成 `-net 0.0.0.0/0` 在部分系统版本上找不到表项。
    private static func destinationArguments(_ entry: RouteEntry, prefix: Int) -> [String] {
        if entry.isDefault { return ["default"] }
        return ["-net", "\(entry.destination)/\(prefix)"]
    }

    private static func destinationLabel(_ entry: RouteEntry, prefix: Int) -> String {
        return entry.isDefault ? "default" : "\(entry.destination)/\(prefix)"
    }

    private static func add(_ route: Route, network: String, prefix: Int) throws -> String {
        let target = "\(network)/\(prefix)"
        var arguments = ["-n", "add", "-net", target]
        if let metric = route.metric {
            arguments.append(contentsOf: ["-hopcount", String(metric)])
        }
        arguments.append(route.gateway)

        var result = try Shell.run(Shell.routePath, arguments, privileged: true)
        if !result.succeeded && route.metric != nil {
            // -hopcount 的摆放位置在不同系统版本上要求不一致，失败就退回不带 metric 的形式。
            Log.shared.warning(L.t("带 metric 添加路由失败，去掉 metric 重试：%@", result.combinedMessage))
            arguments = ["-n", "add", "-net", target, route.gateway]
            result = try Shell.run(Shell.routePath, arguments, privileged: true)
        }
        guard result.succeeded else {
            throw RouteError.commandFailed(L.t("route add %@ 失败：%@", target, result.combinedMessage))
        }
        return L.t("已添加 %@ → %@", target, route.gateway)
    }

    private static func delete(network: String, prefix: Int, gateway: String) throws -> String {
        let target = "\(network)/\(prefix)"
        var arguments = ["-n", "delete", "-net", target]
        if !gateway.isEmpty {
            arguments.append(gateway)
        }
        let result = try Shell.run(Shell.routePath, arguments, privileged: true)
        guard result.succeeded else {
            throw RouteError.commandFailed(L.t("route delete %@ 失败：%@", target, result.combinedMessage))
        }
        return L.t("已删除 %@", target)
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
