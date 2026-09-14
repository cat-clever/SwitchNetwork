import SwiftUI

enum Theme {
    static let accent = Color.accentColor
    static let sectionLineWidth: CGFloat = 3
    static let cardCornerRadius: CGFloat = 10
    static let iconCornerRadius: CGFloat = 7
    static let iconSize: CGFloat = 28
    static let pagePadding: CGFloat = 24
    static let groupSpacing: CGFloat = 22
    static let warningColor = Color.orange
    static let dangerColor = Color.red
    static let successColor = Color.green
}

// MARK: - 分组标题（左侧蓝色竖线）

struct SectionGroup<Content: View>: View {
    let title: String
    var subtitle: String?
    let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.accent)
                .frame(width: Theme.sectionLineWidth)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                content()
            }
        }
    }
}

// MARK: - 卡片

struct Card<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct CardRowDivider: View {
    var body: some View {
        Divider().padding(.leading, Theme.iconSize + 26)
    }
}

// MARK: - 卡片式行：圆角图标 + 标题 + 灰色小字 + 右侧控件

struct CardRow<Control: View>: View {
    let icon: String
    var iconTint: Color = Theme.accent
    let title: String
    var subtitle: String?
    var titleAccessory: AnyView?
    var showsHover: Bool = true
    let control: () -> Control

    @State private var isHovering = false

    init(icon: String,
         iconTint: Color = Theme.accent,
         title: String,
         subtitle: String? = nil,
         titleAccessory: AnyView? = nil,
         showsHover: Bool = true,
         @ViewBuilder control: @escaping () -> Control) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.titleAccessory = titleAccessory
        self.showsHover = showsHover
        self.control = control
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.iconCornerRadius, style: .continuous)
                .fill(iconTint.opacity(0.15))
                .frame(width: Theme.iconSize, height: Theme.iconSize)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(iconTint)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let accessory = titleAccessory {
                        accessory
                    }
                }
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(showsHover && isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            if showsHover {
                isHovering = hovering
            }
        }
    }
}

extension CardRow where Control == EmptyView {
    init(icon: String,
         iconTint: Color = Theme.accent,
         title: String,
         subtitle: String? = nil,
         titleAccessory: AnyView? = nil,
         showsHover: Bool = true) {
        self.init(icon: icon,
                  iconTint: iconTint,
                  title: title,
                  subtitle: subtitle,
                  titleAccessory: titleAccessory,
                  showsHover: showsHover,
                  control: { EmptyView() })
    }
}

// MARK: - 小元件

struct StatusDot: View {
    let isOn: Bool
    var onColor: Color = Theme.successColor

    var body: some View {
        Circle()
            .fill(isOn ? onColor : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
    }
}

struct TagChip: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundColor(tint)
    }
}

/// 详情页里"标签 : 值"的一行。
struct DetailItem: View {
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(valueColor ?? Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minWidth: 92, alignment: .leading)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = Color.secondary
    /// 到了列表两端时把按钮压暗，而不是让它消失——位置固定，手就不用找。
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(disabled ? Color.secondary.opacity(0.35) : (isHovering ? tint : Color.secondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering && !disabled ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// 应用里所有设置行的开关都用 iOS 风格的圆形开关。
struct SwitchToggle: View {
    let isOn: Binding<Bool>
    var disabled: Bool = false

    var body: some View {
        Toggle("", isOn: isOn)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .disabled(disabled)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol = symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(disabled ? Color.secondary.opacity(0.2) : Theme.accent)
            )
            .foregroundColor(disabled ? Color.secondary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol = symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .foregroundColor(disabled ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// 可复制的命令行，用于安装 sudo 免密授权。
struct CopyableCommand: View {
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command)
                .font(.system(size: 10.5, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            HStack(spacing: 8) {
                SecondaryButton(title: copied ? L.t("已复制") : L.t("复制命令"), symbol: copied ? "checkmark" : "doc.on.doc") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                    copied = true
                }
                Text(L.t("在终端里执行，只需要做一次"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct EmptyHint: View {
    let text: String

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: Symbols.resolve("tray", fallback: "square.dashed"))
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 18)
            Spacer()
        }
    }
}
