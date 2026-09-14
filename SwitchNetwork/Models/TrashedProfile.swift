import Foundation

/// 回收站里的一份配置。删配置先进这里，过了保留期才真的从磁盘上消失。
struct TrashedProfile: Identifiable, Codable, Equatable {

    /// 直接用里面那份配置的 id：同一时刻回收站里不会有同一个配置的两份记录，
    /// 界面上的列表也就不用再造一层 id。
    var id: UUID { return profile.id }

    var profile: Profile
    /// 什么时候删的，用来算还剩几天。
    var deletedAt: Date

    init(profile: Profile, deletedAt: Date = Date()) {
        self.profile = profile
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case profile, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(Profile.self, forKey: .profile)
        // 缺 deletedAt（手工改过、或别的东西写进来的）就从现在开始算，
        // 而不是当成"很久以前删的"立刻清掉——这里是回收站，宁可多留一会儿。
        deletedAt = container.value(.deletedAt, default: Date())
    }

    /// 还剩几天被彻底删除，已过期为 0。
    func remainingDays(retentionDays: Int) -> Int {
        let deadline = deletedAt.addingTimeInterval(Double(retentionDays) * 86400)
        let seconds = deadline.timeIntervalSinceNow
        if seconds <= 0 { return 0 }
        return Int(ceil(seconds / 86400))
    }
}
