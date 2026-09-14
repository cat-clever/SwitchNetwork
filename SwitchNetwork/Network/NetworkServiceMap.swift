import Foundation

/// 系统里的一个"网络服务"。networksetup 的所有读写命令用的都是这个 name，
/// 而不是 BSD 设备名，两者并不总是一致（例如服务名"外接网卡"对应 en11）。
struct NetworkService: Equatable {
    let name: String
    let hardwarePort: String
    let device: String
    let isEnabled: Bool
}

/// 服务顺序里的一项。顺序本身就是系统判定主链路的依据。
struct ServiceOrderEntry: Identifiable, Equatable {
    let name: String
    let device: String
    let isEnabled: Bool

    var id: String { return name }
}

enum NetworkServiceMap {

    static func load() -> [NetworkService] {
        guard let text = fetchOrderText() else { return [] }
        return parse(text)
    }

    /// 取出 -listnetworkserviceorder 的原始输出，失败时记日志并返回 nil。
    private static func fetchOrderText() -> String? {
        guard let result = try? Shell.run(Shell.networksetupPath, ["-listnetworkserviceorder"]) else {
            Log.shared.error(L.t("执行 networksetup -listnetworkserviceorder 失败"))
            return nil
        }
        guard result.succeeded else {
            Log.shared.error(L.t("读取网络服务列表失败：%@", result.combinedMessage))
            return nil
        }
        return result.standardOutput
    }

    /// 按系统优先级排列的服务名（第一位优先级最高）。
    ///
    /// 单独解析一遍、而不是复用 `parse` 的结果：`parse` 只保留带 Device 的服务，
    /// 而 `-ordernetworkservices` 要求把所有服务都列全，少一个就会整体失败。
    static func loadNames() -> [String] {
        guard let text = fetchOrderText() else { return [] }
        return parseNames(text)
    }

    /// 服务顺序，附带设备名和启用状态，供界面显示。
    static func loadOrder() -> [ServiceOrderEntry] {
        guard let text = fetchOrderText() else { return [] }
        let details = parse(text)
        return parseNames(text).map { name -> ServiceOrderEntry in
            // 名字是从服务名那行单独刮出来的，可能对不上只保留带 Device 服务的 parse 结果，
            // 这时就当它没有设备信息，不影响排序。
            guard let detail = details.first(where: { $0.name == name }) else {
                return ServiceOrderEntry(name: name, device: "", isEnabled: true)
            }
            return ServiceOrderEntry(name: name, device: detail.device, isEnabled: detail.isEnabled)
        }
    }

    /// 解析形如下面的输出：
    /// ```
    /// (1) Ethernet
    /// (Hardware Port: Ethernet, Device: en0)
    ///
    /// (2) 外接网卡
    /// (Hardware Port: USB 10/100/1000 LAN, Device: en11)
    /// ```
    /// 被禁用的服务，服务名那一行的序号会被替换成 `*`。
    static func parse(_ text: String) -> [NetworkService] {
        var services: [NetworkService] = []
        var pendingName: String?
        var pendingEnabled = true

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("(Hardware Port: "), line.hasSuffix(")") {
                let body = String(line.dropFirst("(Hardware Port: ".count).dropLast())
                var hardwarePort = body
                var device = ""
                if let range = body.range(of: ", Device: ") {
                    hardwarePort = String(body[body.startIndex..<range.lowerBound])
                    device = String(body[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                if !device.isEmpty {
                    let name = pendingName ?? hardwarePort
                    services.append(NetworkService(name: name,
                                                   hardwarePort: hardwarePort,
                                                   device: device,
                                                   isEnabled: pendingEnabled))
                }
                pendingName = nil
                pendingEnabled = true
                continue
            }

            if line.hasPrefix("("), let closing = line.firstIndex(of: ")") {
                let marker = String(line[line.index(after: line.startIndex)..<closing])
                let rest = String(line[line.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
                pendingEnabled = (marker != "*")
                // 旧系统会把禁用服务的名字整段吃掉，此时靠下一行的硬件端口名兜底。
                pendingName = rest.isEmpty ? nil : rest
            }
        }
        return services
    }

    /// 只把服务名刮出来，顺序保持系统给的顺序。
    /// 旧系统上被禁用的服务没有名字（整段被吃掉），这种就跳过——
    /// 名字都读不到的话，也没法把它写进 ordernetworkservices 的参数里。
    static func parseNames(_ text: String) -> [String] {
        var names: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("(Hardware Port: ") { continue }
            guard line.hasPrefix("("), let closing = line.firstIndex(of: ")") else { continue }
            let name = String(line[line.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { names.append(name) }
        }
        return names
    }

    /// 找出某个 BSD 设备对应的网络服务。同一个设备挂了多个服务时优先取启用中的那个。
    static func resolve(device: String, in services: [NetworkService]) -> NetworkService? {
        var matched: NetworkService?
        for service in services {
            if service.device != device { continue }
            if service.isEnabled { return service }
            if matched == nil { matched = service }
        }
        return matched
    }

    static func duplicates(of device: String, in services: [NetworkService]) -> [NetworkService] {
        return services.filter { $0.device == device }
    }
}
