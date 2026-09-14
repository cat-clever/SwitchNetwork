import AppKit
import Combine

/// 菜单栏常驻图标与下拉菜单。
///
/// 需求文档要求"默认不出现在 Dock，只驻留菜单栏"，所以这里用 NSStatusItem 而不是
/// SwiftUI 的 MenuBarExtra（后者要 macOS 13+）。菜单内容每次弹出时重建，
/// 保证看到的一定是当前状态。
final class StatusItemController: NSObject, NSMenuDelegate {

    private let state: AppState
    private let onOpenMainWindow: () -> Void
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(state: AppState, onOpenMainWindow: @escaping () -> Void) {
        self.state = state
        self.onOpenMainWindow = onOpenMainWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        refreshButton()
        bind()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - 状态栏图标

    private func bind() {
        state.$interfaces
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let controller = self else { return }
                controller.refreshButton()
            }
            .store(in: &cancellables)

        state.$profiles
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let controller = self else { return }
                controller.refreshButton()
            }
            .store(in: &cancellables)

        state.$privilegeGranted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let controller = self else { return }
                controller.refreshButton()
            }
            .store(in: &cancellables)

        // 提示语是取当前语言的，换语言后要马上重取，别等下一次接口刷新。
        state.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let controller = self else { return }
                controller.refreshButton()
            }
            .store(in: &cancellables)
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        switch state.healthState {
        case .attention:
            symbolName = Symbols.resolve("exclamationmark.triangle", fallback: "network")
            button.contentTintColor = NSColor.systemOrange
        case .normal:
            symbolName = Symbols.resolve("network", fallback: "network")
            button.contentTintColor = nil
        case .unconfigured:
            symbolName = Symbols.resolve("network", fallback: "network")
            button.contentTintColor = nil
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SwitchNetwork")
        if let image = image {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "SN"
        }
        button.toolTip = tooltip
    }

    private var tooltip: String {
        switch state.healthState {
        case .attention:
            return L.t("SwitchNetwork：有接口的配置未按预期生效")
        case .normal:
            return L.t("SwitchNetwork：自动配置均已生效")
        case .unconfigured:
            return L.t("SwitchNetwork：还没有标记为自动应用的配置")
        }
    }

    // MARK: - 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if state.interfaces.isEmpty {
            let empty = NSMenuItem(title: L.t("没有检测到网络接口"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for status in state.interfaces {
                menu.addItem(makeInterfaceItem(for: status))
            }
        }

        menu.addItem(.separator())

        if !state.privilegeGranted {
            let warning = NSMenuItem(title: L.t("⚠︎ 免密授权未安装，自动应用会失败"), action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        menu.addItem(makeActionItem(title: L.t("打开主窗口"),
                                    symbol: "macwindow",
                                    action: #selector(openMainWindow)))
        let reconcile = makeActionItem(title: L.t("立即按自动配置校正"),
                                       symbol: "arrow.triangle.2.circlepath",
                                       action: #selector(reconcile))
        reconcile.isEnabled = state.settings.autoApplyEnabled
        menu.addItem(reconcile)
        menu.addItem(makeActionItem(title: L.t("刷新接口状态"),
                                    symbol: "arrow.clockwise",
                                    action: #selector(refreshInterfaces)))
        menu.addItem(.separator())
        menu.addItem(makeActionItem(title: L.t("退出 SwitchNetwork"),
                                    symbol: "power",
                                    action: #selector(quit)))
    }

    private var headerTitle: String {
        switch state.healthState {
        case .attention:
            return L.t("有配置未生效")
        case .normal:
            return L.t("自动配置已生效")
        case .unconfigured:
            return L.t("未设置自动配置")
        }
    }

    private func makeInterfaceItem(for status: InterfaceStatus) -> NSMenuItem {
        let item = NSMenuItem(title: "\(status.displayName) · \(status.connectionLabel)",
                              action: nil,
                              keyEquivalent: "")
        item.image = dotImage(color: status.isConnected ? NSColor.systemGreen : NSColor.tertiaryLabelColor)
        item.toolTip = interfaceTooltip(for: status)

        // 注意不要给子菜单设 delegate：menuNeedsUpdate 会把主菜单内容填进子菜单。
        // 子菜单在父菜单重建时一起重建，不需要单独刷新。
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let owned = state.profiles(for: status.identifier)
        let current = state.currentProfile(for: status)
        let auto = state.autoProfile(for: status.identifier)

        if owned.isEmpty {
            let hint = NSMenuItem(title: L.t("还没有为该接口保存的配置"), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            submenu.addItem(hint)
        } else {
            for profile in owned {
                let suffix = profile.autoApplyOnConnect ? L.t("（自动）") : ""
                let entry = NSMenuItem(title: "\(profile.name)\(suffix)",
                                       action: #selector(applyProfile(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.representedObject = profile.id
                if let current = current, current.id == profile.id {
                    entry.state = .on
                }
                var tips = ["\(profile.ipSummary) · \(profile.dnsSummary)"]
                if let gateway = profile.gatewaySummary { tips.append(gateway) }
                if !profile.validationErrors.isEmpty {
                    tips.append(contentsOf: profile.validationErrors)
                }
                entry.toolTip = tips.joined(separator: "\n")
                submenu.addItem(entry)
            }
        }

        submenu.addItem(.separator())

        let refresh = NSMenuItem(title: L.t("刷新接口状态"),
                                 action: #selector(refreshInterfaces),
                                 keyEquivalent: "")
        refresh.target = self
        submenu.addItem(refresh)

        if let target = auto {
            let note = NSMenuItem(title: L.t("自动配置：%@", target.name), action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
        } else {
            let note = NSMenuItem(title: L.t("未指定自动配置"), action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
        }

        item.submenu = submenu
        return item
    }

    private func interfaceTooltip(for status: InterfaceStatus) -> String {
        var lines = [status.title]
        lines.append(L.t("当前 IP：%@", status.currentIPLabel))
        if let gateway = status.currentGateway, !gateway.isEmpty {
            lines.append(L.t("网关：%@", gateway))
        }
        if !status.currentDNS.isEmpty {
            lines.append(L.t("DNS：%@", status.currentDNS.joined(separator: ", ")))
        }
        if !status.isConfigurable {
            lines.append(L.t("该接口在系统里没有对应的网络服务，无法写入配置"))
        }
        return lines.joined(separator: "\n")
    }

    private func makeActionItem(title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = menuIcon(symbol)
        return item
    }

    private func menuIcon(_ symbol: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: Symbols.resolve(symbol, fallback: "circle"),
                                  accessibilityDescription: nil) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    /// 用代码画一个彩色圆点。菜单项图片默认按模板渲染会被染色，必须关掉 isTemplate。
    private func dotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false, drawingHandler: { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 6, height: 6)).fill()
            return true
        })
        image.isTemplate = false
        return image
    }

    // MARK: - 动作

    @objc private func openMainWindow() {
        onOpenMainWindow()
    }

    @objc private func reconcile() {
        state.reconcileNow(reason: L.t("菜单栏手动校正"))
    }

    @objc private func refreshInterfaces() {
        state.refreshAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? UUID else { return }
        state.apply(profileID: identifier, requireConnected: false)
    }
}
