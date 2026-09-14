import Foundation

enum ConfiguratorError: LocalizedError {
    case permissionDenied
    case commandFailed(String)
    case noService(String)
    case notConnected(String)
    case invalidProfile([String])

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L.t("缺少 root 权限。请在「设置 → 权限」里按提示安装 sudo 免密授权。")
        case .commandFailed(let message):
            return message
        case .noService(let identifier):
            return L.t("接口 %@ 在系统里没有对应的网络服务，无法写入配置", identifier)
        case .notConnected(let identifier):
            return L.t("接口 %@ 当前未连接，已跳过自动应用", identifier)
        case .invalidProfile(let errors):
            return errors.joined(separator: L.listSeparator)
        }
    }
}

enum StepOutcome {
    case success
    case warning
    case failure
}

struct ApplyStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let outcome: StepOutcome
}

struct ApplyReport {
    /// nil 表示这不是「应用某份配置」，而是把接口交还系统，措辞要换一套。
    let profileID: UUID?
    let profileName: String
    let interfaceIdentifier: String
    let steps: [ApplyStep]

    var isRestore: Bool {
        return profileID == nil
    }

    var hasFailure: Bool {
        return steps.contains { $0.outcome == .failure }
    }

    var failureMessages: [String] {
        return steps.filter { $0.outcome == .failure }.map { L.t("%@：%@", $0.title, $0.detail) }
    }

    var warningCount: Int {
        return steps.filter { $0.outcome == .warning }.count
    }

    var summary: String {
        if steps.isEmpty { return L.t("没有执行任何操作") }
        if isRestore {
            if hasFailure {
                return L.t("接口 %@ 交还系统失败：%@", interfaceIdentifier, failureMessages.joined(separator: L.listSeparator))
            }
            if warningCount == 0 {
                return L.t("接口 %@ 已交还系统：IP 走 DHCP，DNS 自动获取", interfaceIdentifier)
            }
            return L.t("接口 %@ 已交还系统（%d 项提示）", interfaceIdentifier, warningCount)
        }
        if hasFailure {
            return L.t("%@ 应用失败：%@", profileName, failureMessages.joined(separator: L.listSeparator))
        }
        if warningCount == 0 {
            return L.t("%@ 已应用到 %@", profileName, interfaceIdentifier)
        }
        return L.t("%@ 已应用到 %@（%d 项提示）", profileName, interfaceIdentifier, warningCount)
    }
}

/// 把 Profile 真正写进系统：IP/掩码/网关 → DNS → 静态路由。
enum NetworkConfigurator {

    /// - Parameter requireConnected: 自动应用时为 true，未连接直接跳过（需求文档要求）。
    ///   用户在主窗口手动点"应用"时传 false，允许先写好配置等接口连上再生效。
    static func apply(_ profile: Profile,
                      to status: InterfaceStatus,
                      requireConnected: Bool) -> ApplyReport {
        var steps: [ApplyStep] = []

        func finish() -> ApplyReport {
            return ApplyReport(profileID: profile.id,
                               profileName: profile.name,
                               interfaceIdentifier: status.identifier,
                               steps: steps)
        }

        let errors = profile.validationErrors
        if !errors.isEmpty {
            for error in errors {
                steps.append(ApplyStep(title: L.t("配置校验"), detail: error, outcome: .failure))
            }
            return finish()
        }

        guard let service = status.serviceName else {
            steps.append(ApplyStep(title: L.t("网络服务"),
                                   detail: ConfiguratorError.noService(status.identifier).localizedDescription,
                                   outcome: .failure))
            return finish()
        }

        if requireConnected && !status.isConnected {
            steps.append(ApplyStep(title: L.t("连接状态"),
                                   detail: ConfiguratorError.notConnected(status.identifier).localizedDescription,
                                   outcome: .warning))
            return finish()
        }
        if !status.isConnected {
            steps.append(ApplyStep(title: L.t("连接状态"),
                                   detail: L.t("接口当前未连接，配置已写入，待接口连上后生效"),
                                   outcome: .warning))
        }

        // 1. IP / 掩码 / 网关
        do {
            let detail: String
            switch profile.ipMode {
            case .manual:
                detail = try setManual(service: service, profile: profile)
            case .dhcp:
                detail = try setDHCP(service: service)
            }
            steps.append(ApplyStep(title: L.t("IP 配置"), detail: detail, outcome: .success))
        } catch {
            steps.append(ApplyStep(title: L.t("IP 配置"), detail: error.localizedDescription, outcome: .failure))
            // IP 都没写进去，后面的 DNS 和路由没有意义
            return finish()
        }

        // 2. DNS
        do {
            let detail: String
            switch profile.dnsMode {
            case .manual:
                detail = try setDNS(service: service, servers: profile.dnsServers)
            case .automatic:
                detail = try setDNSAutomatic(service: service)
            }
            steps.append(ApplyStep(title: "DNS", detail: detail, outcome: .success))
        } catch {
            steps.append(ApplyStep(title: "DNS", detail: error.localizedDescription, outcome: .failure))
        }

        // 3. 静态路由
        if profile.routes.isEmpty {
            steps.append(ApplyStep(title: L.t("静态路由"), detail: L.t("该配置没有静态路由"), outcome: .success))
        } else {
            for (index, route) in profile.routes.enumerated() {
                let title = L.t("路由 %d", index + 1)
                do {
                    let detail = try RouteManager.apply(route)
                    steps.append(ApplyStep(title: title, detail: detail, outcome: .success))
                } catch {
                    steps.append(ApplyStep(title: title,
                                           detail: L.t("%@ — %@", route.summary, error.localizedDescription),
                                           outcome: .failure))
                }
            }
        }

        // 4. 服务顺序置顶。放在最后：先让接口能通，再决定它的优先级。
        if profile.promoteServiceToTop {
            do {
                let detail = try promoteServiceToTop(service)
                steps.append(ApplyStep(title: L.t("服务优先级"), detail: detail, outcome: .success))
            } catch {
                steps.append(ApplyStep(title: L.t("服务优先级"),
                                       detail: error.localizedDescription,
                                       outcome: .failure))
            }
        }

        return finish()
    }

