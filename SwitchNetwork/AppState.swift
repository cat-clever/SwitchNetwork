import Foundation
import Combine
import AppKit

/// 全局应用状态：网卡配置、接口快照、设置、自动应用协调。
final class AppState: ObservableObject {

    static let shared = AppState()

    private static let profilesFile = "profiles.json"
    private static let trashFile = "trash.json"
    private static let settingsFile = "settings.json"

    /// 问用户要不要把本机已有的配置导入 iCloud。
    struct MigrationPrompt: Identifiable {
        let id = UUID()
        /// 本机旧目录里有几份配置。
        let count: Int
        /// 本机旧目录的位置，界面上显示出来让用户知道从哪导。
        let sourcePath: String
    }

    enum HealthState {
        /// 有自动配置的接口都已经按预期生效。
        case normal
        /// 有接口已连接、却没按自动配置生效。
        case attention
        /// 一个自动配置都没有。
        case unconfigured
    }

    @Published private(set) var profiles: [Profile] = []
    /// 回收站。删除的配置先到这里，过了保留期才真的消失。
    @Published private(set) var trash: [TrashedProfile] = []
    @Published private(set) var interfaces: [InterfaceStatus] = []
    @Published private(set) var privilegeGranted: Bool = false
    @Published private(set) var activeApplyCount: Int = 0
    @Published private(set) var lastReports: [String: ApplyReport] = [:]
    @Published private(set) var loginItemState: LoginItemState = .disabled
    /// 系统当前的服务顺序（优先级从高到低）。
    @Published private(set) var serviceOrder: [ServiceOrderEntry] = []
    /// 正在弹密码框安装免密授权。
    @Published private(set) var isInstallingPrivilege = false
    /// 配置文件读不出来时的说明（云端还没下载完之类）。非 nil 表示本次运行暂停写入。
    @Published private(set) var storageWarning: String?
    /// 非 nil 时界面弹一次「要不要把本机配置导入 iCloud」。
    @Published var pendingMigration: MigrationPrompt?
    /// 启动时静默查到的新版本。只在真的查到更新的版本时才有值。
    @Published private(set) var availableUpdate: UpdateInfo?
    /// 上次查到结果的时间，设置页显示用。
    @Published private(set) var lastUpdateCheck: Date?

    /// 系统当前路由表（只读快照，仅 IPv4）。
    @Published private(set) var systemRoutes: [RouteEntry] = []
    /// 正在读路由表。读不跟写抢，所以不占 routeOperationCount——
    /// 进页面只是读一次，按钮不该显示成「正在写入」。
    @Published private(set) var isLoadingRoutes = false
    /// 读路由表失败过。要跟「还没读」区分开：macOS 的路由表不可能是空的
    /// （至少有 lo0 和接口直连），所以拿到空结果只可能是读失败，
    /// 直接按空表显示会让用户以为路由全被删了。
    @Published private(set) var routeLoadFailed = false
    /// 正在往路由表里写（增删改）。单独计数，不复用 activeApplyCount——
    /// 那个被「网络服务优先级」的按钮拿来禁用了，混在一起会让它莫名变灰。
    @Published private(set) var routeOperationCount = 0
    /// 页面顶部那条提示。删除/还原/新增的结果都写这里，过一会儿自动消失。
    /// 需要长期留着的是 deletedRoutes，不是它。
    @Published private(set) var routeBanner: RouteBanner?
    /// 本次运行删掉的路由，供「本次删除」列表还原。仅内存，重启即消失。
    @Published private(set) var deletedRoutes: [DeletedRoute] = []

