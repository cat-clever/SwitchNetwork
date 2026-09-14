import Foundation
import SystemConfiguration

/// 监听网络接口状态变化。
///
/// 用 SCDynamicStore 的通知机制而不是轮询：注册 `State:/Network/Interface/*/Link`
/// 等键的通配模式，系统在链路状态变化时回调我们。
///
/// 有线（网线插入并完成协商）和 Wi-Fi（已关联）都会反映在同一个 Link 键上，
/// 所以不需要为两种介质各写一套 monitor。
final class InterfaceMonitor {

    struct Change {
        let identifier: String
        let becameConnected: Bool
    }

    /// 接口从"未连接"翻转为"已连接"（或反向）时回调，主线程。
    /// 同时带上这一轮的接口快照，避免调用方再去依赖回调顺序。
    var onConnectivityChange: (([Change], [InterfaceStatus]) -> Void)?
    /// 每次重新枚举完成后回调，携带最新快照，主线程。
    var onStatusUpdate: (([InterfaceStatus]) -> Void)?

    private let queue = DispatchQueue(label: "com.CleverCat.SwitchNetwork.monitor")
    private var store: SCDynamicStore?
    private var previousConnectivity: [String: Bool] = [:]
    private var debounceWork: DispatchWorkItem?
    private var debounceSeconds: Double = 1.5
    private var isStarted = false

    func start() {
        queue.async {
            guard !self.isStarted else { return }

            var context = SCDynamicStoreContext(version: 0,
                                                info: Unmanaged.passUnretained(self).toOpaque(),
                                                retain: nil,
                                                release: nil,
                                                copyDescription: nil)
            // 闭包不捕获任何外部变量，因此可以转换成 C 函数指针。
            let callback: SCDynamicStoreCallBack = { _, _, info in
                guard let info = info else { return }
                Unmanaged<InterfaceMonitor>.fromOpaque(info).takeUnretainedValue().dynamicStoreDidChange()
            }

            guard let created = SCDynamicStoreCreate(nil,
                                                     "com.CleverCat.SwitchNetwork.monitor" as CFString,
                                                     callback,
                                                     &context) else {
                Log.shared.error(L.t("创建 SCDynamicStore 失败，接口状态监听未启动，只能用「立即刷新」手动更新"))
                return
            }

            let patterns = [
                "State:/Network/Interface/.*/Link",
                "State:/Network/Interface/.*/IPv4",
                "State:/Network/Global/IPv4"
            ] as CFArray

            if !SCDynamicStoreSetNotificationKeys(created, nil, patterns) {
                Log.shared.warning(L.t("注册网络状态通知失败，将只能手动刷新"))
            }
            SCDynamicStoreSetDispatchQueue(created, self.queue)

            self.store = created
            self.isStarted = true
            Log.shared.info(L.t("接口状态监听已启动"))
            self.reload()
        }
    }

    func stop() {
        queue.async {
            guard self.isStarted else { return }
            if let existing = self.store {
                SCDynamicStoreSetDispatchQueue(existing, nil)
            }
            self.store = nil
            self.isStarted = false
        }
    }

    /// 立即重新枚举一次。会正常触发"未连接 → 已连接"的翻转判定。
    func refresh() {
        queue.async {
            self.reload()
        }
    }

    func updateDebounce(_ seconds: Double) {
        queue.async {
            self.debounceSeconds = seconds
        }
    }

    // MARK: - 内部（全部在 queue 上执行）

    fileprivate func dynamicStoreDidChange() {
        // 网络协商期间 Link 键会反复跳变，等状态稳定后再统一判定，
        // 否则一次插网线可能触发好几轮配置写入。
        if let pending = debounceWork {
            pending.cancel()
        }
        let work = DispatchWorkItem { [weak self] in
            guard let monitor = self else { return }
            monitor.reload()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
    }

    private func reload() {
        let statuses = InterfaceEnumerator.enumerate()

        var changes: [Change] = []
        var currentConnectivity: [String: Bool] = [:]

        for status in statuses {
            currentConnectivity[status.identifier] = status.isConnected
            let previous = previousConnectivity[status.identifier]
            if previous == false && status.isConnected {
                changes.append(Change(identifier: status.identifier, becameConnected: true))
                Log.shared.info(L.t("接口 %@ 已连接", status.identifier))
            } else if previous == true && !status.isConnected {
                Log.shared.info(L.t("接口 %@ 已断开", status.identifier))
            }
        }
        previousConnectivity = currentConnectivity

        DispatchQueue.main.async {
            if let handler = self.onStatusUpdate {
                handler(statuses)
            }
            if !changes.isEmpty, let handler = self.onConnectivityChange {
                handler(changes, statuses)
            }
        }
    }
}
