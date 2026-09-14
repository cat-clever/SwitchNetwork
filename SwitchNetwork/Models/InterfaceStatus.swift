import AppKit

/// SF Symbols 在不同系统版本上的可用集合不一样，
/// 这里做一次存在性检查，避免在旧系统上渲染出空白图标。
enum Symbols {
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func resolve(_ name: String, fallback: String = "network") -> String {
        let key = "\(name)|\(fallback)"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var resolved = "network"
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            resolved = name
        } else if NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil {
            resolved = fallback
        }

        lock.lock()
        cache[key] = resolved
        lock.unlock()
        return resolved
    }
}

enum InterfaceType: String, Codable {
    case ethernet
    case wifi
    case bridge
    case other

    var label: String {
        switch self {
        case .ethernet: return L.t("有线")
        case .wifi: return "Wi-Fi"
        case .bridge: return L.t("网桥")
        case .other: return L.t("其他")
        }
    }

    var symbolName: String {
        switch self {
        case .ethernet: return Symbols.resolve("cable.connector", fallback: "network")
        case .wifi: return Symbols.resolve("wifi", fallback: "network")
        case .bridge: return Symbols.resolve("arrow.triangle.merge", fallback: "network")
        case .other: return Symbols.resolve("questionmark.circle", fallback: "network")
        }
    }
}

/// 接口当前的 IPv4 配置来源。
enum InterfaceConfigurationMode: String {
    case manual
    case dhcp
    case bootp
    case off
    case unknown

    var label: String {
        switch self {
        case .manual: return L.t("手动")
        case .dhcp: return "DHCP"
        case .bootp: return "BootP"
        case .off: return L.t("已关闭")
        case .unknown: return L.t("未知")
        }
    }

    static func parse(_ line: String) -> InterfaceConfigurationMode {
        let text = line.lowercased()
        if text.contains("manual") { return .manual }
        if text.contains("dhcp") { return .dhcp }
        if text.contains("bootp") { return .bootp }
        if text.contains("off") { return .off }
        return .unknown
    }
}

/// 一个网络接口的实时状态快照。
struct InterfaceStatus: Identifiable, Equatable {
    var id: String { return identifier }

    /// BSD 设备名，如 en0。
    let identifier: String
    /// 系统里的硬件端口名，如 "USB 10/100/1000 LAN"。
    let displayName: String
    /// networksetup 使用的网络服务名，如 "外接网卡"。没有对应服务时为 nil，此时无法写入配置。
    let serviceName: String?
    let type: InterfaceType
    /// 网线已插入并完成链路协商 / Wi-Fi 已关联。
    let isConnected: Bool
    let currentIP: String?
    let currentMask: String?
    let currentGateway: String?
    let currentDNS: [String]
    let configurationMode: InterfaceConfigurationMode
    /// Wi-Fi 已关联的 SSID。新版 macOS 需要定位权限才能读到，无权限时为 nil。
    let ssid: String?

    var isConfigurable: Bool {
        return serviceName != nil
    }

    /// 跟在名字后面的设备名（如 en0）。和名字相同时返回 nil，界面据此不重复显示。
    var secondaryIdentifier: String? {
        return identifier == displayName ? nil : identifier
    }

    /// 「Ethernet · en0」这样的一行文字：先给人看的名字，再是设备名。
    var title: String {
        if let secondary = secondaryIdentifier {
            return "\(displayName) · \(secondary)"
        }
        return displayName
    }

    var connectionLabel: String {
        if isConnected {
            if let value = ssid, !value.isEmpty {
                return L.t("已连接 · %@", value)
            }
            return L.t("已连接")
        }
        return L.t("未连接")
    }

    var currentIPLabel: String {
        guard let ip = currentIP else { return L.t("无 IP") }
        if let mask = currentMask, let prefix = IPv4.maskToPrefix(mask) {
            return "\(ip)/\(prefix)"
        }
        return ip
    }