    /// 顶部提示条。
    struct RouteBanner: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
        /// 非 nil 时提示条上给一个「撤回」按钮，指向 deletedRoutes 里的那一条。
        let undoID: UUID?
    }

    @Published var settings: AppSettings = AppSettings() {
        didSet {
            if settings != oldValue {
                settingsDidChange(from: oldValue)
            }
        }
    }

    let monitor = InterfaceMonitor()

    /// 编辑器保存完一份配置后发出，携带配置的 id。
    /// 界面上对应的那张卡片收到后重新检查静态路由，让用户马上看到"到没到系统里"。
    let profileSaved = PassthroughSubject<UUID, Never>()

    private let applyQueue = DispatchQueue(label: "com.CleverCat.SwitchNetwork.apply")
    private var isUpdatingLoginItem = false
    private var hasStarted = false
    /// 云端文件还没下载完时重试读了几次。
    private var cloudRetryCount = 0
    /// 顶部提示条的引线，不是状态。下一次提示会把它掐掉重新计时。
    private var routeBannerTimer: DispatchWorkItem?

    /// 顶部提示条挂多久。够看清一句话，又不至于一直占着屏幕顶部。
    private static let routeBannerSeconds: Double = 12

    var isApplying: Bool {
        return activeApplyCount > 0
    }

    /// 路由表页的忙碌态。和 isApplying 分开，见 routeOperationCount 的说明。
    var isRouteBusy: Bool {
        return routeOperationCount > 0
    }

    /// 算出生效的语言代码（"跟随系统"在这里被解析成具体的 zh-Hans / en）。
    /// 主窗口拿它做 `.id()`：值一变，下面整棵内容树重建，所有 L.t 重新取词。
    /// 之所以挂在 AppState 上而不是让 Localization 自己发布，
    /// 是因为语言是在 settings 的 didSet 里应用的，视图更新过程中再发布另一个
    /// 可观察对象会被 SwiftUI 吞掉；走 settings 的发布会顺带把这次重绘带上。
    var resolvedLanguage: String {
        return Localization.resolve(settings.language)
    }

    private init() {
        settings = JSONStore.load(AppSettings.self, from: Self.settingsFile, scope: .local).value ?? AppSettings()
        loginItemState = SystemCompat.loginItemState()
        // 界面还没建起来之前先把语言定下来，免得首屏闪一下中文。
        Localization.shared.apply(settings.language)
        loadSyncedData()
        offerMigrationIfNeeded()
    }

    // MARK: - 落盘数据的读写

    /// 读配置和回收站。两个文件都在同步范围内，一起读、一起判断能不能写。
    ///
    /// 读不出来（iCloud 还没把文件下载下来）时不拿默认值顶上去，而是挂上只读闸、
    /// 过一秒再试，直到读到或超时——否则会用空数组覆盖掉云端的真配置。
    private func loadSyncedData() {
        var pendingReason: String?

        switch JSONStore.load([Profile].self, from: Self.profilesFile, scope: .synced) {
        case .loaded(let list):
            profiles = list
        case .missing, .corrupt:
            profiles = []
        case .unreadable(let reason):
            pendingReason = reason
        }

        switch JSONStore.load([TrashedProfile].self, from: Self.trashFile, scope: .synced) {
        case .loaded(let list):
            trash = list
        case .missing, .corrupt:
            trash = []
        case .unreadable(let reason):
            if pendingReason == nil { pendingReason = reason }
        }

        guard let reason = pendingReason else {
            if storageWarning != nil {
                Log.shared.success(L.t("云端配置已经下载完，恢复写入"))
            }
            storageWarning = nil
            cloudRetryCount = 0
            JSONStore.unfreeze()
            purgeExpiredTrash()
            return
        }

        storageWarning = reason
        Log.shared.error(L.t("暂时不能写入配置：%@", reason))
        scheduleCloudRetry()
    }

    /// 界面上的「重试」：把重试计数清零再读一次同步范围的数据。
    func retryCloudLoad() {
        cloudRetryCount = 0
        loadSyncedData()
    }

    /// 云端文件没下载完时，每秒重试一次，最多 30 次。
    private func scheduleCloudRetry() {
        guard cloudRetryCount < 30 else {
            Log.shared.error(L.t("等了 30 秒还没等到云端文件，本次运行不再重试；网络恢复后重开应用即可"))
            return
        }
        cloudRetryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let state = self else { return }
            state.loadSyncedData()
        }
    }

    private func persistProfiles() {
        JSONStore.save(profiles, to: Self.profilesFile, scope: .synced)
    }

    private func persistTrash() {
        JSONStore.save(trash, to: Self.trashFile, scope: .synced)
    }

    /// 配置和回收站存在哪，给设置页显示。
    var storageLocationLabel: String {
        return JSONStore.isUsingCloud ? L.t("iCloud Drive（多台 Mac 自动同步）") : L.t("本机（这台机器没开 iCloud）")
    }

    var storageLocationPath: String {
        return JSONStore.directory(for: .synced).path
    }

    // MARK: - 生命周期

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // 用户可能在系统设置里改过登录项，以系统状态为准。
        let actualLoginItem = SystemCompat.loginItemState()
        loginItemState = actualLoginItem
        if settings.launchAtLogin != actualLoginItem.isOn {
            settings.launchAtLogin = actualLoginItem.isOn
        }

        AppearanceManager.apply(settings.appearance)
        Localization.shared.apply(settings.language)
        applyActivationPolicy()
        monitor.updateDebounce(settings.debounceSeconds)

        monitor.onStatusUpdate = { [weak self] statuses in
            guard let state = self else { return }
            state.interfaces = statuses
        }
        monitor.onConnectivityChange = { [weak self] changes, statuses in
            guard let state = self else { return }
            state.handleConnectivityChange(changes, statuses: statuses)
        }
        monitor.start()

        refreshPrivilegeStatus()
        refreshServiceOrder()
        scheduleLaunchReconcile()
        checkForUpdatesQuietly()
    }

    // MARK: - 检查更新

    /// 手动查到的结果也记回来，免得「启动时提示有新版本」和「刚手动查过」
    /// 两处显示对不上。查不到新版本就把旧的清掉。
    func recordUpdateCheck(available: UpdateInfo?) {
        lastUpdateCheck = Date()
        availableUpdate = available
    }

    /// 启动后延时静默查一次：有新版本才记下来，失败什么都不做。
    /// 这是唯一会联网的功能，所以故意做得不打扰——查不到就当没这回事。
    private func checkForUpdatesQuietly() {
        // 晚一点再查：启动头几秒在忙接口刷新，别同时挤一个网络请求。
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let state = self else { return }
            UpdateChecker.shared.check { outcome in
                switch outcome {
                case .available(let info):
                    state.recordUpdateCheck(available: info)
                    Log.shared.info(L.t("发现新版本 %@，可在「设置 → 更新」里安装", info.version))
                case .noDownloadableAsset(let info):
                    state.recordUpdateCheck(available: info)
                    Log.shared.info(L.t("发现新版本 %@，但这个版本没有 dmg 附件", info.version))
                case .upToDate:
                    state.recordUpdateCheck(available: nil)
                case .failed(let message):
                    Log.shared.warning(L.t("启动检查更新失败：%@", message))
                }
            }
        }
    }

    func applyActivationPolicy() {
        if settings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func settingsDidChange(from oldValue: AppSettings) {
        // 设置在同步范围之外：里面有开机启动、服务顺序这类跟本机绑定的项。
        JSONStore.save(settings, to: Self.settingsFile, scope: .local)
        if settings.trashRetentionDays != oldValue.trashRetentionDays {
            purgeExpiredTrash()
        }
        if settings.appearance != oldValue.appearance {
            AppearanceManager.apply(settings.appearance)
        }
        if settings.language != oldValue.language {
            Localization.shared.apply(settings.language)
        }
        if settings.debounceSeconds != oldValue.debounceSeconds {
            monitor.updateDebounce(settings.debounceSeconds)
        }
        if settings.showInDock != oldValue.showInDock {
            applyActivationPolicy()
        }
        if settings.launchAtLogin != oldValue.launchAtLogin {
            updateLoginItem(enabled: settings.launchAtLogin)
        }
    }

    private func updateLoginItem(enabled: Bool) {
        guard !isUpdatingLoginItem else { return }
        isUpdatingLoginItem = true
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                try SystemCompat.setLoginItem(enabled: enabled)
            } catch {
                failure = error.localizedDescription
            }
            let state = SystemCompat.loginItemState()
            DispatchQueue.main.async {
                self.loginItemState = state
                self.isUpdatingLoginItem = false
                if let message = failure {
                    Log.shared.error(L.t("设置开机启动失败：%@", message))
                    // 把开关拨回系统的真实状态，不要让 UI 骗人。
                    self.isUpdatingLoginItem = true
                    self.settings.launchAtLogin = state.isOn
                    self.isUpdatingLoginItem = false
                } else if enabled {
                    Log.shared.success(L.t("已开启开机启动"))
                } else {
                    Log.shared.info(L.t("已关闭开机启动"))
                }
            }
        }
    }

    // MARK: - 权限

    func refreshPrivilegeStatus() {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = PrivilegeManager.probe()
            DispatchQueue.main.async {
                self.privilegeGranted = granted
            }
        }
    }

    /// 点「一键安装授权」后的流程：弹系统密码框 → 写 sudoers → 重新探测。
    func installPrivilegeAuthorization() {
        guard !isInstallingPrivilege else { return }
        isInstallingPrivilege = true
        Log.shared.info(L.t("正在申请管理员授权以安装免密配置"))
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = PrivilegeManager.installWithAuthorization()
            let granted = PrivilegeManager.probe()
            DispatchQueue.main.async {
                self.isInstallingPrivilege = false
                self.privilegeGranted = granted
                switch outcome {
                case .installed:
                    Log.shared.success(L.t("免密授权已安装：%@", PrivilegeManager.sudoersPath))
                case .cancelled:
                    Log.shared.warning(L.t("已取消安装免密授权"))
                case .failed(let message):
                    Log.shared.error(L.t("安装免密授权失败：%@", message))
                }
            }
        }
    }

    // MARK: - 网卡配置

    func profile(withID id: UUID) -> Profile? {
        for profile in profiles where profile.id == id {
            return profile
        }
        return nil
    }

    func profiles(for interfaceIdentifier: String) -> [Profile] {
        return profiles.filter { $0.interfaceIdentifier == interfaceIdentifier }
    }

    func autoProfile(for interfaceIdentifier: String) -> Profile? {
        for profile in profiles
        where profile.interfaceIdentifier == interfaceIdentifier && profile.autoApplyOnConnect {
            return profile
        }
        return nil
    }

    /// 保存（新增或更新）。同一接口下「自动应用」互斥，由这里统一保证。
    /// - Parameter checkRoutesAfterSave: 用户在编辑器里点保存时传 true：
    ///   立刻刷新一次接口状态，并通知界面重新检查静态路由是否已生效。
    @discardableResult
    func save(_ profile: Profile, checkRoutesAfterSave: Bool = false) -> Profile {
        // 只读期间不写：内存里改了、磁盘上没落，界面会显示一份其实不存在的配置。
        guard !JSONStore.isFrozen else {
            Log.shared.error(L.t("暂时不能写入配置，保存已取消：%@", storageWarning ?? ""))
            return profile
        }
        var updated = profile
        updated.updatedAt = Date()
        if updated.autoApplyOnConnect {
            for index in profiles.indices
            where profiles[index].interfaceIdentifier == updated.interfaceIdentifier
                && profiles[index].id != updated.id {
                profiles[index].autoApplyOnConnect = false
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        } else {
            profiles.append(updated)
        }
        persistProfiles()

        if checkRoutesAfterSave {
            monitor.refresh()
            profileSaved.send(updated.id)
        }
        return updated
    }

    /// 删除 = 移进回收站，过了保留期才真的从磁盘上消失。
    func delete(profileID: UUID) {
        guard let target = profile(withID: profileID) else { return }
        guard !JSONStore.isFrozen else {
            Log.shared.error(L.t("暂时不能写入配置，删除已取消：%@", storageWarning ?? ""))
            return
        }
        // 先写回收站再改配置列表：中间万一出错，多留一份比少一份安全。
        trash.insert(TrashedProfile(profile: target), at: 0)
        persistTrash()
        profiles.removeAll { $0.id == profileID }
        persistProfiles()
        Log.shared.info(L.t("已把「%@」移入回收站，%d 天后彻底删除", target.name, settings.trashRetentionDays))
    }

    // MARK: - 回收站

    func restoreFromTrash(id: UUID) {
        guard let index = trash.firstIndex(where: { $0.id == id }) else { return }
        var restored = trash[index].profile
        trash.remove(at: index)
        // 同一个接口只能有一份自动配置。位置被占了就退让，
        // 不去静默抢掉用户后来设的那一份。
        if restored.autoApplyOnConnect, let occupied = autoProfile(for: restored.interfaceIdentifier) {
            restored.autoApplyOnConnect = false
            Log.shared.warning(L.t("接口 %@ 上已经有自动应用的「%@」，还原的这份不自动应用",
                                   restored.interfaceIdentifier, occupied.name))
        }
        persistTrash()
        save(restored)
        Log.shared.success(L.t("已还原配置「%@」", restored.name))
    }

    func purgeFromTrash(id: UUID) {
        guard let item = trash.first(where: { $0.id == id }) else { return }
        trash.removeAll { $0.id == id }
        persistTrash()
        Log.shared.info(L.t("已彻底删除「%@」", item.profile.name))
    }

    func emptyTrash() {
        guard !trash.isEmpty else { return }
        let count = trash.count
        trash.removeAll()
        persistTrash()
        Log.shared.info(L.t("已清空回收站，彻底删除 %d 份配置", count))
    }

    /// 清掉超过保留期的。启动时、打开回收站时、改保留天数时各跑一次。
    /// 只读模式下跳过：那会儿回收站的内容都还没读进来，清一遍等于误删。
    func purgeExpiredTrash() {
        guard !JSONStore.isFrozen else { return }
        let days = settings.trashRetentionDays
        let kept = trash.filter { $0.remainingDays(retentionDays: days) > 0 }
        let removed = trash.count - kept.count
        guard removed > 0 else { return }
        trash = kept
        persistTrash()
        Log.shared.info(L.t("回收站里有 %d 份配置超过 %d 天，已彻底删除", removed, days))
    }

    // MARK: - 从本机旧目录搬到 iCloud

    /// 本机旧目录里有配置、iCloud 里还没有的时候问一次。
    /// 只问不搬：用户点了才导入，本机那份始终留着当备份。
    private func offerMigrationIfNeeded() {
        guard JSONStore.isUsingCloud, !settings.didOfferICloudMigration, !JSONStore.isFrozen else { return }
        let count = (JSONStore.load([Profile].self, from: Self.profilesFile, scope: .local).value ?? []).count
        // iCloud 里已经有配置就不用问；本机也没有就没什么可导入的。
        guard count > 0, profiles.isEmpty else { return }
        pendingMigration = MigrationPrompt(count: count,
                                           sourcePath: JSONStore.directory(for: .local).path)
    }

    func importLocalProfilesToCloud() {
        guard let list = JSONStore.load([Profile].self, from: Self.profilesFile, scope: .local).value,
              !list.isEmpty else {
            pendingMigration = nil
            return
        }
        profiles = list
        persistProfiles()
        pendingMigration = nil
        // 本机那份不动：既是备份，也是这次导入万一出问题时的退路。
        Log.shared.success(L.t("已把本机的 %d 份配置导入 iCloud，本机那份保留作备份", list.count))
    }

    /// 「先不导入」，之后不再问。想导入时本机文件还在，随时可以手工拷过去。
    func declineMigration() {
        settings.didOfferICloudMigration = true
        pendingMigration = nil
    }

    /// 克隆一份并自动生成不重名的名称。克隆出来的默认不自动应用，避免立刻触发互斥。
    @discardableResult
    func clone(profileID: UUID) -> Profile? {
        guard let original = profile(withID: profileID) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = uniqueName(base: L.t("%@ 副本", original.name), for: original.interfaceIdentifier)
        copy.autoApplyOnConnect = false
        copy.routes = original.routes.map { route in
            var duplicated = route
            duplicated.id = UUID()
            return duplicated
        }
        copy.createdAt = Date()
        copy.updatedAt = Date()
        profiles.append(copy)
        persistProfiles()
        Log.shared.info(L.t("已克隆 %@ → %@", original.name, copy.name))
        return copy
    }

    func setAutoApply(profileID: UUID, enabled: Bool) {
        guard let target = profile(withID: profileID) else { return }
        var updated = target
        updated.autoApplyOnConnect = enabled
        let saved = save(updated)

        // 打开开关时如果接口已经连着、且当前配置不符，立刻应用一次，
        // 否则用户会以为开关没生效。
        guard enabled, settings.autoApplyEnabled, privilegeGranted else { return }
        guard let status = interfaceStatus(for: saved.interfaceIdentifier) else { return }
        guard status.isConnected, !status.matches(saved) else { return }
        performApply(profile: saved, status: status, requireConnected: true)
    }

    /// 哪个已保存的配置正在这个接口上生效。判定条件见 InterfaceStatus.matches(_:)：
    /// 地址获取方式、IP/掩码/网关、DNS 都要对得上。
    func currentProfile(for status: InterfaceStatus) -> Profile? {
        let candidates = profiles(for: status.identifier)
        for profile in candidates where status.matches(profile) {
            return profile
        }
        return nil
    }

    func interfaceStatus(for identifier: String) -> InterfaceStatus? {
        for status in interfaces where status.identifier == identifier {
            return status
        }
        return nil
    }

    /// 界面上"按接口分组"的数据源，顺序跟着接口列表走。
    func profilesGroupedByInterface() -> [(status: InterfaceStatus, profiles: [Profile])] {
        var groups: [(status: InterfaceStatus, profiles: [Profile])] = []
        for status in interfaces {
            let owned = profiles(for: status.identifier)
            if owned.isEmpty && !status.isConfigurable { continue }
            groups.append((status, owned))
        }
        // 有配置但接口已经不在了（比如 USB 网卡被拔走），单独补一组，避免配置"消失"。
        let known = Set(interfaces.map { $0.identifier })
        var orphans: [String: [Profile]] = [:]
        for profile in profiles where !known.contains(profile.interfaceIdentifier) {
            orphans[profile.interfaceIdentifier, default: []].append(profile)
        }
        for (identifier, owned) in orphans.sorted(by: { $0.key < $1.key }) {
            var name = identifier
            if let first = owned.first {
                name = first.interfaceDisplayName
            }
            let placeholder = InterfaceStatus(identifier: identifier,
                                             displayName: name.isEmpty ? identifier : name,
                                             serviceName: nil,
                                             type: .other,
                                             isConnected: false,
                                             currentIP: nil,
                                             currentMask: nil,
                                             currentGateway: nil,
                                             currentDNS: [],
                                             configurationMode: .unknown,
                                             ssid: nil)
            groups.append((placeholder, owned))
        }
        return groups
    }

    var healthState: HealthState {
        var hasAutoProfile = false
        var needsAttention = false
        for status in interfaces {
            guard let target = autoProfile(for: status.identifier) else { continue }
            hasAutoProfile = true
            guard status.isConnected else { continue }
            if !privilegeGranted || !status.matches(target) || needsServicePromotion(target) {
                needsAttention = true
            }
        }
        if !hasAutoProfile { return .unconfigured }
        return needsAttention ? .attention : .normal
    }

    // MARK: - 应用配置

    func apply(profileID: UUID, requireConnected: Bool) {
        guard let target = profile(withID: profileID) else { return }
        guard let status = interfaceStatus(for: target.interfaceIdentifier) else {
            Log.shared.error(L.t("找不到接口 %@，无法应用 %@", target.interfaceIdentifier, target.name))
            return
        }
        performApply(profile: target, status: status, requireConnected: requireConnected)
    }

    func apply(profile: Profile, to status: InterfaceStatus, requireConnected: Bool) {
        performApply(profile: profile, status: status, requireConnected: requireConnected)
    }

    /// 「不使用配置」：把这个接口交还系统。
    func restoreToSystem(identifier: String) {
        guard let status = interfaceStatus(for: identifier) else {
            Log.shared.error(L.t("找不到接口 %@，无法交还系统", identifier))
            return
        }
        let owned = profiles(for: identifier)

        // 不关掉自动应用的话，下一次插拔或者「立即校正」就会把刚撤掉的配置又写回来，
        // 用户看到的就成了"点了没用"。
        for profile in owned where profile.autoApplyOnConnect {
            setAutoApply(profileID: profile.id, enabled: false)
            Log.shared.info(L.t("已关闭「%@」的自动应用，否则下次连接会再写回来", profile.name))
        }

        // 用该接口所有配置里的路由并集：本应用是唯一的路由写入方，
        // 多删一条不存在的路由是安全的，漏掉一条就会留下黑洞。
        var routes: [Route] = []
        for profile in owned {
            for route in profile.routes where !routes.contains(route) {
                routes.append(route)
            }
        }

        activeApplyCount += 1
        Log.shared.info(L.t("开始把接口 %@ 交还系统", identifier))
        applyQueue.async {
            let report = NetworkConfigurator.restoreToSystem(for: status, routes: routes)
            DispatchQueue.main.async {
                self.activeApplyCount = max(0, self.activeApplyCount - 1)
                self.lastReports[identifier] = report
                if report.hasFailure {
                    for message in report.failureMessages {
                        Log.shared.error(message)
                    }
                } else {
                    Log.shared.success(report.summary)
                }
                self.monitor.refresh()
            }
        }
    }

    func refreshAll() {
        monitor.refresh()
        refreshServiceOrder()
    }

    // MARK: - 路由表

    /// 重新读一遍系统路由表。进页面、手动刷新、每次增删改之后都走它。
    func loadRoutes() {
        isLoadingRoutes = true
        applyQueue.async {
            let read = RouteManager.readRoutes()
            DispatchQueue.main.async {
                self.isLoadingRoutes = false
                self.systemRoutes = read.routes
                self.routeLoadFailed = read.failed
            }
        }
    }

    /// 删一条路由。删成了才记进「本次删除」，没删成不记——
    /// 记了会给出一个撤回按钮，点下去却什么也没发生，反而更让人糊涂。
    func deleteRoute(_ entry: RouteEntry) {
        routeOperationCount += 1
        Log.shared.info(L.t("开始删除路由 %@", entry.summary))
        applyQueue.async {
            var outcome = RouteOperationOutcome()
            do {
                let removal = try RouteManager.delete(entry: entry)
                outcome.detail = removal.message
                // 只有真删掉了才进「本次删除」。本来就不在表里的那条，一点撤回反而会把它
                // 加出来——而它是一条系统已经不要了的路由，加回去纯属添乱。
                if removal.removed {
                    outcome.undoItem = DeletedRoute(entry: entry, deletedAt: Date(), restoreFailure: nil)
                }
            } catch {
                outcome.failure = error.localizedDescription
            }
            self.finishRouteOperation(outcome, subject: entry.summary)
        }
    }

    /// 撤回一次删除。
    func restoreRoute(id: UUID) {
        guard let item = deletedRoutes.first(where: { $0.id == id }) else { return }
        routeOperationCount += 1
        Log.shared.info(L.t("开始还原路由 %@", item.entry.summary))
        applyQueue.async {
            var outcome = RouteOperationOutcome()
            outcome.undoID = id
            do {
                outcome.detail = try RouteManager.restore(entry: item.entry)
            } catch {
                outcome.failure = error.localizedDescription
            }
            self.finishRouteOperation(outcome, subject: item.entry.summary)
        }
    }

    /// 加一条临时路由。不进任何配置，也不落盘——重启之后路由表本来就会被系统重建。
    func addRoute(_ route: Route) {
        routeOperationCount += 1
        Log.shared.info(L.t("开始新增路由 %@", route.summary))
        applyQueue.async {
            var outcome = RouteOperationOutcome()
            do {
                outcome.detail = try RouteManager.apply(route)
            } catch {
                outcome.failure = error.localizedDescription
            }
            self.finishRouteOperation(outcome, subject: route.summary)
        }
    }

    /// 改一条路由。
    ///
    /// 不能直接调 `RouteManager.apply`：那个的语义是「同一网段换下一跳」，
    /// 网段本身改了它会在新网段上加一条、旧的那条原地留着。所以先按整行删掉旧的再加新的。
    func updateRoute(_ route: Route, replacing old: RouteEntry) {
        routeOperationCount += 1
        Log.shared.info(L.t("开始修改路由 %@", old.summary))
        applyQueue.async {
            var outcome = RouteOperationOutcome()
            do {
                try RouteManager.delete(entry: old)
                do {
                    outcome.detail = try RouteManager.apply(route)
                } catch {
                    outcome.failure = self.rollBackMessage(error.localizedDescription, entry: old)
                }
            } catch {
                outcome.failure = error.localizedDescription
            }
            self.finishRouteOperation(outcome, subject: old.summary)
        }
    }

    /// 点掉顶部提示条。
    func dismissRouteBanner() {
        cancelRouteBannerTimer()
        routeBanner = nil
    }

    /// 提示条上那个「撤回」按钮的动作。
    func undoDeletionFromBanner() {
        guard let banner = routeBanner else { return }
        guard let id = banner.undoID else { return }
        restoreRoute(id: id)
    }

    /// 这条路由的网段是不是某份配置里写着的，是的话返回配置名。
    ///
    /// 只比网段不比下一跳：配置里只要写着这个网段，下次自动应用就会把这条路由写回来，
    /// 这正是要在界面上提醒用户的事。本应用是唯一按配置写路由的主体，命中基本可以确定是它写的。
    func profileName(owning entry: RouteEntry) -> String? {
        for profile in profiles {
            for route in profile.routes {
                if route.normalizedNetwork == entry.destination && route.subnetMask == entry.mask {
                    return profile.name
                }
            }
        }
        return nil
    }

    /// 一次路由操作的收成。凑成一个结构，四个入口就能共用一个收尾。
    private struct RouteOperationOutcome {
        var detail: String?
        var failure: String?
        /// 删成功后要放进「本次删除」的那一条。
        var undoItem: DeletedRoute?
        /// 还原成功后要从「本次删除」里拿掉的那个 id。
        var undoID: UUID?
    }

    /// 收尾：回主线程更新表格、撤回列表、提示条和日志。
    private func finishRouteOperation(_ outcome: RouteOperationOutcome, subject: String) {
        let read = RouteManager.readRoutes()
        DispatchQueue.main.async {
            self.routeOperationCount = max(0, self.routeOperationCount - 1)
            self.systemRoutes = read.routes
            self.routeLoadFailed = read.failed

            if let item = outcome.undoItem {
                self.deletedRoutes.insert(item, at: 0)
            }
            if let id = outcome.undoID {
                if let message = outcome.failure {
                    // 还原失败就留在列表里让用户重试，原因写在那一行上，不静默吞掉。
                    if let index = self.deletedRoutes.firstIndex(where: { $0.id == id }) {
                        self.deletedRoutes[index].restoreFailure = message
                    }
                } else {
                    self.deletedRoutes.removeAll { $0.id == id }
                }
            }

            if let message = outcome.failure {
                Log.shared.error(L.t("路由操作失败（%@）：%@", subject, message))
                self.showRouteBanner(text: message, isError: true, undoID: nil)
            } else if let detail = outcome.detail {
                Log.shared.success(detail)
                var undoID: UUID?
                if let item = outcome.undoItem {
                    undoID = item.id
                }
                self.showRouteBanner(text: detail, isError: false, undoID: undoID)
            }
        }
    }

    /// 改路由是「先删后加」，加失败时旧的已经没了。这里把它加回去，
    /// 免得用户只是想把一条路由改一下，结果反而把整条路由弄丢。
    private func rollBackMessage(_ reason: String, entry: RouteEntry) -> String {
        do {
            try RouteManager.restore(entry: entry)
            return L.t("%@；已把原来的 %@ 加回去", reason, entry.summary)
        } catch {
            Log.shared.error(L.t("回滚路由 %@ 也失败了：%@", entry.summary, error.localizedDescription))
            return L.t("%@；原来的 %@ 也没能加回去，请到路由表里手动补一条", reason, entry.summary)
        }
    }

    private func showRouteBanner(text: String, isError: Bool, undoID: UUID?) {
        cancelRouteBannerTimer()
        let banner = RouteBanner(text: text, isError: isError, undoID: undoID)
        routeBanner = banner
        let work = DispatchWorkItem { [weak self] in
            guard let state = self else { return }
            // 只清掉自己这一次：后来的提示条已经换了 id，不该被上一条的计时器顺手抹掉。
            guard let current = state.routeBanner else { return }
            if current.id == banner.id {
                state.routeBanner = nil
            }
        }
        routeBannerTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.routeBannerSeconds, execute: work)
    }

    private func cancelRouteBannerTimer() {
        if let timer = routeBannerTimer {
            timer.cancel()
        }
        routeBannerTimer = nil
    }

    // MARK: - 网络服务优先级

    /// 界面里显示、也用来写入系统的顺序：
    /// 以保存的顺序打底（那是用户的意图），系统新增的服务追加到末尾，
    /// 系统里已经没有的服务丢掉。插一次 dock 就多一个服务，不能让顺序整个乱掉。
    var desiredServiceOrder: [ServiceOrderEntry] {
        let saved = settings.serviceOrder
        if saved.isEmpty { return serviceOrder }

        var result: [ServiceOrderEntry] = []
        for name in saved {
            guard let entry = serviceOrder.first(where: { $0.name == name }) else { continue }
            if !result.contains(entry) { result.append(entry) }
        }
        for entry in serviceOrder where !result.contains(entry) {
            result.append(entry)
        }
        return result
    }

    /// 保存过顺序、但系统里现在不是这个顺序（比如刚插上新网卡，或者被系统设置改过）。
    var isServiceOrderOutOfSync: Bool {
        if settings.serviceOrder.isEmpty { return false }
        return settings.serviceOrder != serviceOrder.map { $0.name }
    }

    func refreshServiceOrder() {
        applyQueue.async {
            let order = NetworkServiceMap.loadOrder()
            DispatchQueue.main.async {
                self.serviceOrder = order
            }
        }
    }

    /// 这份配置勾了置顶，但它的服务现在不在第一位。
    /// 服务顺序还没读回来时返回 false——宁可这一轮不校正，也别去乱写。
    func needsServicePromotion(_ profile: Profile) -> Bool {
        guard profile.promoteServiceToTop else { return false }
        guard let status = interfaceStatus(for: profile.interfaceIdentifier) else { return false }
        guard let service = status.serviceName else { return false }
        guard let first = serviceOrder.first else { return false }
        return first.name != service
    }

    /// 把系统当前顺序收为「期望顺序」。
    /// 用在带置顶的配置应用成功之后：顺序是这次刚写进去的，界面不该再提示"与系统不一致"。
    private func adoptSystemServiceOrder() {
        applyQueue.async {
            let order = NetworkServiceMap.loadOrder()
            let names = order.map { $0.name }
            DispatchQueue.main.async {
                self.serviceOrder = order
                if !names.isEmpty { self.settings.serviceOrder = names }
            }
        }
    }

    /// 在期望顺序里上下移动一项。改动立刻落盘，不用等点「应用顺序」。
    func moveServiceOrder(name: String, offset: Int) {
        var names = desiredServiceOrder.map { $0.name }
        guard let index = names.firstIndex(of: name) else { return }
        let target = index + offset
        guard target >= 0, target < names.count else { return }
        names.swapAt(index, target)
        settings.serviceOrder = names
    }

    /// 把期望顺序写进系统。
    func applyServiceOrder() {
        let names = desiredServiceOrder.map { $0.name }
        guard !names.isEmpty else { return }
        // 先把"想要的顺序"记下来：即使这次写系统失败，界面也还知道用户想要什么。
        settings.serviceOrder = names

        activeApplyCount += 1
        applyQueue.async {
            var detail: String?
            var failure: String?
            do {
                detail = try NetworkConfigurator.applyServiceOrder(names)
            } catch {
                failure = error.localizedDescription
            }
            let reloaded = NetworkServiceMap.loadOrder()
            DispatchQueue.main.async {
                self.activeApplyCount = max(0, self.activeApplyCount - 1)
                self.serviceOrder = reloaded
                if let message = failure {
                    Log.shared.error(L.t("写入网络服务优先级失败：%@", message))
                } else if let message = detail {
                    Log.shared.success(L.t("网络服务优先级已更新：%@", message))
                }
            }
        }
    }

    /// 丢掉保存的顺序，回到"直接显示系统当前顺序"的状态。
    func resetServiceOrder() {
        settings.serviceOrder = []
    }

    func report(for interfaceIdentifier: String) -> ApplyReport? {
        return lastReports[interfaceIdentifier]
    }

    func clearReport(for interfaceIdentifier: String) {
        lastReports.removeValue(forKey: interfaceIdentifier)
    }

    /// 「立即按自动配置校正」：不管刚才有没有插拔，强制对一遍。
    func reconcileNow(reason: String) {
        guard settings.autoApplyEnabled else {
            Log.shared.warning(L.t("自动应用总开关已关闭，跳过%@", reason))
            return
        }
        guard privilegeGranted else {
            Log.shared.error(L.t("缺少 root 权限，无法执行%@。请先在「设置 → 权限」里安装免密授权。", reason))
            return
        }
        var didSomething = false
        for status in interfaces where status.isConnected && status.isConfigurable {
            guard let target = autoProfile(for: status.identifier) else { continue }
            // IP/DNS/路由对上了、但勾了置顶而顺序没到位，也要再走一遍。
            if status.matches(target) && !needsServicePromotion(target) {
                Log.shared.info(L.t("接口 %@ 已符合自动配置 %@", status.identifier, target.name))
                continue
            }
            didSomething = true
            Log.shared.info(L.t("%@：接口 %@ 与自动配置 %@ 不一致，开始校正", reason, status.identifier, target.name))
            performApply(profile: target, status: status, requireConnected: true)
        }
        if !didSomething {
            Log.shared.info(L.t("%@：所有已连接接口都符合各自的自动配置", reason))
        }
    }

    // MARK: - 内部

    private func performApply(profile: Profile, status: InterfaceStatus, requireConnected: Bool) {
        activeApplyCount += 1
        Log.shared.info(L.t("开始应用 %@ → %@", profile.name, status.identifier))
        applyQueue.async {
            let report = NetworkConfigurator.apply(profile, to: status, requireConnected: requireConnected)
            DispatchQueue.main.async {
                self.activeApplyCount = max(0, self.activeApplyCount - 1)
                self.lastReports[status.identifier] = report
                if report.hasFailure {
                    for message in report.failureMessages {
                        Log.shared.error(message)
                    }
                } else {
                    Log.shared.success(report.summary)
                }
                // 让界面尽快反映写入后的真实配置
                self.monitor.refresh()
                // 刚置顶过，系统顺序已经变了，把它收成期望顺序，
                // 免得「网络服务优先级」那块一直提示与系统不一致。
                if profile.promoteServiceToTop && !report.hasFailure {
                    self.adoptSystemServiceOrder()
                }
            }
        }
    }

    private func handleConnectivityChange(_ changes: [InterfaceMonitor.Change],
                                         statuses: [InterfaceStatus]) {
        // 插拔网卡会带出或带走网络服务，顺序列表得跟着刷新，
        // 否则界面上那份顺序会一直是旧的，还查不出为什么会对不上。
        if changes.contains(where: { $0.becameConnected }) {
            refreshServiceOrder()
        }
        guard settings.autoApplyEnabled else {
            Log.shared.info(L.t("自动应用总开关已关闭，忽略本次连接事件"))
            return
        }
        for change in changes where change.becameConnected {
            guard let target = autoProfile(for: change.identifier) else {
                Log.shared.info(L.t("接口 %@ 已连接，但没有标记为自动应用的配置，保持系统现状", change.identifier))
                continue
            }
            guard let status = statuses.first(where: { $0.identifier == change.identifier }) else {
                continue
            }
            guard privilegeGranted else {
                Log.shared.error(L.t("接口 %@ 已连接，但缺少 root 权限，无法自动应用 %@", change.identifier, target.name))
                continue
            }
            performApply(profile: target, status: status, requireConnected: true)
        }
    }

    private func scheduleLaunchReconcile() {
        guard settings.reconcileOnLaunch, settings.autoApplyEnabled else { return }
        // 刚启动时系统还没把网络配置下发完，等几秒再判断。
        applyQueue.asyncAfter(deadline: .now() + 5) {
            DispatchQueue.main.async {
                self.reconcileNow(reason: L.t("启动校正"))
            }
        }
    }

    private func uniqueName(base: String, for interfaceIdentifier: String) -> String {
        let existing = Set(profiles(for: interfaceIdentifier).map { $0.name })
        if !existing.contains(base) { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}
