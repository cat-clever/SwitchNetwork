import Foundation

/// 「应用状态 / 菜单栏 / 系统兼容 / 存储」相关文案的英文对照。键是中文原文。
let englishStringsApp: [String: String] = [
    // AppState
    "设置开机启动失败：%@": "Failed to set Launch at Login: %@",
    "已开启开机启动": "Launch at Login enabled",
    "已关闭开机启动": "Launch at Login disabled",
    "%@ 副本": "%@ Copy",
    "已克隆 %@ → %@": "Duplicated %@ → %@",
    "找不到接口 %@，无法应用 %@": "Interface %@ not found; cannot apply %@",
    "自动应用总开关已关闭，跳过%@": "Auto Apply master switch is off; skipping %@",
    "缺少 root 权限，无法执行%@。请先在「设置 → 权限」里安装免密授权。": "Missing root privileges; cannot perform %@. Install Passwordless Authorization in Settings → Permissions first.",
    "接口 %@ 已符合自动配置 %@": "Interface %@ already matches Auto-Apply Profile %@",
    "%@：接口 %@ 与自动配置 %@ 不一致，开始校正": "%@: Interface %@ does not match Auto-Apply Profile %@; starting reconcile",
    "%@：所有已连接接口都符合各自的自动配置": "%@: all connected interfaces match their Auto-Apply Profiles",
    "开始应用 %@ → %@": "Applying %@ → %@",
    "自动应用总开关已关闭，忽略本次连接事件": "Auto Apply master switch is off; ignoring this connectivity event",
    "接口 %@ 已连接，但没有标记为自动应用的配置，保持系统现状": "Interface %@ is connected but has no Auto-Apply Profile; leaving the system as is",
    "接口 %@ 已连接，但缺少 root 权限，无法自动应用 %@": "Interface %@ is connected but root privileges are missing; cannot auto apply %@",
    "启动校正": "Launch Reconcile",

    // StatusItemController
    "SwitchNetwork：有接口的配置未按预期生效": "SwitchNetwork: some interface profiles are not in effect as expected",
    "SwitchNetwork：自动配置均已生效": "SwitchNetwork: all Auto-Apply Profiles are in effect",
    "SwitchNetwork：还没有标记为自动应用的配置": "SwitchNetwork: no Auto-Apply Profiles yet",
    "没有检测到网络接口": "No network interfaces detected",
    "⚠︎ 免密授权未安装，自动应用会失败": "⚠︎ Passwordless Authorization is not installed; Auto Apply will fail",
    "打开主窗口": "Open Main Window",
    "立即按自动配置校正": "Reconcile with Auto-Apply Profiles Now",
    "刷新接口状态": "Refresh Interface Status",
    "退出 SwitchNetwork": "Quit SwitchNetwork",
    "有配置未生效": "Profiles Not In Effect",
    "自动配置已生效": "Auto-Apply Profiles In Effect",
    "未设置自动配置": "No Auto-Apply Profile",
    "还没有为该接口保存的配置": "No profiles saved for this interface yet",
    "（自动）": " (Auto)",
    "自动配置：%@": "Auto-Apply Profile: %@",
    "未指定自动配置": "No Auto-Apply Profile",
    "当前 IP：%@": "Current IP: %@",
    "网关：%@": "Gateway: %@",
    "DNS：%@": "DNS: %@",
    "该接口在系统里没有对应的网络服务，无法写入配置": "This interface has no matching Network Service in the system; configuration cannot be written",
    "菜单栏手动校正": "Manual reconcile from menu bar",

    // SystemCompat
    "已开启": "Enabled",
    "等待你在系统设置里批准": "Waiting for your approval in System Settings",
    "设置失败：%@": "Setup failed: %@",
    "读不到 App 的可执行文件路径，无法注册开机启动": "Cannot read the app executable path; unable to register Launch at Login",
    "launchctl 注册失败：%@": "launchctl registration failed: %@",

    // JSONStore
    "解析 %@ 失败：%@": "Failed to parse %@: %@",
    "写入 %@ 失败：%@": "Failed to write %@: %@",

    // Shell
    "无法启动 %@": "Failed to launch %@",
    "%@ 执行超时": "%@ timed out",

    // AppDelegate
    "由开机启动拉起，仅驻留菜单栏": "Launched at login; staying in the menu bar only",
    "网络服务优先级已更新：%@": "Network service priority updated: %@",
    "写入网络服务优先级失败：%@": "Failed to write the network service priority: %@",
    "正在申请管理员授权以安装免密配置": "Requesting administrator authorization to install the passwordless configuration.",
    "免密授权已安装：%@": "Passwordless authorization installed: %@",
    "已取消安装免密授权": "Passwordless authorization installation cancelled.",
    "安装免密授权失败：%@": "Failed to install passwordless authorization: %@",
    "找不到接口 %@，无法交还系统": "Cannot find interface %@; unable to return it to the system",
    "已关闭「%@」的自动应用，否则下次连接会再写回来": "Auto apply for %@ was turned off, otherwise the next connection would write it back",
    "开始把接口 %@ 交还系统": "Returning interface %@ to the system",
]
