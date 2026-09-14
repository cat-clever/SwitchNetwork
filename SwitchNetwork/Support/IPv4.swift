import Foundation

/// IPv4 地址、子网掩码、CIDR 前缀之间的解析与换算。
enum IPv4 {

    // MARK: - 解析

    /// 把 "192.168.1.1" 解析为 UInt32。非法输入返回 nil。
    static func addressToUInt32(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard part.count >= 1, part.count <= 3 else { return nil }
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        return value
    }

    static func string(from value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

    // MARK: - 校验

    static func isValidAddress(_ text: String) -> Bool {
        return addressToUInt32(text) != nil
    }

    /// 合法掩码必须是连续的 1 后接连续的 0，且不能全 0。
    static func isValidMask(_ text: String) -> Bool {
        guard let prefix = maskToPrefix(text) else { return false }
        return prefix >= 1
    }

    static func isValidGateway(_ text: String) -> Bool {
        if text.isEmpty { return true }
        return isValidAddress(text)
    }

    // MARK: - 掩码 / 前缀 互转

    static func maskToPrefix(_ mask: String) -> Int? {
        guard let value = addressToUInt32(mask) else { return nil }
        var prefix = 0
        var sawZero = false
        var bit: UInt32 = 0x8000_0000
        for _ in 0..<32 {
            if value & bit != 0 {
                if sawZero { return nil }
                prefix += 1
            } else {
                sawZero = true
            }
            bit >>= 1
        }
        return prefix
    }

    static func prefixToMask(_ prefix: Int) -> String {
        let clamped = min(max(prefix, 0), 32)
        if clamped == 0 { return "0.0.0.0" }
        let value: UInt32 = ~UInt32(0) << (32 - clamped)
        return string(from: value)
    }

    /// "10.0.0.5" + "255.255.255.0" -> "10.0.0.0"
    static func networkAddress(destination: String, mask: String) -> String? {
        guard let address = addressToUInt32(destination) else { return nil }
        guard let maskValue = addressToUInt32(mask) else { return nil }
        return string(from: address & maskValue)
    }

    /// 判断某个地址是否落在指定网段内。
    static func contains(address: String, networkAddress: String, mask: String) -> Bool {
        guard let addressValue = addressToUInt32(address) else { return false }
        guard let networkValue = addressToUInt32(networkAddress) else { return false }
        guard let maskValue = addressToUInt32(mask) else { return false }
        return (addressValue & maskValue) == (networkValue & maskValue)
    }
}
