import SwiftUI
import AppKit

struct LogViewerView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var log = Log.shared
    @State private var filter: LogFilter = .all
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleEntries.isEmpty {
                Spacer()
                EmptyHint(text: log.entries.isEmpty ? L.t("还没有日志") : L.t("没有符合筛选条件的日志"))
                Spacer()
            } else {
                entryList
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(isPresented: $isConfirmingClear) {
            Alert(title: Text(L.t("清空日志")),
                  message: Text(L.t("会同时清空界面上的记录和日志文件内容，确定吗？")),
                  primaryButton: .destructive(Text(L.t("清空"))) {
                      log.clear()
                      Log.shared.info(L.t("日志已清空"))
                  },
                  secondaryButton: .cancel(Text(L.t("取消"))))
        }
    }

    // MARK: - 分段

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: Symbols.resolve("list.bullet.rectangle", fallback: "list.bullet"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.accent)
            Text(L.t("运行日志"))
                .font(.system(size: 14, weight: .semibold))

            Picker("", selection: $filter) {
                ForEach(LogFilter.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .frame(width: 260)

            Spacer()

            Text(L.t("%d / %d 条", visibleEntries.count, log.entries.count))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleEntries) { entry in
                    LogEntryRow(entry: entry)
                    Divider().padding(.leading, 18)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            SecondaryButton(title: L.t("在访达中显示日志文件"), symbol: "arrow.up.forward.app") {
                NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
            }
            SecondaryButton(title: L.t("清空"), symbol: "trash", disabled: log.entries.isEmpty) {
                isConfirmingClear = true
            }
            Spacer()
            PrimaryButton(title: L.t("关闭"), symbol: "xmark") {
                isPresented = false
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var visibleEntries: [Log.Entry] {
        // 最新的排在前面，排查问题时不用滚到底。
        let filtered: [Log.Entry]
        switch filter {
        case .all:
            filtered = log.entries
        case .problemOnly:
            filtered = log.entries.filter { $0.level == .warning || $0.level == .error }
        case .errorOnly:
            filtered = log.entries.filter { $0.level == .error }
        }
        return filtered.reversed()
    }
}

private enum LogFilter: String, CaseIterable, Identifiable {
    case all
    case problemOnly
    case errorOnly

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .all: return L.t("全部")
        case .problemOnly: return L.t("警告与错误")
        case .errorOnly: return L.t("只看错误")
        }
    }
}

private struct LogEntryRow: View {
    let entry: Log.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(timestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(entry.level.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }

    private var tint: Color {
        switch entry.level {
        case .info: return Color.secondary
        case .success: return Theme.successColor
        case .warning: return Theme.warningColor
        case .error: return Theme.dangerColor
        }
    }

    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: entry.date)
    }
}
