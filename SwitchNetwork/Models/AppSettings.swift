import Foundation

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .system: return L.t("跟随系统")
        case .light: return L.t("浅色")
        case .dark: return L.t("深色")
        }
    }
}

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool
    var showInDock: Bool
    var appearance: AppearanceMode
    /// 界面语言。默认跟随系统。
    var language: LanguageMode
    /// 自动应用的全局开关。关掉后即使接口连上也不会自动写入配置。
    var autoApplyEnabled: Bool
    /// 接口状态抖动防抖时长（秒）。网络协商期间状态会反复跳变，等稳定后再判定。
    var debounceSeconds: Double
    /// 启动时对已连接接口做一次"当前配置是否等于自动配置"的校正。
    var reconcileOnLaunch: Bool
    /// 期望的网络服务顺序（服务名按优先级从高到低）。
    /// 空数组表示还没设过，此时界面直接显示系统当前顺序。
    var serviceOrder: [String]
    /// 删除的配置在回收站里留多少天，超期才彻底删除。
    var trashRetentionDays: Int
    /// 已经问过「要不要把本机已有的配置导入 iCloud」。
    var didOfferICloudMigration: Bool

    init(launchAtLogin: Bool = false,
         showInDock: Bool = false,
         appearance: AppearanceMode = .system,
         language: LanguageMode = .system,
         autoApplyEnabled: Bool = true,
         debounceSeconds: Double = 1.5,
         reconcileOnLaunch: Bool = true,
         serviceOrder: [String] = [],
         trashRetentionDays: Int = 30,
         didOfferICloudMigration: Bool = false) {
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.appearance = appearance
        self.language = language
        self.autoApplyEnabled = autoApplyEnabled
        self.debounceSeconds = debounceSeconds
        self.reconcileOnLaunch = reconcileOnLaunch
        self.serviceOrder = serviceOrder
        self.trashRetentionDays = trashRetentionDays
        self.didOfferICloudMigration = didOfferICloudMigration
    }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, showInDock, appearance, language
        case autoApplyEnabled, debounceSeconds, reconcileOnLaunch, serviceOrder
        case trashRetentionDays, didOfferICloudMigration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = container.value(.launchAtLogin, default: false)
        showInDock = container.value(.showInDock, default: false)
        appearance = container.value(.appearance, default: .system)
        language = container.value(.language, default: .system)
        autoApplyEnabled = container.value(.autoApplyEnabled, default: true)
        let debounce = container.value(.debounceSeconds, default: 1.5)
        debounceSeconds = min(max(debounce, 0.5), 10)
        reconcileOnLaunch = container.value(.reconcileOnLaunch, default: true)
        serviceOrder = container.value(.serviceOrder, default: [])
        // 下限 1 天：0 会让回收站失去意义，用户想立刻清空可以在回收站里手动删。
        let retention = container.value(.trashRetentionDays, default: 30)
        trashRetentionDays = min(max(retention, 1), 365)
        didOfferICloudMigration = container.value(.didOfferICloudMigration, default: false)
    }
}
