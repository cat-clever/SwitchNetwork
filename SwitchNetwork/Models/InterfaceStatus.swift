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

/// 当前系统路由表中的一条记录。
struct RouteEntry: Equatable {
    let destination: String
    let mask: String
    let gateway: String
    let interface: String
    let flags: String

    var isDefault: Bool {
        return destination == "0.0.0.0" && mask == "0.0.0.0"
    }

    var summary: String {
        if isDefault { return "default → \(gateway)" }
        if let prefix = IPv4.maskToPrefix(mask) {
            return "\(destination)/\(prefix) → \(gateway)"
        }
        return "\(destination) → \(gateway)"
    }
}
