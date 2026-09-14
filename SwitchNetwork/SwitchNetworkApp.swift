import SwiftUI

/// 应用入口。
///
/// 主窗口不由 SwiftUI 的 WindowGroup 管理（openWindow 要 macOS 13+），
/// 而是由 AppDelegate 手动创建 NSWindow，这样任意版本上都能做到
/// "默认只驻留菜单栏、需要时才开窗口"。
@main
struct SwitchNetworkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
