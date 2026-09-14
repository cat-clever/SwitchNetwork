import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case overview
    case profiles
    case automation
    case settings

    var id: String { return rawValue }

    var title: String {
        switch self {
        case .overview: return L.t("接口概览")
        case .profiles: return L.t("配置管理")
        case .automation: return L.t("自动化规则")
        case .settings: return L.t("设置")
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return Symbols.resolve("rectangle.grid.2x2", fallback: "square.grid.2x2")
        case .profiles: return Symbols.resolve("list.bullet.rectangle", fallback: "list.bullet")
        case .automation: return Symbols.resolve("bolt.circle", fallback: "bolt")
        case .settings: return Symbols.resolve("gearshape", fallback: "gear")
        }
    }

    /// 搜索框只在会列出配置的页面出现。
    var supportsSearch: Bool {
        return self == .overview || self == .profiles
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var state: AppState

    @State private var section: MainSection = .overview
    @State private var searchText = ""
    @State private var isShowingLog = false

    var body: some View {
        VStack(spacing: 0) {
            TopNavBar(section: $section, searchText: $searchText)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.groupSpacing) {
                    if let warning = state.storageWarning {
                        StorageWarningBanner(reason: warning)
                    }
                    content
                }
                .padding(Theme.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // 语言一变就让下面的内容整棵树重建，所有 L.t 重新取词。
        // .id 放在 .sheet 里面，换语言时不会把已经打开的日志窗口一起拆掉。
        .id(state.resolvedLanguage)
        .frame(minWidth: 940, minHeight: 660)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $isShowingLog) {
            LogViewerView(isPresented: $isShowingLog)
                .environmentObject(state)
        }
        .sheet(item: $state.pendingMigration) { prompt in
            MigrationPromptView(prompt: prompt)
                .environmentObject(state)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            InterfaceOverviewView(searchText: searchText)
        case .profiles:
            ProfileManagerView(searchText: searchText)
        case .automation:
            AutomationView(onNavigateToProfiles: { section = .profiles })
        case .settings:
            SettingsView(showLog: { isShowingLog = true })
        }
    }
}

/// 云端文件还没下载完时的横幅。告诉用户「不是坏了，是暂时不写」，
/// 顺带给一个重试按钮，不用为此重启应用。
private struct StorageWarningBanner: View {
    @EnvironmentObject private var state: AppState

    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Symbols.resolve("exclamationmark.triangle.fill",
                                              fallback: "exclamationmark.triangle"))
                .font(.system(size: 12))
                .foregroundColor(Theme.warningColor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("配置还在云端，本次运行暂时只读"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L.t("%@，这期间不会写回云端，免得把云端已有的配置覆盖成空白。", reason))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            SecondaryButton(title: L.t("重试"), symbol: "arrow.clockwise") {
                state.retryCloudLoad()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.warningColor.opacity(0.12))
        )
    }
}

/// 第一次发现「本机有配置、iCloud 还是空的」时问一次。
/// 只问不搬：点了才导入，本机那份始终留着。
private struct MigrationPromptView: View {
    @EnvironmentObject private var state: AppState

    let prompt: AppState.MigrationPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: Symbols.resolve("icloud.and.arrow.up", fallback: "icloud"))
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
                Text(L.t("把本机配置导入 iCloud"))
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(L.t("检测到本机有 %d 份配置，iCloud 里还是空的。导入后这几台 Mac 就能共用同一份配置。",
                     prompt.count))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            Text(prompt.sourcePath)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            Text(L.t("本机那份会保留作备份，不会删掉。"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                SecondaryButton(title: L.t("不用了，以后不再提示")) {
                    state.declineMigration()
                }
                PrimaryButton(title: L.t("导入 iCloud"), symbol: "icloud.and.arrow.up") {
                    state.importLocalProfilesToCloud()
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct TopNavBar: View {
    @Binding var section: MainSection
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: Symbols.resolve("arrow.triangle.swap", fallback: "network"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent)
                    )
                Text("SwitchNetwork")
                    .font(.system(size: 14, weight: .semibold))
            }

            HStack(spacing: 3) {
                ForEach(MainSection.allCases) { item in
                    SectionTab(item: item, isSelected: item == section) {
                        section = item
                    }
                }
            }

            Spacer(minLength: 8)

            if section.supportsSearch {
                SearchField(text: $searchText)
            }

            Button(action: { section = .settings }) {
                Image(systemName: Symbols.resolve("gearshape", fallback: "gear"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(L.t("打开设置"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct SectionTab: View {
    let item: MainSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 11, weight: .medium))
                Text(item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fillColor)
            )
            .foregroundColor(isSelected ? Theme.accent : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var fillColor: Color {
        if isSelected { return Theme.accent.opacity(0.15) }
        if isHovering { return Color.primary.opacity(0.06) }
        return Color.clear
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: Symbols.resolve("magnifyingglass"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField(L.t("搜索配置"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 140)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: Symbols.resolve("xmark.circle.fill", fallback: "xmark.circle"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
