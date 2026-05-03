import SwiftUI

struct ToolbarView: View {
    let selection: RelayDockSection

    var body: some View {
        HStack(spacing: 12) {
            Label(selection.title, systemImage: selection.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if selection != .preferences {
                SearchFieldPlaceholder()
                    .frame(width: 300)
            }

            toolbarActions
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var toolbarActions: some View {
        switch selection {
        case .runAndRecovery:
            ToolbarButton("重新检查", systemImage: "arrow.clockwise")
            ToolbarButton("全部折叠", systemImage: "rectangle.compress.vertical")
            ToolbarButton("停止全部运行", systemImage: "stop.fill", role: .destructive)
            ToolbarButton("清空恢复列表", systemImage: "xmark.circle", role: .destructive)
        case .registry:
            ToolbarButton("导入 SSH", systemImage: "terminal")
            ToolbarButton("新增规则", systemImage: "plus")
        case .logsAndDiagnostics:
            ToolbarButton("筛选", systemImage: "line.3.horizontal.decrease.circle")
        case .preferences:
            EmptyView()
        }
    }
}

private struct SearchFieldPlaceholder: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)

            Text("搜索主机 / 服务 / 别名")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(RelayDockColor.controlBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .accessibilityLabel("搜索主机、服务或别名")
    }
}

private struct ToolbarButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?

    init(_ title: String, systemImage: String, role: ButtonRole? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
    }

    var body: some View {
        Button(role: role) {} label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }
}
