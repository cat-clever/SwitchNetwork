import Foundation

/// 本次运行里删掉的一条路由，供「撤回」用。
///
/// 刻意不落盘：路由是系统状态，重启之后那条被删的路由多半已经被系统重建了，
/// 把一份过期的删除记录读回界面只会误导人。所以只活在内存里。
struct DeletedRoute: Identifiable, Equatable {
    let id = UUID()
    let entry: RouteEntry
    let deletedAt: Date
    /// 撤回失败的原因。留在那一行上显示，不静默吞掉。
    var restoreFailure: String?

    var summary: String {
        return entry.summary
    }
}
