import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState.shared
        state.start()

        statusItemController = StatusItemController(state: state) { [weak self] in
            guard let delegate = self else { return }
            delegate.showMainWindow()
        }

        if CommandLine.arguments.contains("--launched-at-login") {
            // 开机启动时只驻留菜单栏，不弹窗口打扰用户。
            Log.shared.info(L.t("由开机启动拉起，仅驻留菜单栏"))
        } else {
            showMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - 主窗口

    func showMainWindow() {
        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            SystemCompat.activateApp()
            return
        }

        let hosting = NSHostingView(rootView: MainWindowView().environmentObject(AppState.shared))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "SwitchNetwork"
        window.contentView = hosting
        // 关掉窗口不销毁实例，菜单栏里「打开主窗口」才能再把它找回来。
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 940, height: 660)
        window.titlebarSeparatorStyle = .line
        window.center()
        _ = window.setFrameAutosaveName("SwitchNetworkMainWindow")
        window.makeKeyAndOrderFront(nil)

        mainWindow = window
        SystemCompat.activateApp()
    }
}
