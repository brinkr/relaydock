import SwiftUI

struct StatusBarView: View {
    let summary: StatusSummary

    var body: some View {
        HStack(spacing: 18) {
            StatusPill(
                title: "\(summary.connectedHosts) 个主机已连接",
                systemImage: "network",
                color: .green
            )

            StatusPill(
                title: "\(summary.runningForwards) 个转发正在运行",
                systemImage: "arrow.left.arrow.right",
                color: .blue
            )

            Spacer()

            if summary.issueCount > 0 {
                StatusPill(
                    title: "\(summary.issueCount) 处异常状态",
                    systemImage: "exclamationmark.triangle",
                    color: .red
                )
            } else {
                StatusPill(
                    title: summary.message,
                    systemImage: "checkmark.circle",
                    color: .secondary
                )
            }
        }
        .padding(.horizontal, 16)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .background(RelayDockColor.contentBackground)
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel(title)
    }
}
