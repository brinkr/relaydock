import SwiftUI

struct RunAndRecoveryView: View {
    let snapshot: RunRecoverySnapshotResult?
    let isLoading: Bool
    let bridgeError: BridgeErrorInfo?
    let collapseCommand: RunRecoveryCollapseCommand?
    let onRecover: (String) -> Void
    let onRetry: (String) -> Void
    let onStop: (String) -> Void
    let onClear: (String) -> Void
    let onChangeLocalPort: (String, UInt16) -> Void
    let onReload: () -> Void

    @State private var collapsedHostIds = Set<String>()
    @State private var localPortDraft: LocalPortOverrideDraft?

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
                            onRetry: onRetry,
                            onStop: onStop,
                            onClear: onClear,
                            onChangeLocalPort: { row in
                                localPortDraft = LocalPortOverrideDraft(row: row)
                            }
                        )
                    }
                } else {
                    EmptyRunRecoveryState(onReload: onReload)
                }
            }
        }
        .background(RelayDockColor.contentBackground)
        .onChange(of: collapseCommand) { _, command in
            guard let command, let snapshot else {
                return
            }

            switch command.kind {
            case .collapseAll:
                collapsedHostIds = Set(snapshot.hosts.map(\.id))
            case .expandAll:
                collapsedHostIds.removeAll()
            }
        }
        .sheet(item: $localPortDraft) { draft in
            LocalPortOverrideSheet(
                draft: draft,
                onCancel: {
                    localPortDraft = nil
                },
                onApply: { localPort in
                    onChangeLocalPort(draft.row.ruleId, localPort)
                    localPortDraft = nil
                }
            )
        }
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
    let onRetry: (String) -> Void
    let onStop: (String) -> Void
    let onClear: (String) -> Void
    let onChangeLocalPort: (RunRecoveryRow) -> Void

    private var runningCount: Int {
        host.rows.filter { $0.state != .recoverable }.count
    }

    private var recoverableCount: Int {
        host.rows.count - runningCount
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
                .frame(width: 16, height: 20)
                .accessibilityLabel(isCollapsed ? "展开主机" : "折叠主机")

                Image(systemName: "desktopcomputer")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(host.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(host.endpoint) · 运行中 \(runningCount) 个 / 待恢复 \(recoverableCount) 个")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(host.providerSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 134, alignment: .trailing)

                HStack(spacing: 8) {
                    Button("恢复全部") {
                        host.rows
                            .filter { $0.state == .recoverable }
                            .forEach { onRecover($0.ruleId) }
                    }
                    .disabled(!host.rows.contains { $0.state == .recoverable })

                    Divider()
                        .frame(height: 16)

                    Button("停止运行中", role: .destructive) {
                        host.rows.compactMap(\.runtimeId).forEach(onStop)
                    }
                    .disabled(!host.rows.contains { $0.runtimeId != nil })

                    Button("清空待恢复", role: .destructive) {
                        host.rows.compactMap(\.recoveryId).forEach(onClear)
                    }
                    .disabled(!host.rows.contains { $0.recoveryId != nil })
                }
                .font(.system(size: 11, weight: .medium))
                .frame(width: 232, alignment: .trailing)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(RelayDockColor.groupHeaderBackground)

            Divider()

            if !isCollapsed {
                ForEach(host.rows) { row in
                    RuntimeServiceRow(
                        row: row,
                        onRecover: onRecover,
                        onRetry: onRetry,
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
    let onRetry: (String) -> Void
    let onStop: (String) -> Void
    let onClear: (String) -> Void
    let onChangeLocalPort: (RunRecoveryRow) -> Void

    private enum Metrics {
        static let contentIndent: CGFloat = 30
        static let portWidth: CGFloat = 112
        static let statusWidth: CGFloat = 74
        static let telemetryWidth: CGFloat = 116
        static let providerWidth: CGFloat = 126
        static let actionWidth: CGFloat = 172
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ServiceGlyph(name: row.serviceName)

                Text(row.serviceName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(row.alias)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text(row.providerLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Metrics.providerWidth, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Text(row.portSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Metrics.portWidth, alignment: .leading)

                Text(row.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .frame(width: Metrics.statusWidth, alignment: .leading)

                if let telemetry = row.telemetry, !telemetry.isEmpty {
                    Text(telemetry)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: Metrics.telemetryWidth, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: Metrics.telemetryWidth, height: 1)
                }

                if let error = row.error {
                    Text(error.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(errorColor)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(row.actions, id: \.action) { action in
                        Button(action.label, role: buttonRole(for: action.action)) {
                            perform(action.action)
                        }
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .frame(width: Metrics.actionWidth, alignment: .trailing)
            }
            .padding(.leading, Metrics.contentIndent)
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
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
        case .recover, .retry, .changeLocalPort:
            return nil
        }
    }

    private func perform(_ action: RunRecoveryActionKind) {
        switch action {
        case .recover:
            onRecover(row.ruleId)
        case .retry:
            if let runtimeId = row.runtimeId {
                onRetry(runtimeId)
            }
        case .changeLocalPort:
            onChangeLocalPort(row)
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

private struct LocalPortOverrideDraft: Identifiable {
    let id: String
    let row: RunRecoveryRow
    var localPortText: String

    init(row: RunRecoveryRow) {
        self.id = row.ruleId
        self.row = row
        self.localPortText = row.portSummary.firstPortText ?? ""
    }
}

private struct LocalPortOverrideSheet: View {
    @State private var localPortText: String

    let draft: LocalPortOverrideDraft
    let onCancel: () -> Void
    let onApply: (UInt16) -> Void

    init(
        draft: LocalPortOverrideDraft,
        onCancel: @escaping () -> Void,
        onApply: @escaping (UInt16) -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onApply = onApply
        _localPortText = State(initialValue: draft.localPortText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("改本地端口")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(draft.row.serviceName) · \(draft.row.alias)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("本地端口")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 64, alignment: .leading)
                TextField("例如 15432", text: $localPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            Text("当前会用临时端口恢复运行，不写回资源登记规则。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("应用并恢复") {
                    guard let localPort = UInt16(localPortText) else {
                        return
                    }
                    onApply(localPort)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(UInt16(localPortText) == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private extension String {
    var firstPortText: String? {
        split(whereSeparator: { !$0.isNumber }).first.map(String.init)
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
