import Foundation

/// 「数据模型 / 日志」相关文案的英文对照。键是中文原文。
let englishStringsModels: [String: String] = [
    // IPMode / DNSMode
    "手动": "Manual",
    "手工填写 IP、掩码和网关": "Manually enter the IP, mask, and gateway",
    "IP、掩码和网关由 DHCP 服务器下发，本地填写的值会被忽略": "IP, mask, and gateway are provided by the DHCP server; locally entered values are ignored",
    "手动指定": "Manual",
    "自动获取": "Automatic",
    "按下面的列表顺序使用": "Used in the order listed below",
    "清空手动 DNS，交给系统获取。DHCP 下就是服务器下发的 DNS": "Clears the manual DNS list and lets the system handle it. Under DHCP this is the DNS provided by the server",

    // Route 校验
    "缺少目的网段": "Destination is required",
    "目的网段格式不正确": "Destination has an invalid format",
    "子网掩码不正确": "Invalid subnet mask",
    "下一跳网关不正确": "Invalid next hop",
    "metric 不能为负数": "Metric cannot be negative",
    "不支持用静态路由覆盖默认网关，请改用「网关」字段": "Overriding the default gateway with a static route is not supported; use the Gateway field instead",

    // Profile 展示
    "DHCP 自动获取": "Automatic via DHCP",
    "未设置 IP": "No IP address",
    "DNS 自动获取": "Automatic DNS",
    "DNS 未设置": "DNS not set",
    "网关 %@": "Gateway %@",

    // Profile 校验
    "名称不能为空": "Name is required",
    "必须选择绑定的网络接口": "A bound interface must be selected",
    "IP 地址不能为空": "IP Address is required",
    "IP 地址格式不正确": "IP Address has an invalid format",
    "子网掩码不正确，必须是连续的网络位（如 255.255.255.0）": "Subnet mask must be a contiguous block of network bits (e.g. 255.255.255.0)",
    "网关格式不正确": "Gateway has an invalid format",
    "网关 %@ 不在本机网段 %@ 内，请确认": "Gateway %@ is not within this machine's network %@; please verify",
    "DNS 选了「手动指定」就至少要填一个地址，或改成「自动获取」": "When DNS is set to Manual, you must enter at least one address, or switch to Automatic",
    "第 %d 个 DNS 地址格式不正确": "DNS address #%d has an invalid format",
    "路由 %d：%@": "Route %d: %@",

    // InterfaceType
    "有线": "Wired",
    "网桥": "Bridge",
    "其他": "Other",

    // InterfaceConfigurationMode
    "已关闭": "Disabled",
    "未知": "Unknown",

    // InterfaceStatus 摘要
    "已连接 · %@": "Connected · %@",
    "已连接": "Connected",
    "未连接": "Not Connected",
    "无 IP": "No IP",

    // Log.Level
    "信息": "Info",
    "成功": "Success",
    "警告": "Warning",
    "错误": "Error",

    // AppearanceMode
    "跟随系统": "Follow System",
    "浅色": "Light",
    "深色": "Dark",

    // MARK: - 存储位置 / iCloud 同步
    "iCloud 里的 %@ 还没下载完": "%@ in iCloud has not finished downloading yet",
    "读取 %@ 失败：%@": "Failed to read %@: %@",
    "已暂停写入 %@：%@": "Paused writing %@: %@",
    "请求 iCloud 下载 %@ 失败，等系统自己同步": "Failed to request the iCloud download of %@; waiting for the system to sync it.",
    "暂时不能写入配置：%@": "Cannot write profiles right now: %@",
    "暂时不能写入配置，保存已取消：%@": "Cannot write profiles right now; saving was cancelled: %@",
    "暂时不能写入配置，删除已取消：%@": "Cannot write profiles right now; deleting was cancelled: %@",
    "云端配置已经下载完，恢复写入": "The cloud profiles finished downloading; writing is enabled again.",
    "等了 30 秒还没等到云端文件，本次运行不再重试；网络恢复后重开应用即可": "Waited 30 seconds for the cloud files without success; giving up for this run. Reopen the app once the network is back.",
    "已把本机的 %d 份配置导入 iCloud，本机那份保留作备份": "Imported %d local profiles into iCloud; the local copies are kept as a backup.",
    "把本机配置导入 iCloud": "Import Local Profiles into iCloud",
    "检测到本机有 %d 份配置，iCloud 里还是空的。导入后这几台 Mac 就能共用同一份配置。": "Found %d profiles on this Mac while iCloud is still empty. Import them and your Macs will share the same profiles.",
    "本机那份会保留作备份，不会删掉。": "The local copies are kept as a backup and are not deleted.",
    "不用了，以后不再提示": "Not now, and don't ask again",
    "导入 iCloud": "Import into iCloud"
]
