import Foundation

struct ServiceConfig {
    let mode: InterfaceConfigurationMode
    let ip: String?
    let mask: String?
    let gateway: String?

    static let unknown = ServiceConfig(mode: .unknown, ip: nil, mask: nil, gateway: nil)
}

/// 读取某个网络服务当前的 IPv4 配置。
/// 用 networksetup -getinfo 而不是 SCDynamicStore，因为前者显示的正是我们写入的那份配置，
/// 拿它跟 Profile 比对才能判断"这个配置到底有没有生效"。
enum ServiceConfigReader {

    static func read(_ serviceName: String) -> ServiceConfig {
        guard let result = try? Shell.run(Shell.networksetupPath, ["-getinfo", serviceName]) else {
            return .unknown
        }
        guard result.succeeded else {
            Log.shared.warning(L.t("读取 %@ 的配置失败：%@", serviceName, result.combinedMessage))
            return .unknown
        }
        return parse(result.standardOutput)
    }

    /// 解析形如下面的输出：
    /// ```
    /// Manual Configuration
    /// IP address: 192.168.137.166
    /// Subnet mask: 255.255.255.0
    /// Router: 192.168.137.1
    ///
    /// Ethernet Address: d0:11:e5:94:6c:f8
    /// ```
    static func parse(_ text: String) -> ServiceConfig {
        var mode = InterfaceConfigurationMode.unknown
        var ip: String?
        var mask: String?
        var gateway: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasSuffix("Configuration") {
                mode = InterfaceConfigurationMode.parse(line)
                continue
            }
            // 必须排在 "IP address:" 之前，否则 "IPv6 IP address:" 会被误判成 IPv4。
            if line.hasPrefix("IPv6") { continue }

            if let value = value(after: "IP address:", in: line) {
                if IPv4.isValidAddress(value) { ip = value }
                continue
            }
            if let value = value(after: "Subnet mask:", in: line) {
                if IPv4.isValidAddress(value) { mask = value }
                continue
            }
            if let value = value(after: "Router:", in: line) {
                if IPv4.isValidAddress(value) { gateway = value }
                continue
            }
        }
        return ServiceConfig(mode: mode, ip: ip, mask: mask, gateway: gateway)
    }

    /// 读取某个服务上配置的 DNS。没有配置时 networksetup 会输出一句英文提示，被自然过滤掉。
    static func readDNS(_ serviceName: String) -> [String] {
        guard let result = try? Shell.run(Shell.networksetupPath, ["-getdnsservers", serviceName]) else {
            return []
        }
        guard result.succeeded else { return [] }

        var servers: [String] = []
        for rawLine in result.standardOutput.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if IPv4.isValidAddress(line) {
                servers.append(line)
            }
        }
        return servers
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
