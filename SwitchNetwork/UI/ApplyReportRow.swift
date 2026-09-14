import SwiftUI

/// 展示一次「应用配置」的逐项结果。
/// 自动应用不弹窗，用户就是靠这里和日志知道"到底为什么没生效"。
struct ApplyReportRow: View {
    let report: ApplyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: report.hasFailure
                      ? Symbols.resolve("xmark.circle.fill", fallback: "xmark.circle")
                      : Symbols.resolve("checkmark.circle.fill", fallback: "checkmark.circle"))
                    .font(.system(size: 12))
                    .foregroundColor(report.hasFailure ? Theme.dangerColor : Theme.successColor)
                Text(report.summary)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            ForEach(report.steps) { step in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(color(for: step.outcome))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    Text(L.t("%@：%@", step.title, step.detail))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func color(for outcome: StepOutcome) -> Color {
        switch outcome {
        case .success: return Theme.successColor
        case .warning: return Theme.warningColor
        case .failure: return Theme.dangerColor
        }
    }
}

/// 路由检查结果的一行。
struct RouteCheckRow: View {
    let result: RouteCheckResult

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 12))
                .foregroundColor(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.route.summary)
                    .font(.system(size: 12, weight: .medium))
                Text(result.status.label)
                    .font(.system(size: 11))
                    .foregroundColor(result.status.isProblem ? tint : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var symbolName: String {
        switch result.status {
        case .ok:
            return Symbols.resolve("checkmark.circle.fill", fallback: "checkmark.circle")
        case .missing:
            return Symbols.resolve("plus.circle.fill", fallback: "plus.circle")
        case .wrongGateway, .maskMismatch:
            return Symbols.resolve("arrow.triangle.2.circlepath", fallback: "arrow.clockwise")
        case .connectedConflict:
            return Symbols.resolve("exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
        case .notChecked:
            return Symbols.resolve("questionmark.circle", fallback: "circle")
        }
    }

    private var tint: Color {
        switch result.status {
        case .ok: return Theme.successColor
        case .missing: return Theme.warningColor
        case .wrongGateway, .maskMismatch: return Theme.warningColor
        case .connectedConflict: return Theme.dangerColor
        case .notChecked: return Color.secondary
        }
    }
}