    // MARK: - 交还系统

    /// 「不使用配置」：把这个接口交还系统——IP 切回 DHCP、DNS 改自动获取、
    /// 删掉本应用写进去的静态路由。
    ///
    /// 顺序和 apply 相反：先撤路由再换 IP。静态路由的下一跳还在旧网段里，
    /// 先换 IP 的话中间那段时间会有流量被丢进黑洞。
    static func restoreToSystem(for status: InterfaceStatus, routes: [Route]) -> ApplyReport {
        var steps: [ApplyStep] = []

        func finish() -> ApplyReport {
            return ApplyReport(profileID: nil,
                               profileName: L.t("不使用配置"),
                               interfaceIdentifier: status.identifier,
                               steps: steps)
        }

        guard let service = status.serviceName else {
            steps.append(ApplyStep(title: L.t("网络服务"),
                                   detail: ConfiguratorError.noService(status.identifier).localizedDescription,
                                   outcome: .failure))
            return finish()
        }

        if !status.isConnected {
            steps.append(ApplyStep(title: L.t("连接状态"),
                                   detail: L.t("接口当前未连接，已写入的撤销要等接口连上才生效"),
                                   outcome: .warning))
        }

        // 1. 静态路由
        if routes.isEmpty {
            steps.append(ApplyStep(title: L.t("静态路由"), detail: L.t("没有需要撤销的静态路由"), outcome: .success))
        } else {
            for (index, route) in routes.enumerated() {
                let title = L.t("路由 %d", index + 1)
                let summary = route.summary
                // 本来就不在表里（比如手工删过、或者这条一直没写成功），
                // 直接去 route delete 只会拿到 not in table 的报错，先查一下再说。
                if RouteManager.status(of: route) == .missing {
                    steps.append(ApplyStep(title: title,
                                           detail: L.t("%@ 不在路由表里，无需撤销", summary),
                                           outcome: .success))
                    continue
                }
                do {
                    let detail = try RouteManager.remove(route)
                    steps.append(ApplyStep(title: title, detail: detail, outcome: .success))
                } catch RouteError.conflict(let message), RouteError.invalidRoute(let message) {
                    // 系统直连路由不是本应用写的，撤不走也不算失败。
                    steps.append(ApplyStep(title: title, detail: message, outcome: .warning))
                } catch {
                    steps.append(ApplyStep(title: title,
                                           detail: L.t("%@ — %@", summary, error.localizedDescription),
                                           outcome: .failure))
                }
            }
        }

        // 2. IP / 掩码 / 网关 交还 DHCP
        do {
            let detail = try setDHCP(service: service)
            steps.append(ApplyStep(title: L.t("IP 配置"), detail: detail, outcome: .success))
        } catch {
            steps.append(ApplyStep(title: L.t("IP 配置"), detail: error.localizedDescription, outcome: .failure))
            // DHCP 都没切过去，DNS 维持现状至少还能用旧的解析器
            return finish()
        }

        // 3. DNS 交还自动获取
        do {
            let detail = try setDNSAutomatic(service: service)
            steps.append(ApplyStep(title: "DNS", detail: detail, outcome: .success))
        } catch {
            steps.append(ApplyStep(title: "DNS", detail: error.localizedDescription, outcome: .failure))
        }

        return finish()
    }

