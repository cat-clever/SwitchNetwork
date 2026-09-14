import Foundation
import SystemConfiguration
import CoreWLAN

/// 枚举所有网络接口并汇总它们的实时状态。
///
/// 链路状态来自 SCDynamicStore 的 `State:/Network/Interface/<bsd>/Link`，
/// 这个键对有线（网线插入并完成协商）和 Wi-Fi（已关联）都有效，
/// 因此不需要为两种介质各写一套判断逻辑。
enum InterfaceEnumerator {

    static func enumerate() -> [InterfaceStatus] {
        let services = NetworkServiceMap.load()
        let store = SCDynamicStoreCreate(nil, "com.CleverCat.SwitchNetwork.enumerate" as CFString, nil, nil)

        var results: [InterfaceStatus] = []
        for interface in allInterfaces() {
            guard let bsdValue = SCNetworkInterfaceGetBSDName(interface) else { continue }
            let bsd = bsdValue as String

            let service = NetworkServiceMap.resolve(device: bsd, in: services)
            let localizedName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            let typeName = SCNetworkInterfaceGetInterfaceType(interface)
            let connected = readLinkActive(store: store, bsd: bsd)

            // 没有对应网络服务的接口无法写入配置。这类接口只在"已连接"时才展示，
            // 否则一堆闲置的雷雳口会把界面塞满。
            if service == nil {
                if !connected || !bsd.hasPrefix("en") { continue }
            }

            let type = detectType(typeName: typeName, displayName: localizedName, bsd: bsd)
            let displayName = localizedName ?? bsd

            var ip: String?
            var mask: String?
            var gateway: String?
            var mode = InterfaceConfigurationMode.unknown
            var dns: [String] = []

            if let found = service {
                let serviceName = found.name
                let config = ServiceConfigReader.read(serviceName)
                mode = config.mode
                ip = config.ip
                mask = config.mask
                gateway = config.gateway
                dns = ServiceConfigReader.readDNS(serviceName)
            } else if let address = readIPv4(store: store, bsd: bsd) {
                ip = address.ip
                mask = address.mask
            }

            var ssid: String?
            if type == .wifi, connected {
                ssid = WiFiSSIDReader.currentSSID(forBSDName: bsd)
            }

            var resolvedServiceName: String?
            if let found = service {
                resolvedServiceName = found.name
            }

            results.append(InterfaceStatus(identifier: bsd,
                                           displayName: displayName,
                                           serviceName: resolvedServiceName,
                                           type: type,
                                           isConnected: connected,
                                           currentIP: ip,
                                           currentMask: mask,
                                           currentGateway: gateway,
                                           currentDNS: dns,
                                           configurationMode: mode,
                                           ssid: ssid))
        }

        results.sort { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            if lhs.isConfigurable != rhs.isConfigurable { return lhs.isConfigurable }
            return sortKey(lhs.identifier) < sortKey(rhs.identifier)
        }
        return results
    }

    // MARK: - SystemConfiguration

    private static func allInterfaces() -> [SCNetworkInterface] {
        let rawList: CFArray = SCNetworkInterfaceCopyAll()
        var interfaces: [SCNetworkInterface] = []
        let count = CFArrayGetCount(rawList)
        var index = 0
        while index < count {
            let pointer = CFArrayGetValueAtIndex(rawList, index)
            index += 1
            guard let pointer = pointer else { continue }
            interfaces.append(Unmanaged<SCNetworkInterface>.fromOpaque(pointer).takeUnretainedValue())
        }
        return interfaces
    }

    private static func readLinkActive(store: SCDynamicStore?, bsd: String) -> Bool {
        guard let store = store else { return false }
        let key = "State:/Network/Interface/\(bsd)/Link" as CFString
        guard let raw = SCDynamicStoreCopyValue(store, key) else { return false }
        guard let dictionary = raw as? [String: Any] else { return false }
        if let flag = dictionary["Active"] as? Bool { return flag }
        if let number = dictionary["Active"] as? NSNumber { return number.boolValue }
        return false
    }

    private static func readIPv4(store: SCDynamicStore?, bsd: String) -> (ip: String, mask: String)? {
        guard let store = store else { return nil }
        let key = "State:/Network/Interface/\(bsd)/IPv4" as CFString
        guard let raw = SCDynamicStoreCopyValue(store, key) else { return nil }
        guard let dictionary = raw as? [String: Any] else { return nil }
        guard let addresses = dictionary["Addresses"] as? [String] else { return nil }
        guard let first = addresses.first else { return nil }
        var mask = ""
        if let masks = dictionary["SubnetMasks"] as? [String], let firstMask = masks.first {
            mask = firstMask
        }
        return (first, mask)
    }

    private static func detectType(typeName: CFString?, displayName: String?, bsd: String) -> InterfaceType {
        if let typeName = typeName {
            if CFStringCompare(typeName, kSCNetworkInterfaceTypeIEEE80211, []) == .compareEqualTo {
                return .wifi
            }
            if CFStringCompare(typeName, kSCNetworkInterfaceTypeEthernet, []) == .compareEqualTo {
                if bsd.hasPrefix("bridge") { return .bridge }
                return .ethernet
            }
        }
        if bsd.hasPrefix("bridge") { return .bridge }
        if let name = displayName {
            let lowered = name.lowercased()
            if lowered.contains("wi-fi") || lowered.contains("wifi") || lowered.contains("airport") {
                return .wifi
            }
        }
        if bsd.hasPrefix("en") { return .ethernet }
        return .other
    }

    /// 让 en2 排在 en11 前面，而不是按字典序把 en11 排到 en2 前面。
    private static func sortKey(_ identifier: String) -> (String, Int) {
        var letters = ""
        var digits = ""
        for character in identifier {
            if character.isNumber {
                digits.append(character)
            } else if digits.isEmpty {
                letters.append(character)
            }
        }
        return (letters, Int(digits) ?? 0)
    }
}

/// 读取 Wi-Fi 当前关联的 SSID。
/// macOS 14 起读取 SSID 需要定位权限，没有权限时系统只会返回 nil，这里按"读不到就不显示"处理。
enum WiFiSSIDReader {

    private static let lock = NSLock()
    private static var warned = false

    static func currentSSID(forBSDName bsd: String) -> String? {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else { return nil }
        guard let interfaceName = interface.interfaceName else { return nil }
        if interfaceName != bsd { return nil }
        guard let ssid = interface.ssid() else {
            warnOnce()
            return nil
        }
        return ssid
    }

    private static func warnOnce() {
        lock.lock()
        let shouldWarn = !warned
        warned = true
        lock.unlock()
        if shouldWarn {
            Log.shared.info(L.t("读不到 Wi-Fi 的 SSID，通常是未授予定位权限；不影响连接状态的判断。"))
        }
    }
}