    /// 配置是否与该 Profile 完全一致：地址获取方式 + IP/掩码/网关 + DNS。
    func matches(_ profile: Profile) -> Bool {
        switch profile.ipMode {
        case .manual:
            if configurationMode != .manual { return false }
        case .dhcp:
            if configurationMode != .dhcp { return false }
        }
        if !profile.matchesCurrent(ip: currentIP, mask: currentMask, gateway: currentGateway) {
            return false
        }
        switch profile.dnsMode {
        case .automatic:
            // DNS 由系统获取，具体值不可预期，不做比对。
            return true
        case .manual:
            let expected = Set(profile.dnsServers.filter { !$0.isEmpty })
            return expected == Set(currentDNS)
        }
    }
}

/// 路由表里一条记录的来源，界面据此决定图标颜色、要不要给「编辑」、删前要不要二次确认。
///
/// 刻意不按 netstat 的 flags 判断来源：接口直连是 `UCS`、组播是 `UmCS`，都带 `S`，
/// 所以那个 `S` 不代表「手动添加」，拿它分类会把系统路由全标成用户加的。
enum RouteEntryOrigin: Hashable {
    /// 默认路由。删掉会立刻断网。
    case defaultRoute
    /// 接口直连网段，系统按接口地址自动生成。
    case link
    /// 本机回环与组播，系统自带。
    case local
    /// 其余：下一跳是真实地址，可能是手动加的，也可能是 VPN 生成的。
    case staticRoute
}

/// 当前系统路由表中的一条记录。
struct RouteEntry: Equatable, Identifiable {
    let destination: String
    let mask: String
    let gateway: String
    let interface: String
    let flags: String

    /// 同一网段可能有两条路由（下一跳不同），所以要和网关、接口一起才能定位到一行。
    /// flags 也带上：只有 flags 不同的两行同样是两行，不能让它们撞 id。
    var id: String {
        return "\(destination)/\(mask)#\(gateway)@\(interface)@\(flags)"
    }

    var isDefault: Bool {
        return destination == "0.0.0.0" && mask == "0.0.0.0"
    }

    var origin: RouteEntryOrigin {
        if isDefault { return .defaultRoute }
        // 组播和受限广播的下一跳也是 link#，但它更该归到「本机与组播」，
        // 所以这两类要先判，否则 224.0.0/4 会被算成接口直连。
        if isLocalOrMulticast { return .local }
        if gateway.hasPrefix("link#") { return .link }
        return .staticRoute
    }

    /// 网关是不是接口本身（link#N）而不是一个真实地址。这种路由不能用带网关的形式增删。
    var isInterfaceScope: Bool {
        return gateway.hasPrefix("link#")
    }

    /// 走 VPN 的接口，删它的路由等于断掉隧道。
    var isTunnelInterface: Bool {
        return interface.hasPrefix("utun") || interface.hasPrefix("ppp") || interface.hasPrefix("ipsec")
    }

    /// 是不是接口直连网段里的地址（本机所在网段），界面提示用。
    var isDirectlyConnectedScope: Bool {
        return origin == .link || origin == .local
    }

    private var isLocalOrMulticast: Bool {
        if IPv4.contains(address: destination, networkAddress: "127.0.0.0", mask: "255.0.0.0") { return true }
        if IPv4.contains(address: destination, networkAddress: "224.0.0.0", mask: "240.0.0.0") { return true }
        return destination == "255.255.255.255"
    }

    /// 前缀长度。掩码不是合法掩码时返回 nil——这种情况下这一行没法拼成 route 命令。
    var prefixLength: Int? {
        return IPv4.maskToPrefix(mask)
    }

    /// 「10.100.0.0/16」，默认路由显示成 default。
    var networkLabel: String {
        if isDefault { return "default" }
        guard let prefix = prefixLength else { return destination }
        return "\(destination)/\(prefix)"
    }

    var summary: String {
        if isDefault { return "default → \(gateway)" }
        if let prefix = prefixLength {
            return "\(destination)/\(prefix) → \(gateway)"
        }
        return "\(destination) → \(gateway)"
    }
}
