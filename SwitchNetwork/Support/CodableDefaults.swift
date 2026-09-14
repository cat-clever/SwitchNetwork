import Foundation

extension KeyedDecodingContainer {

    /// 宽容解码：字段缺失或为 null 时回落到默认值。
    /// 配置文件是长期存在的 JSON，加字段/删字段都不应该让用户丢掉整份配置。
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        if let decoded = try? decodeIfPresent(T.self, forKey: key) {
            return decoded
        }
        return fallback
    }

    /// 可选字段：缺失、为 null、或类型不符时统一返回 nil。
    func optionalValue<T: Decodable>(_ key: Key) -> T? {
        if let decoded = try? decodeIfPresent(T.self, forKey: key) {
            return decoded
        }
        return nil
    }
}
