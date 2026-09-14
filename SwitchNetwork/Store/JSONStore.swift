import Foundation

/// 一份数据放在哪一边。
enum StoreScope {
    /// 跟着 iCloud Drive 走：配置和回收站，多台 Mac 共用同一份。
    case synced
    /// 只在本机：设置。里面是开机启动、服务顺序这类跟具体机器绑定的东西，
    /// 同步过去只会让人困惑（服务名本来就因机器而异）。
    case local
}

/// 读取结果。
///
/// 故意把「确定没有」和「读不出来」分开：iCloud 会为了省空间把文件内容收走，
/// 只在本地留一个 `.<文件名>.icloud` 占位符。这时候读不到内容**并不代表没有数据**，
/// 当成「没有」就会拿默认值（空数组）往下走，下一次保存就把云端的真配置覆盖掉了。
enum LoadOutcome<T> {
    /// 读到了，也解析成功。
    case loaded(T)
    /// 文件确实不存在（连占位符都没有）。用默认值是安全的。
    case missing
    /// 文件在、字节也读到了，但解析不了。已经另存 `.corrupt` 备份，可以用默认值继续。
    case corrupt(String)
    /// 字节拿不到（云端还没下载完、占位符下载失败、权限或 IO 错误）。
    /// 调用方要当作「这次不能写」处理，别用默认值覆盖磁盘上可能存在的真数据。
    case unreadable(String)

    var value: T? {
        if case .loaded(let loaded) = self { return loaded }
        return nil
    }
}

/// 数据的落盘位置。
///
/// - 配置、回收站：优先 iCloud Drive 的 `SwitchNetwork/`，机器上没开 iCloud 就退回本机目录。
/// - 设置：始终在本机 `~/Library/Application Support/SwitchNetwork/`。
enum JSONStore {

    /// iCloud Drive 里的配置目录。这台机器没开 iCloud Drive 时为 nil。
    static var cloudDirectory: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: drive.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return drive.appendingPathComponent("SwitchNetwork", isDirectory: true)
    }

    /// 本机目录。也是旧版本配置所在的位置，迁移时从这里读。
    static var localDirectory: URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = base ?? manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return root.appendingPathComponent("SwitchNetwork", isDirectory: true)
    }

    static func directory(for scope: StoreScope) -> URL {
        switch scope {
        case .local:
            return localDirectory
        case .synced:
            return cloudDirectory ?? localDirectory
        }
    }

    /// 配置是不是真的落在 iCloud 里。设置页和迁移提示都要用它。
    static var isUsingCloud: Bool {
        return cloudDirectory != nil
    }

    // MARK: - 只读闸

    /// 出现过「读不出来」时置上：本次运行期间拒绝写入同步范围的数据。
    /// 宁可这次不写，也不能把云端的真配置覆盖成空。
    private static var freezeReason: String?

    static var isFrozen: Bool {
        return freezeReason != nil
    }

    static func freeze(_ reason: String) {
        if freezeReason == nil { freezeReason = reason }
    }

    static func unfreeze() {
        freezeReason = nil
    }

    // MARK: - 读写

    static func load<T: Decodable>(_ type: T.Type,
                                   from fileName: String,
                                   scope: StoreScope) -> LoadOutcome<T> {
        let folder = directory(for: scope)
        let url = folder.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: url.path) {
            guard scope == .synced else { return .missing }
            guard requestCloudDownload(of: fileName, in: folder) else { return .missing }
            let reason = L.t("iCloud 里的 %@ 还没下载完", fileName)
            freeze(reason)
            return .unreadable(reason)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // 文件在却读不出字节：属于不确定状态，不能拿默认值顶上去。
            let reason = L.t("读取 %@ 失败：%@", fileName, error.localizedDescription)
            Log.shared.error(reason)
            freeze(reason)
            return .unreadable(reason)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return .loaded(try decoder.decode(T.self, from: data))
        } catch {
            let message = L.t("解析 %@ 失败：%@", fileName, error.localizedDescription)
            Log.shared.error(message)
            // 把损坏的文件挪到一边，避免下次保存直接把它覆盖掉，用户还有手工抢救的机会。
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return .corrupt(message)
        }
    }

    /// 写盘。被只读闸拦住时返回 false，调用方不用自己判断。
    @discardableResult
    static func save<T: Encodable>(_ value: T, to fileName: String, scope: StoreScope) -> Bool {
        if scope == .synced, isFrozen {
            Log.shared.error(L.t("已暂停写入 %@：%@", fileName, freezeReason ?? ""))
            return false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let folder = directory(for: scope)
            try FileManager.default.createDirectory(at: folder,
                                                   withIntermediateDirectories: true,
                                                   attributes: nil)
            let data = try encoder.encode(value)
            try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
            return true
        } catch {
            Log.shared.error(L.t("写入 %@ 失败：%@", fileName, error.localizedDescription))
            return false
        }
    }

    // MARK: - iCloud 占位符

    /// 文件内容被 iCloud 收走时，本地只剩 `.<文件名>.icloud` 这个占位符。
    /// 有占用符就催它下载（异步，不等结果）。返回是否确实存在占位符。
    private static func requestCloudDownload(of fileName: String, in folder: URL) -> Bool {
        let placeholder = folder.appendingPathComponent("." + fileName + ".icloud")
        guard FileManager.default.fileExists(atPath: placeholder.path) else { return false }

        // 占位符路径和真实路径指向同一个 iCloud 条目，但不同 macOS 版本上
        // 认哪个不太一致，所以两个都试一遍；都失败就等系统自己同步。
        let target = folder.appendingPathComponent(fileName)
        for candidate in [placeholder, target] {
            if (try? FileManager.default.startDownloadingUbiquitousItem(at: candidate)) != nil {
                return true
            }
        }
        Log.shared.warning(L.t("请求 iCloud 下载 %@ 失败，等系统自己同步", fileName))
        return true
    }
}
