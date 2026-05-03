import SwiftUI

struct RegistryView: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("资源分组")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)

                RegistryHostRow(name: "Mac mini · 家", subtitle: "admin@192.168.1.5", selected: true)
                RegistryHostRow(name: "Ubuntu Dev Server", subtitle: "root@10.0.0.12", selected: false)

                Spacer()
            }
            .frame(width: 260)
            .background(RelayDockColor.sidebarBackground.opacity(0.55))

            Divider()

            PlaceholderPane(
                title: "Mac mini · 家",
                subtitle: "当前主机详情、连接策略摘要、规则清单和 SSH 命令导入入口。"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("启动预设")
                    Text("日常开发 · 4 个规则")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    SectionHeader("规则清单")
                    RegistryRuleRow(name: "React 前端", alias: "react.home.localhost", port: "3000")
                    RegistryRuleRow(name: "PostgreSQL Main", alias: "pg.home.localhost", port: "5432")
                }
            }
        }
    }
}

private struct RegistryHostRow: View {
    let name: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? RelayDockColor.sidebarSelection : Color.clear)
    }
}

private struct RegistryRuleRow: View {
    let name: String
    let alias: String
    let port: String

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .medium))
            Text(alias)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(port)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
