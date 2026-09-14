import Foundation

/// 「设置 / 日志 / 通用控件 / 主窗口骨架」相关文案的英文对照。键是中文原文。
let englishStringsSettings: [String: String] = [
    // MARK: - 设置 / 外观
    "外观": "Appearance",
    "跟随系统时会随系统的浅色/深色切换自动变化，菜单栏面板也一并生效": "When following the system, it changes automatically with the system's Light/Dark appearance, including the menu bar panel.",
    "主题": "Theme",
    "切换后立即生效，不需要重启": "Takes effect immediately; no restart needed.",
    "在 Dock 中显示图标": "Show Icon in Dock",
    "关掉之后应用只驻留在菜单栏，不会占用 Dock 和 ⌘Tab（这是默认行为）": "When off, the app lives only in the menu bar, staying out of the Dock and ⌘Tab (the default).",
    "界面语言": "Interface Language",
    "默认跟随系统语言。切换后界面立即重建，不需要重启": "Follows the system language by default. The interface rebuilds immediately after switching; no restart needed.",

    // MARK: - 设置 / 启动
    "启动": "Startup",
    "开机自动启动": "Launch at Login",
    "打开登录项设置": "Open Login Items Settings",
    "登录后立即刷新接口状态": "Refresh Interface Status at Login",
    "刷新会重新读取接口、链路状态和当前 IP，可随时手动执行": "Refreshing re-reads interfaces, link status, and current IP addresses. You can run it manually at any time.",
    "刷新": "Refresh",
    "已开启。开机后会驻留在菜单栏，接口连上时自动应用配置": "On. The app stays in the menu bar after login and applies the profile automatically when an interface connects.",
    "开启后开机自动驻留菜单栏": "When on, the app stays in the menu bar after login.",
    "系统还要求在「登录项」里手动允许一次，点右边按钮去打开": "macOS also requires you to allow it once in Login Items. Click the button on the right to open them.",

    // MARK: - 设置 / 权限
    "权限": "Permissions",
    "改 IP、增删路由必须以 root 身份执行。安装一次免密授权后，自动应用才不会因为权限不足而失败": "Changing IP addresses and adding or removing routes must run as root. Install the passwordless authorization once so automatic apply doesn't fail for lack of permission.",
    "免密授权已生效": "Passwordless Authorization Active",
    "免密授权未安装": "Passwordless Authorization Not Installed",
    "已授权：/usr/sbin/networksetup、/sbin/route": "Authorized: /usr/sbin/networksetup, /sbin/route",
    "只授权这两条命令、仅限 admin 组成员，改动范围比输入密码更可控": "Authorizes only these two commands, only for members of the admin group — a more controlled scope than typing a password each time.",
    "已就绪": "Ready",
    "未完成": "Incomplete",
    "重新检测": "Check Again",
    "收起命令": "Hide Command",
    "查看安装命令": "View Installation Command",
    "当前用户 %@ 不在 admin 组，这条规则对它不生效。": "%@ is not in the admin group, so this rule does not apply to it.",
    "想撤销授权就执行这行：": "To revoke the authorization, run this line:",

    // MARK: - 设置 / 数据
    "数据": "Data",
    "运行日志": "Activity Log",
    "记录每次应用配置的逐项结果，排查「为什么没自动生效」时看这里": "Records each step of every apply. Check here when a profile doesn't take effect as expected.",
    "查看日志": "View Log",
    "配置文件位置": "Profile Folder",
    "在访达中打开": "Show in Finder",
    "日志文件位置": "Log File",
    "在访达中显示": "Show in Finder",

    // MARK: - 日志查看器
    "还没有日志": "No Activity Yet",
    "没有符合筛选条件的日志": "No entries match the current filter",
    "清空日志": "Clear Log",
    "会同时清空界面上的记录和日志文件内容，确定吗？": "This also clears the on-screen entries and the log file contents. Are you sure?",
    "清空": "Clear",
    "日志已清空": "Log cleared",
    "%d / %d 条": "%d / %d entries",
    "在访达中显示日志文件": "Show Log File in Finder",
    "关闭": "Close",
    "全部": "All",
    "警告与错误": "Warnings & Errors",
    "只看错误": "Errors Only",

    // MARK: - 应用结果 / 通用控件
    "%@：%@": "%@: %@",
    "已复制": "Copied",
    "复制命令": "Copy Command",
    "在终端里执行，只需要做一次": "Run this once in Terminal.",
    // 主窗口骨架（导航栏 / 搜索框）
    "接口概览": "Interfaces",
    "配置管理": "Profiles",
    "自动化规则": "Automation",
    "设置": "Settings",
    "打开设置": "Open Settings",
    "搜索配置": "Search Profiles",
    "等待授权…": "Waiting for authorization…",
    "一键安装授权": "Install Authorization",
    "上面的按钮会弹一次系统密码框，输完即装好。不想用按钮，就在「终端」里粘贴执行下面这行，效果完全一样，也只需做一次。": "The button above prompts for your macOS password once; enter it and you are done. If you would rather not use the button, paste the line below into Terminal — it does exactly the same thing, and only needs to be done once.",

    // MARK: - 设置 / 数据与存储
    "iCloud Drive（多台 Mac 自动同步）": "iCloud Drive (synced across your Macs)",
    "本机（这台机器没开 iCloud）": "This Mac only (iCloud is not enabled here)",
    "设置文件位置": "Settings File Location",
    "开机启动、Dock 图标、网络服务顺序这些都跟具体机器绑定，所以设置留在本机：%@": "Launch at login, the Dock icon and the network service order are tied to this particular Mac, so settings stay on this machine: %@",
    "回收站保留天数": "Trash Retention",
    "删除的配置先放回收站，超过这个天数才真的从磁盘上删掉": "Deleted profiles go to the trash first and are only removed from disk after this many days.",
    "%d 天": "%d days",
    "重试": "Retry",
    "配置还在云端，本次运行暂时只读": "Profiles are still in the cloud; this run is read-only",
    "%@，这期间不会写回云端，免得把云端已有的配置覆盖成空白。": "%@, so nothing is written back to the cloud for now — that way existing cloud profiles are not overwritten with an empty list.",
]