    // MARK: - 单项操作

    static func setManual(service: String, profile: Profile) throws -> String {
        var arguments = ["-setmanual", service, profile.ipAddress, profile.subnetMask]
        if !profile.gateway.isEmpty {
            arguments.append(profile.gateway)
        }
        try runNetworksetup(arguments)

        var detail = "\(profile.ipAddress) / \(profile.subnetMask)"
        if !profile.gateway.isEmpty {
            detail += L.t(" / 网关 %@", profile.gateway)
        }
        return detail
    }

    /// 切换为 DHCP。networksetup 没有"保留静态网关"的选项，
    /// 所以 DHCP 模式下网关一定由服务器下发。
    static func setDHCP(service: String) throws -> String {
        try runNetworksetup(["-setdhcp", service])
        return L.t("已切换为 DHCP，IP / 掩码 / 网关由服务器下发")
    }

    static func setDNS(service: String, servers: [String]) throws -> String {
        let cleaned = servers.filter { !$0.isEmpty }
        let arguments = ["-setdnsservers", service] + (cleaned.isEmpty ? ["Empty"] : cleaned)
        try runNetworksetup(arguments)
        return cleaned.isEmpty ? L.t("已清空，回退到自动获取") : cleaned.joined(separator: ", ")
    }

    /// 清空手动 DNS 列表。networksetup 用关键字 Empty 表示"不指定"，
    /// 之后系统按当前地址的获取方式决定：DHCP 就用服务器下发的 DNS。
    static func setDNSAutomatic(service: String) throws -> String {
        try runNetworksetup(["-setdnsservers", service, "Empty"])
        return L.t("已清空手动 DNS，交给系统自动获取")
    }

    /// 把某条路由从系统里删掉（供界面上的"删除此路由"使用）。
    @discardableResult
    static func removeRoute(_ route: Route) throws -> String {
        return try RouteManager.remove(route)
    }

    /// 写入网络服务优先级（macOS 的"服务顺序"）。
    ///
    /// networksetup 要求把**所有**服务都列出来，少一个就会整体失败，
    /// 所以先跟系统里的服务集合核对一遍：只要对不上就直接拒绝，不去赌系统的容错。
    static func applyServiceOrder(_ names: [String]) throws -> String {
        guard !names.isEmpty else {
            throw ConfiguratorError.commandFailed(L.t("服务列表为空，已取消写入顺序"))
        }
        let existing = NetworkServiceMap.loadNames()
        guard names.count == existing.count, Set(names) == Set(existing) else {
            throw ConfiguratorError.commandFailed(
                L.t("服务列表与系统不一致（系统里共 %d 项），已取消写入顺序", existing.count))
        }
        try runNetworksetup(["-ordernetworkservices"] + names)
        return L.t("已应用 %d 项服务的顺序", names.count)
    }

    /// 把某个网络服务提到顺序的第一位，其他服务的相对顺序不动。
    /// `name` 是 networksetup 的服务名，不是 en0 这种设备名。
    @discardableResult
    static func promoteServiceToTop(_ name: String) throws -> String {
        let existing = NetworkServiceMap.loadNames()
        guard existing.contains(name) else {
            throw ConfiguratorError.commandFailed(L.t("系统里找不到服务「%@」，无法调整优先级", name))
        }
        if existing.first == name {
            return L.t("「%@」本来就在最前面", name)
        }
        var reordered = existing
        reordered.removeAll { $0 == name }
        reordered.insert(name, at: 0)
        // 复用上面那份"服务集合必须完全一致"的校验，不另写一遍。
        _ = try applyServiceOrder(reordered)
        return L.t("已把「%@」提到最前面", name)
    }

    @discardableResult
    private static func runNetworksetup(_ arguments: [String]) throws -> String {
        let result = try Shell.run(Shell.networksetupPath, arguments, privileged: true)
        if result.isPermissionDenied {
            throw ConfiguratorError.permissionDenied
        }
        guard result.succeeded else {
            throw ConfiguratorError.commandFailed(result.combinedMessage)
        }
        // networksetup 偶发会以退出码 0 结束、却把失败原因写在 stderr 里，
        // 静默的成功会导致"看起来生效了其实没有"，这里把它当失败处理。
        let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.range(of: "error", options: .caseInsensitive) != nil {
            throw ConfiguratorError.commandFailed(message)
        }
        return result.standardOutput
    }
}
