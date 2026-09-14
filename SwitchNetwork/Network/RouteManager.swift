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
        guard let result = try? Shell.run(Shell.netstatPath, ["-rn", "-f", "inet"]) else {
            Log.shared.error(L.t("执行 netstat 失败"))
            return []
        }
        guard result.succeeded else {
            Log.shared.error(L.t("读取路由表失败：%@", result.combinedMessage))
            return []
        }
        return parseNetstat(result.standardOutput)
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

    // MARK: - 私有

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
