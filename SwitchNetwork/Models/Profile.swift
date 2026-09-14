import Foundation

/// IP / 掩码 / 网关 的来源。
enum IPMode: String, Codable, CaseIterable, Identifiable {
    /// 手工填写的静态地址。
    case manual
    /// 由 DHCP 服务器下发。
    case dhcp

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .manual: return L.t("手动")
        case .dhcp: return "DHCP"
        }
    }

    var detail: String {
        switch self {
        case .manual: return L.t("手工填写 IP、掩码和网关")
        case .dhcp: return L.t("IP、掩码和网关由 DHCP 服务器下发，本地填写的值会被忽略")
        }
    }
}

/// DNS 的来源。和 IP 的来源相互独立：用 DHCP 拿地址同样可以指定固定 DNS，
/// 用静态地址也可以让 DNS 自动获取。
enum DNSMode: String, Codable, CaseIterable, Identifiable {
    /// 手工指定的 DNS 列表。
    case manual
    /// 清空手动列表，由系统按当前地址的获取方式决定。
    case automatic

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .manual: return L.t("手动指定")
        case .automatic: return L.t("自动获取")
        }
    }

    var detail: String {
        switch self {
        case .manual: return L.t("按下面的列表顺序使用")
        case .automatic: return L.t("清空手动 DNS，交给系统获取。DHCP 下就是服务器下发的 DNS")
        }
    }
}

/// 一条静态路由。
struct Route: Identifiable, Codable, Equatable {
    var id: UUID
    var destination: String
    var subnetMask: String
    var gateway: String
    var metric: Int?

    init(id: UUID = UUID(),
         destination: String = "",
         subnetMask: String = "255.255.255.0",
         gateway: String = "",
         metric: Int? = nil) {
        self.id = id
        self.destination = destination
        self.subnetMask = subnetMask
        self.gateway = gateway
        self.metric = metric
    }

    private enum CodingKeys: String, CodingKey {
        case id, destination, subnetMask, gateway, metric
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.value(.id, default: UUID())
        destination = container.value(.destination, default: "")
        subnetMask = container.value(.subnetMask, default: "255.255.255.0")
        gateway = container.value(.gateway, default: "")
        metric = container.optionalValue(.metric)
    }

    /// 归一化后的网段地址，"10.0.0.5 / 255.255.255.0" -> "10.0.0.0"。
    var normalizedNetwork: String? {
        return IPv4.networkAddress(destination: destination, mask: subnetMask)
    }

    var prefixLength: Int? {
        return IPv4.maskToPrefix(subnetMask)
    }

    var summary: String {
        let network = normalizedNetwork ?? destination
        if let prefix = prefixLength {
            return "\(network)/\(prefix) → \(gateway)"
        }
        return "\(network) → \(gateway)"
    }

    var validationError: String? {
        if destination.isEmpty { return L.t("缺少目的网段") }
        if !IPv4.isValidAddress(destination) { return L.t("目的网段格式不正确") }
        if !IPv4.isValidMask(subnetMask) { return L.t("子网掩码不正确") }
        if !IPv4.isValidAddress(gateway) { return L.t("下一跳网关不正确") }
        if let value = metric, value < 0 { return L.t("metric 不能为负数") }
        if let prefix = prefixLength, prefix == 0 {
            return L.t("不支持用静态路由覆盖默认网关，请改用「网关」字段")
        }
        return nil
    }
}

