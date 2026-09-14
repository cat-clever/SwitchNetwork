import Foundation

/// 界面语言。默认跟随系统。
enum LanguageMode: String, Codable, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { return rawValue }

    /// 语言名按惯例用该语言自己的写法，只有"跟随系统"跟着界面语言走。
    var displayName: String {
        switch self {
        case .system: return L.t("跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
}

/// 当前生效的界面语言。
///
/// 文案的做法是「拿中文原文当 key 去查译文表」：
/// - 漏翻只会回落到中文，界面不会出现奇怪的 key，也不会崩；
/// - 加一门语言只要再写一张表。
///
/// 这里刻意不做成 ObservableObject：语言是在 AppSettings 的 didSet 里应用的，
/// 如果在视图更新过程中再发布一个可观察对象，SwiftUI 可能吞掉这次更新。
/// 界面重绘由 AppState.settings 的发布驱动，见 MainWindowView 的 .id(resolvedLanguage)。
final class Localization {

    static let shared = Localization()

    /// 生效的语言代码，例如 "zh-Hans" / "en"。
    private(set) var activeCode: String = "zh-Hans"

    private var table: [String: String] = [:]

    private init() {
        buildTable()
    }

    // MARK: - 语言

    func apply(_ mode: LanguageMode) {
        let resolved = Localization.resolve(mode)
        if resolved != activeCode {
            activeCode = resolved
        }
    }

    /// 跟随系统时只区分中英：系统首选语言里第一个中文用中文，第一个英文用英文。
    static func resolve(_ mode: LanguageMode) -> String {
        switch mode {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        case .system:
            for preferred in Locale.preferredLanguages {
                let lowered = preferred.lowercased()
                if lowered.hasPrefix("zh") { return "zh-Hans" }
                if lowered.hasPrefix("en") { return "en" }
            }
            return "en"
        }
    }

    // MARK: - 取词

    /// 查不到就返回中文原文。
    func translate(_ chinese: String) -> String {
        if activeCode == "zh-Hans" { return chinese }
        if let value = table[chinese] { return value }
        return chinese
    }

    private func buildTable() {
        var merged: [String: String] = [:]
        for part in Localization.parts {
            for (key, value) in part {
                merged[key] = value
            }
        }
        table = merged
    }

    /// 各分组分别写在 Strings*.swift 里，这里汇总。
    private static var parts: [[String: String]] {
        return [englishStringsProfiles,
                englishStringsSettings,
                englishStringsOverview,
                englishStringsModels,
                englishStringsNetwork,
                englishStringsRoutes,
                englishStringsUpdate,
                englishStringsApp]
    }
}

/// 取当前语言的文案。
///
/// 用法：
/// ```
/// Text(L.t("网卡配置"))
/// Text(L.t("已删除配置 %@", profile.name))
/// Text(L.t("还有 %d 项需要修正", count))
/// ```
enum L {
    /// 中文原文当 key。带参数时用 %@ / %d 占位，不要直接拼字符串，
    /// 否则译文里没法调整语序。
    static func t(_ chinese: String, _ arguments: CVarArg...) -> String {
        let template = Localization.shared.translate(chinese)
        if arguments.isEmpty { return template }
        return String(format: template, arguments)
    }

    /// 列举分隔符。中文习惯用全角，英文用半角加空格，
    /// 否则英文界面里会出现「A；B」这种别扭的标点。
    static var listSeparator: String {
        return Localization.shared.activeCode == "zh-Hans" ? "；" : "; "
    }

    static var commaSeparator: String {
        return Localization.shared.activeCode == "zh-Hans" ? "，" : ", "
    }
}
