import SwiftUI

struct RunAndRecoveryView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HostRuntimeGroup(
                    hostName: "Mac mini · 家",
                    endpoint: "admin@192.168.1.5",
                    providerSummary: "SSH · 家庭宽带",
                    rows: [
                        RuntimeRow(
                            serviceName: "React 前端",
                            alias: "react.home.localhost",
                            portSummary: "3000",
                            status: "运行中",
                            telemetry: "6h 12m · 2ms · 0次",
                            actions: ["停止"]
                        ),
                        RuntimeRow(
                            serviceName: "PostgreSQL Main",
                            alias: "pg.home.localhost",
                            portSummary: "5432",
                            status: "待恢复",
                            telemetry: "",
                            actions: ["恢复", "改本地端口", "清除"]
                        )
                    ]
                )
            }
        }
        .background(RelayDockColor.contentBackground)
    }
}

private struct HostRuntimeGroup: View {
    let hostName: String
    let endpoint: String
    let providerSummary: String
    let rows: [RuntimeRow]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(hostName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(endpoint) · 运行集包含 \(rows.count) 个转发")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(providerSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("恢复全部") {}
                    .font(.system(size: 11, weight: .medium))
                Button("停止运行中", role: .destructive) {}
                    .font(.system(size: 11, weight: .medium))
                Button("清空待恢复", role: .destructive) {}
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(RelayDockColor.controlBackground.opacity(0.72))

            Divider()

            ForEach(rows) { row in
                RuntimeServiceRow(row: row)
                Divider()
            }
        }
    }
}

private struct RuntimeRow: Identifiable {
    let id = UUID()
    let serviceName: String
    let alias: String
    let portSummary: String
    let status: String
    let telemetry: String
    let actions: [String]
}

private struct RuntimeServiceRow: View {
    let row: RuntimeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                ServiceGlyph(name: row.serviceName)

                Text(row.serviceName)
                    .font(.system(size: 13, weight: .medium))

                Text(row.alias)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("SSH · 家庭宽带")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Text(row.portSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)

                Text(row.status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(row.status == "运行中" ? .green : .secondary)

                if !row.telemetry.isEmpty {
                    Text(row.telemetry)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ForEach(row.actions, id: \.self) { action in
                    Button(action, role: action == "停止" || action == "清除" ? .destructive : nil) {}
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(RelayDockColor.contentBackground)
    }
}

private struct ServiceGlyph: View {
    let name: String

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(RelayDockColor.controlBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