/// 一套网络配置档案。
struct Profile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    /// BSD 设备名，如 en0。实际匹配用这个。
    var interfaceIdentifier: String
    /// 用户在系统里看到的名称，如 "外接网卡"。
    var interfaceDisplayName: String
    /// IP / 掩码 / 网关 的来源。为 .dhcp 时下面三个字段不参与校验和写入。
    var ipMode: IPMode
    var ipAddress: String
    var subnetMask: String
    var gateway: String
    /// DNS 的来源。为 .automatic 时 dnsServers 不参与校验和写入。
    var dnsMode: DNSMode
    var dnsServers: [String]
    var routes: [Route]
    /// 同一 interfaceIdentifier 下最多只能有一个为 true。
    var autoApplyOnConnect: Bool
    /// 应用这份配置时，把该接口对应的网络服务提到「网络服务优先级」的第一位。
    var promoteServiceToTop: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String = "",
         interfaceIdentifier: String = "",
         interfaceDisplayName: String = "",
         ipMode: IPMode = .manual,
         ipAddress: String = "",
         subnetMask: String = "255.255.255.0",
         gateway: String = "",
         dnsMode: DNSMode = .automatic,
         dnsServers: [String] = [],
         routes: [Route] = [],
         autoApplyOnConnect: Bool = false,
         promoteServiceToTop: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.interfaceIdentifier = interfaceIdentifier
        self.interfaceDisplayName = interfaceDisplayName
        self.ipMode = ipMode
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.gateway = gateway
        self.dnsMode = dnsMode
        self.dnsServers = dnsServers
        self.routes = routes
        self.autoApplyOnConnect = autoApplyOnConnect
        self.promoteServiceToTop = promoteServiceToTop
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, interfaceIdentifier, interfaceDisplayName
        case ipMode, ipAddress, subnetMask, gateway
        case dnsMode, dnsServers, routes
        case autoApplyOnConnect, promoteServiceToTop, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.value(.id, default: UUID())
        name = container.value(.name, default: "")
        interfaceIdentifier = container.value(.interfaceIdentifier, default: "")
        interfaceDisplayName = container.value(.interfaceDisplayName, default: "")
        // 旧数据没有模式字段，一律按静态地址处理，保持原来的行为。
        ipMode = container.value(.ipMode, default: .manual)
        ipAddress = container.value(.ipAddress, default: "")
        subnetMask = container.value(.subnetMask, default: "255.255.255.0")
        gateway = container.value(.gateway, default: "")
        dnsServers = container.value(.dnsServers, default: [])

        let decodedDNSMode: DNSMode? = container.optionalValue(.dnsMode)
        if let decoded = decodedDNSMode {
            dnsMode = decoded
        } else {
            // 旧数据没有这个字段：列表为空说明本来就是"交给系统"，否则是手动指定。
            dnsMode = dnsServers.isEmpty ? .automatic : .manual
        }

        routes = container.value(.routes, default: [])
        autoApplyOnConnect = container.value(.autoApplyOnConnect, default: false)
        promoteServiceToTop = container.value(.promoteServiceToTop, default: false)
        createdAt = container.value(.createdAt, default: Date())
        updatedAt = container.value(.updatedAt, default: Date())
    }

    // MARK: - 展示

    var ipSummary: String {
        if ipMode == .dhcp { return L.t("DHCP 自动获取") }
        if ipAddress.isEmpty { return L.t("未设置 IP") }
        if let prefix = IPv4.maskToPrefix(subnetMask) {
            return "\(ipAddress)/\(prefix)"
        }
        return ipAddress
    }

    var dnsSummary: String {
        if dnsMode == .automatic { return L.t("DNS 自动获取") }
        let cleaned = dnsServers.filter { !$0.isEmpty }
        if cleaned.isEmpty { return L.t("DNS 未设置") }
        return cleaned.joined(separator: ", ")
    }

    /// 手写的网关只在静态地址下有意义。
    var gatewaySummary: String? {
        if ipMode == .dhcp { return nil }
        if gateway.isEmpty { return nil }
        return L.t("网关 %@", gateway)
    }

    // MARK: - 校验

    var validationErrors: [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(L.t("名称不能为空"))
        }
        if interfaceIdentifier.isEmpty {
            errors.append(L.t("必须选择绑定的网络接口"))
        }

        // DHCP 下 IP、掩码、网关都由服务器下发，本地填的值会被忽略，因此不校验。
        if ipMode == .manual {
            if ipAddress.isEmpty {
                errors.append(L.t("IP 地址不能为空"))
            } else if !IPv4.isValidAddress(ipAddress) {
                errors.append(L.t("IP 地址格式不正确"))
            }
            if !IPv4.isValidMask(subnetMask) {
                errors.append(L.t("子网掩码不正确，必须是连续的网络位（如 255.255.255.0）"))
            }
            if !IPv4.isValidGateway(gateway) {
                errors.append(L.t("网关格式不正确"))
            }
            if !gateway.isEmpty, !ipAddress.isEmpty, IPv4.isValidMask(subnetMask) {
                if let network = IPv4.networkAddress(destination: ipAddress, mask: subnetMask) {
                    if !IPv4.contains(address: gateway, networkAddress: network, mask: subnetMask) {
                        errors.append(L.t("网关 %@ 不在本机网段 %@ 内，请确认", gateway, network))
                    }
                }
            }
        }

        if dnsMode == .manual {
            let cleaned = dnsServers.filter { !$0.isEmpty }
            if cleaned.isEmpty {
                errors.append(L.t("DNS 选了「手动指定」就至少要填一个地址，或改成「自动获取」"))
            }
            for (index, server) in dnsServers.enumerated() where !server.isEmpty {
                if !IPv4.isValidAddress(server) {
                    errors.append(L.t("第 %d 个 DNS 地址格式不正确", index + 1))
                }
            }
        }

        for (index, route) in routes.enumerated() {
            if let error = route.validationError {
                errors.append(L.t("路由 %d：%@", index + 1, error))
            }
        }
        return errors
    }

    var isValid: Bool {
        return validationErrors.isEmpty
    }

    /// 当前地址/掩码/网关 是否与给定值一致，用于判断"这个 Profile 是否正在生效"。
    /// 配置方式的比对在 InterfaceStatus.matches(_:) 里做，这里只管数值。
    func matchesCurrent(ip: String?, mask: String?, gateway: String?) -> Bool {
        // DHCP 分的地址事先无法预知，只能靠"配置方式是不是 DHCP"来判断。
        if ipMode == .dhcp { return true }
        guard let currentIP = ip, let currentMask = mask else { return false }
        if currentIP != ipAddress { return false }
        if currentMask != subnetMask { return false }
        if !self.gateway.isEmpty, let currentGateway = gateway {
            if currentGateway != self.gateway { return false }
        }
        return true
    }
}
