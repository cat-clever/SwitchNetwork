import SwiftUI

/// 回收站。删除的配置先落在这里，过了保留期才真的从磁盘上消失。
/// 空的时候整块不出现，不占地方。
struct TrashSection: View {
    @EnvironmentObject private var state: AppState

    @State private var pendingAction: TrashAction?

    /// 彻底删除和清空回收站都要二次确认，但同一个视图上挂两个 alert 会被后一个顶掉，
    /// 所以合成一个待办动作。
    private enum TrashAction: Identifiable {
        case purge(TrashedProfile)
        case emptyAll

        var id: String {
            switch self {
            case .purge(let item): return item.id.uuidString
            case .emptyAll: return "empty"
            }
        }
    }

    var body: some View {
        if state.trash.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        SectionGroup(title: L.t("回收站"),
                     subtitle: L.t("删除的配置先放在这里，超过 %d 天才真的从磁盘上删掉",
                                   state.settings.trashRetentionDays)) {
            VStack(spacing: 10) {
                ForEach(state.trash) { item in
                    row(for: item)
                }
                HStack {
                    Text(L.t("共 %d 份", state.trash.count))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    SecondaryButton(title: L.t("清空回收站"), symbol: "trash.slash") {
                        pendingAction = .emptyAll
                    }
                }
            }
        }
        .alert(item: $pendingAction) { action in
            switch action {
            case .purge(let item):
                return Alert(title: Text(L.t("彻底删除")),
                             message: Text(L.t("确定要彻底删除「%@」吗？这一步不能撤销。", item.profile.name)),
                             primaryButton: .destructive(Text(L.t("彻底删除"))) {
                                 state.purgeFromTrash(id: item.id)
                             },
                             secondaryButton: .cancel(Text(L.t("取消"))))
            case .emptyAll:
                return Alert(title: Text(L.t("清空回收站")),
                             message: Text(L.t("会彻底删除里面全部 %d 份配置，此操作不能撤销。", state.trash.count)),
                             primaryButton: .destructive(Text(L.t("清空"))) {
                                 state.emptyTrash()
                             },
                             secondaryButton: .cancel(Text(L.t("取消"))))
            }
        }
        .onAppear {
            // 打开回收站时顺手清一次过期的，省得看到一堆早该消失的。
            state.purgeExpiredTrash()
        }
    }

    private func row(for item: TrashedProfile) -> some View {
        Card {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Theme.iconCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: Theme.iconSize, height: Theme.iconSize)
                    .overlay(
                        Image(systemName: Symbols.resolve("trash", fallback: "trash"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.profile.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(summary(for: item))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                SecondaryButton(title: L.t("还原"), symbol: "arrow.uturn.backward") {
                    state.restoreFromTrash(id: item.id)
                }
                IconButton(symbol: "trash.slash",
                           help: L.t("彻底删除，不再恢复"),
                           tint: Theme.dangerColor) {
                    pendingAction = .purge(item)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func summary(for item: TrashedProfile) -> String {
        var parts = [item.profile.interfaceDisplayName, item.profile.ipSummary]
        let days = item.remainingDays(retentionDays: state.settings.trashRetentionDays)
        if days > 0 {
            parts.append(L.t("还剩 %d 天", days))
        } else {
            parts.append(L.t("已过期，马上清理"))
        }
        return parts.joined(separator: " · ")
    }
}
