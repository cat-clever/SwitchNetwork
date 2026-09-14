import Foundation

/// 「网络操作层（networksetup / route）」相关文案的英文对照。键是中文原文。
let englishStringsNetwork: [String: String] = [
    // MARK: - 通用 / 报告
    "%@，%@": "%@, %@",
    "%@ — %@": "%@ — %@",
    "没有执行任何操作": "No actions were performed.",
    "%@ 应用失败：%@": "Failed to apply %@: %@",
    "%@ 已应用到 %@": "%@ applied to %@",
    "%@ 已应用到 %@（%d 项提示）": "%@ applied to %@ (%d warnings)",

    // MARK: - NetworkConfigurator
    "缺少 root 权限。请在「设置 → 权限」里按提示安装 sudo 免密授权。": "Root privileges are missing. Install Passwordless Authorization from Settings → Permissions by following the on-screen instructions.",
    "接口 %@ 在系统里没有对应的网络服务，无法写入配置": "Interface %@ has no matching Network Service in the system, so its configuration cannot be written.",
    "接口 %@ 当前未连接，已跳过自动应用": "Interface %@ is not connected; skipped Auto-Apply Profile.",
    "配置校验": "Profile Validation",
    "网络服务": "Network Service",
    "连接状态": "Connection Status",
    "接口当前未连接，配置已写入，待接口连上后生效": "The interface is not connected. Configuration has been written and will take effect once the interface connects.",
    "IP 配置": "IP Configuration",
    "该配置没有静态路由": "This profile has no Static Routes.",
    "路由 %d": "Route %d",
    " / 网关 %@": " / Gateway %@",
    "已切换为 DHCP，IP / 掩码 / 网关由服务器下发": "Switched to DHCP; IP / Subnet Mask / Gateway are provided by the server.",
    "已清空，回退到自动获取": "Cleared; reverted to automatic retrieval.",
    "已清空手动 DNS，交给系统自动获取": "Manual DNS cleared; the system will retrieve it automatically.",

    // MARK: - RouteManager
    "已生效": "In effect",
    "路由表中不存在，需要添加": "Not present in the routing table; needs to be added.",
    "下一跳不符：期望 %@，实际 %@": "Next Hop mismatch: expected %@, actual %@",
    "掩码不符：期望 %@，实际 %@": "Subnet Mask mismatch: expected %@, actual %@",
    "系统已存在直连路由（%@），静态路由无法覆盖": "The system already has a connected route (%@); a Static Route cannot override it.",
    "尚未检查": "Not checked yet",
    "执行 netstat 失败": "Failed to run netstat.",
    "读取路由表失败：%@": "Failed to read the routing table: %@",
    "路由参数不完整或格式错误，已跳过": "Route parameters are incomplete or malformed; skipped.",
    "不支持用静态路由覆盖默认网关，请直接设置「网关」字段": "Overriding the default gateway with a Static Route is not supported. Set the Gateway field instead.",
    "%@ 是系统直连路由（%@），静态路由无法覆盖，已跳过": "%@ is a system connected route (%@); a Static Route cannot override it, skipped.",
    "%@ 已存在且下一跳一致，跳过": "%@ already exists with the same Next Hop, skipped.",
    "%@/%d 是系统直连路由，不属于静态路由，未做删除": "%@/%d is a system connected route, not a Static Route; nothing was deleted.",
    "带 metric 添加路由失败，去掉 metric 重试：%@": "Adding the route with metric failed; retrying without metric: %@",
    "route add %@ 失败：%@": "route add %@ failed: %@",
    "已添加 %@ → %@": "Added %@ → %@",
    "route delete %@ 失败：%@": "route delete %@ failed: %@",
    "已删除 %@": "Deleted %@",

    // MARK: - InterfaceMonitor
    "创建 SCDynamicStore 失败，接口状态监听未启动，只能用「立即刷新」手动更新": "Failed to create SCDynamicStore; interface status monitoring was not started, so you can only update manually with Refresh Now.",
    "注册网络状态通知失败，将只能手动刷新": "Failed to register network status notifications; only manual refresh will be available.",
    "接口状态监听已启动": "Interface status monitoring started.",
    "接口 %@ 已连接": "Interface %@ connected.",
    "接口 %@ 已断开": "Interface %@ disconnected.",

    // MARK: - InterfaceEnumerator
    "读不到 Wi-Fi 的 SSID，通常是未授予定位权限；不影响连接状态的判断。": "Could not read the Wi-Fi SSID; this usually means Location permission was not granted. It does not affect connection status detection.",

    // MARK: - NetworkServiceMap
    "执行 networksetup -listnetworkserviceorder 失败": "Failed to run networksetup -listnetworkserviceorder.",
    "读取网络服务列表失败：%@": "Failed to read the Network Service list: %@",

    // MARK: - PrivilegeManager
    "sudo 免密尚未配置：%@": "Passwordless Authorization for sudo is not configured yet: %@",
    "探测 sudo 权限时出现异常：%@": "An error occurred while probing sudo privileges: %@",
    "探测 sudo 权限失败：%@": "Failed to probe sudo privileges: %@",

    // MARK: - ServiceConfigReader
    "读取 %@ 的配置失败：%@": "Failed to read the configuration of %@: %@",
    "服务列表为空，已取消写入顺序": "The service list is empty, so writing the order was cancelled.",
    "服务列表与系统不一致（系统里共 %d 项），已取消写入顺序": "The service list does not match the system (which has %d services), so writing the order was cancelled.",
    "已应用 %d 项服务的顺序": "Applied the order of %d services.",
    "服务优先级": "Service Priority",
    "系统里找不到服务「%@」，无法调整优先级": "No service named \"%@\" exists in the system, so its priority cannot be changed.",
    "「%@」本来就在最前面": "\"%@\" is already at the top.",
    "已把「%@」提到最前面": "Moved \"%@\" to the top.",
    "不使用配置": "No Profile",
    "接口当前未连接，已写入的撤销要等接口连上才生效": "The interface is not connected; the revert takes effect once it connects",
    "没有需要撤销的静态路由": "No static routes to remove",
    "%@ 不在路由表里，无需撤销": "%@ is not in the routing table; nothing to remove",
    "接口 %@ 已交还系统：IP 走 DHCP，DNS 自动获取": "Interface %@ returned to the system: IP via DHCP, DNS automatic",
    "接口 %@ 已交还系统（%d 项提示）": "Interface %@ returned to the system (%d notices)",
    "接口 %@ 交还系统失败：%@": "Failed to return interface %@ to the system: %@",
]
