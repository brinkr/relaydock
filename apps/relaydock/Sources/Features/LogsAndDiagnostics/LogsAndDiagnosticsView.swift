import SwiftUI

struct LogsAndDiagnosticsView: View {
    var body: some View {
        PlaceholderPane(
            title: "日志与诊断",
            subtitle: "后续承载 provider 日志、保活事件、端口冲突诊断和结构化排障结果。"
        ) {
            VStack(alignment: .leading, spacing: 7) {
                LogLine(level: "INFO", message: "RelayDock shell 已启动")
                LogLine(level: "INFO", message: "等待 Rust core runtime 快照")
                LogLine(level: "WARN", message: "SSH provider 尚未接入")
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
            }
        }
    }
}

private struct LogLine: View {
    let level: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Text(level)
                .foregroundStyle(level == "WARN" ? .orange : .secondary)
                .frame(width: 42, alignment: .leading)
            Text(message)
                .foregroundStyle(.primary)
        }
    }
}
