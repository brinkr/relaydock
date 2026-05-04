import SwiftUI

struct RunAndRecoveryView: View {
    let snapshot: RunRecoverySnapshotResult?
    let isLoading: Bool
    let bridgeError: BridgeErrorInfo?
    let onRecover: (String) -> Void
    let onStop: (String) -> Void
    let onClear: (String) -> Void
    let onChangeLocalPort: (String) -> Void
    let onReload: () -> Void

    @State private var collapsedHostIds = Set<String>()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let bridgeError {
                    BridgeErrorBanner(error: bridgeError, onReload: onReload)
                }

                if isLoading && snapshot == nil {
                    LoadingRunRecoveryState()
                } else if let snapshot, !snapshot.hosts.isEmpty {
                    ForEach(snapshot.hosts) { host in
                        HostRuntimeGroup(
                            host: host,
                            isCollapsed: collapsedHostIds.contains(host.id),
                            onToggleCollapse: {
                                if collapsedHostIds.contains(host.id) {
                                    collapsedHostIds.remove(host.id)
                                } else {
                                    collapsedHostIds.insert(host.id)
                                }
                            },
                            onRecover: onRecover,
                            onStop: onStop,
                            onClear: onClear,
                            onChangeLocalPort: onChangeLocalPort
                        )
                    }
                } else {
                    EmptyRunRecoveryState(onReload: onReload)
                }
            }
        }
        .background(RelayDockColor.contentBackground)
    }
}

struct BridgeErrorBanner: View {
    let error: BridgeErrorInfo
    let onReload: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.summary)
                    .font(.system(size: 12, weight: .semibold))
                if let detail = error.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("重新读取", action: onReload)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

private struct LoadingRunRecoveryState: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在通过 bridge 读取运行与恢复状态")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(18)
    }
}

private struct EmptyRunRecoveryState: View {
    let onReload: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("没有运行或待恢复项目")
                .font(.system(size: 13, weight: .semibold))
            Button("重新读取", action: onReload)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct HostRuntimeGroup: View {
    let host: RunRecoveryHost
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onRecover: (String) -> Void
    let onStop: (String) -> Void
    let onClear: (String) -> Void
    let onChangeLocalPort: (String) -> Void

    private var runningCount: Int {
        host.rows.filter { $0.state != .recoverable }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16)

                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(host.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(host.endpoint) · 运行中 \(runningCount) 个 / 待恢复 \(host.rows.count - runningCount) 个")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(host.providerSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("恢复全部") {
                    host.rows
                        .filter { $0.state == .recoverable }
                        .forEach { onRecover($0.ruleId) }
                }
                .disabled(!host.rows.contains { $0.state == .recoverable })
                .font(.system(size: 11, weight: .medium))

                Button("停止运行中", role: .destructive) {
                    host.rows.compactMap(\.runtimeId).forEach(onStop)
                }
                .disabled(!host.rows.contains { $0.runtimeId != nil })
                .font(.system(size: 11, weight: .medium))

                Button("清空待恢复", role: .destructive) {
                    host.rows.compactMap(\.recoveryId).forEach(onClear)
                }
                .disabled(!host.rows.contains { $0.recoveryId != nil })
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(RelayDockColor.controlBackground.opacity(0.72))

                Divider()

            if !isCollapsed {
                ForEach(host.rows) { row in
                    RuntimeServiceRow(
                        row: row,
                        onRecover: onRecover,
                        onStop: onStop,
                        onClear: onClear,
                        onChangeLocalPort: onChangeLocalPort
                    )
                    Divider()
                }
            }
        }
    }
}

private struct RuntimeServiceRow: View {
    let row: RunRecoveryRow
    let onRecover: (String) -> Void
    let onStop: (String) -> Void
    let onClear: (String) -> Void
    let onChangeLocalPort: (String) -> Void

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

                Text(row.providerLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 118, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Text(row.portSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                    .padding(.leading, 30)

                Text(row.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 46, alignment: .leading)

                if let telemetry = row.telemetry, !telemetry.isEmpty {
                    Text(telemetry)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 108, alignment: .leading)
                }

                if let error = row.error {
                    Text(error.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(errorColor)
                        .lineLimit(1)
                }

                Spacer()

                ForEach(row.actions, id: \.action) { action in
                    Button(action.label, role: buttonRole(for: action.action)) {
                        perform(action.action)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(RelayDockColor.contentBackground)
    }

    private var statusColor: Color {
        switch row.state {
        case .connected:
            return .green
        case .reconnecting:
            return .orange
        case .error:
            return .red
        case .recoverable:
            return .secondary
        }
    }

    private var errorColor: Color {
        row.state == .recoverable ? .secondary : .red
    }

    private func buttonRole(for action: RunRecoveryActionKind) -> ButtonRole? {
        switch action {
        case .stop, .clear:
            return .destructive
        case .recover, .changeLocalPort:
            return nil
        }
    }

    private func perform(_ action: RunRecoveryActionKind) {
        switch action {
        case .recover:
            onRecover(row.ruleId)
        case .changeLocalPort:
            onChangeLocalPort(row.ruleId)
        case .stop:
            if let runtimeId = row.runtimeId {
                onStop(runtimeId)
            }
        case .clear:
            if let recoveryId = row.recoveryId {
                onClear(recoveryId)
            }
        }
    }
}

struct ServiceGlyph: View {
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
