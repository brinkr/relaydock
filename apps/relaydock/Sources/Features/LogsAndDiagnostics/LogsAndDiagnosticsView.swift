import SwiftUI

struct LogsAndDiagnosticsView: View {
    let runRecoverySnapshot: RunRecoverySnapshotResult?
    let registrySnapshot: RegistrySnapshotResult?
    let runRecoveryError: BridgeErrorInfo?
    let registryError: BridgeErrorInfo?
    let bridgeExecutablePath: String?
    let isBridgeAvailable: Bool
    let onReload: () -> Void

    @State private var selectedScope: DiagnosticScope = .recent

    private var entries: [DiagnosticEntry] {
        DiagnosticEntry.build(
            runRecoverySnapshot: runRecoverySnapshot,
            registrySnapshot: registrySnapshot,
            runRecoveryError: runRecoveryError,
            registryError: registryError,
            bridgeExecutablePath: bridgeExecutablePath,
            isBridgeAvailable: isBridgeAvailable
        )
    }

    private var visibleEntries: [DiagnosticEntry] {
        switch selectedScope {
        case .recent:
            return entries
        case .issues:
            return entries.filter { $0.scope == .issues || $0.level == .warning || $0.level == .error }
        case .bridge:
            return entries.filter { $0.scope == .bridge || $0.component == "bridge.sidecar" }
        case .checks:
            return entries.filter { $0.scope == .checks }
        }
    }

    private var checks: [DiagnosticCheckItem] {
        DiagnosticCheckItem.build(
            runRecoverySnapshot: runRecoverySnapshot,
            registrySnapshot: registrySnapshot,
            runRecoveryError: runRecoveryError,
            registryError: registryError,
            bridgeExecutablePath: bridgeExecutablePath,
            isBridgeAvailable: isBridgeAvailable
        )
    }

    private var recoverableRows: [RunRecoveryRow] {
        runRecoverySnapshot?.hosts
            .flatMap(\.rows)
            .filter { $0.state == .recoverable }
            .sorted { $0.serviceName < $1.serviceName } ?? []
    }

    private var issueRows: [RunRecoveryRow] {
        runRecoverySnapshot?.hosts
            .flatMap(\.rows)
            .filter { $0.state == .error || $0.state == .reconnecting }
            .sorted { lhs, rhs in
                lhs.serviceName < rhs.serviceName
            } ?? []
    }

    private var refreshedAtText: String {
        let refreshedAt = max(
            runRecoverySnapshot?.refreshedAtEpochSeconds ?? 0,
            registrySnapshot?.refreshedAtEpochSeconds ?? 0
        )

        guard refreshedAt > 0 else {
            return "等待 bridge 快照"
        }

        return "最近刷新 \(DateFormatter.relayDockConsole.string(from: Date(timeIntervalSince1970: TimeInterval(refreshedAt))))"
    }

    var body: some View {
        HStack(spacing: 0) {
            scopeSidebar
                .frame(width: 180)

            Divider()

            workspace

            Divider()

            inspector
                .frame(width: 288)
        }
        .background(RelayDockColor.contentBackground)
    }

    private var scopeSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("诊断范围")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 7)

            ForEach(DiagnosticScope.allCases) { scope in
                Button {
                    selectedScope = scope
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: scope.systemImage)
                            .font(.system(size: 12))
                            .foregroundStyle(selectedScope == scope ? .primary : .secondary)
                            .frame(width: 16, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(scope.title)
                                .font(.system(size: 12, weight: selectedScope == scope ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(scope.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 8)

                        Text("\(count(for: scope))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 26, alignment: .trailing)
                    }
                    .frame(height: 34)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selectedScope == scope ? RelayDockColor.sidebarSelection : Color.clear)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(scope.title)，\(count(for: scope)) 条")
                .accessibilityValue(selectedScope == scope ? "已选择" : "未选择")
                .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text("当前上下文")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(contextSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .background(RelayDockColor.sidebarBackground)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedScope.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(visibleEntries.count) 条结构化诊断线索，来自当前运行 / 恢复 / 资源快照")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(refreshedAtText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("重新检查", action: onReload)
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            if visibleEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("当前范围没有可展示的诊断线索")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            DiagnosticConsoleRow(entry: entry)
                            Divider()
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 18) {
                ConsoleFooterMetric(
                    title: "异常运行",
                    value: "\(issueRows.count)",
                    color: issueRows.isEmpty ? .secondary : .orange
                )
                ConsoleFooterMetric(
                    title: "待恢复",
                    value: "\(recoverableRows.count)",
                    color: recoverableRows.isEmpty ? .secondary : .blue
                )
                ConsoleFooterMetric(
                    title: "Bridge",
                    value: isBridgeAvailable ? "已接入" : "缺失",
                    color: isBridgeAvailable ? .green : .red
                )

                Spacer()

                if let action = runRecoverySnapshot?.lastAction {
                    Text(action.message)
                        .font(.system(size: 11))
                        .foregroundStyle(action.ok ? Color.secondary : .red)
                        .lineLimit(1)
                } else {
                    Text("控制台保持与当前 snapshot 同步，不额外发明诊断状态机。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(RelayDockColor.controlBackground)
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            inspectorSectionHeader("检查项")
                .padding(.top, 14)

            ForEach(checks) { item in
                DiagnosticCheckRow(item: item)
                Divider()
            }

            inspectorSectionHeader("待恢复动作")

            if recoverableRows.isEmpty {
                InspectorEmptyState(text: "当前没有待恢复条目")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recoverableRows.prefix(6)) { row in
                            InspectorRecoveryRow(row: row)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            inspectorSectionHeader("Bridge / 快照")

            VStack(alignment: .leading, spacing: 7) {
                InspectorKeyValueRow(title: "sidecar", value: isBridgeAvailable ? "已接入" : "未找到")
                InspectorKeyValueRow(title: "路径", value: bridgeExecutablePath ?? "等待开发环境 sidecar")
                InspectorKeyValueRow(
                    title: "运行数据",
                    value: runRecoverySnapshot == nil ? "未读取" : "\(runRecoverySnapshot?.summary.runningForwards ?? 0) 个运行态条目"
                )
                InspectorKeyValueRow(
                    title: "资源数据",
                    value: registrySnapshot == nil ? "未读取" : "\(registrySnapshot?.hosts.count ?? 0) 个主机"
                )

                if let runRecoveryError {
                    Text(runRecoveryError.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let registryError {
                    Text(registryError.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("诊断控制台只消费当前 snapshot，后续真实 provider 日志会在 bridge 稳定后接进来。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Spacer(minLength: 0)
        }
        .background(RelayDockColor.controlBackground)
    }

    private var contextSummary: String {
        let hostCount = registrySnapshot?.hosts.count ?? 0
        let runningCount = runRecoverySnapshot?.summary.runningForwards ?? 0
        return "\(hostCount) 个主机，\(runningCount) 个运行态条目。"
    }

    private func count(for scope: DiagnosticScope) -> Int {
        switch scope {
        case .recent:
            return entries.count
        case .issues:
            return entries.filter { $0.scope == .issues || $0.level == .warning || $0.level == .error }.count
        case .bridge:
            return entries.filter { $0.scope == .bridge || $0.component == "bridge.sidecar" }.count
        case .checks:
            return checks.count
        }
    }

    private func inspectorSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private enum DiagnosticScope: String, CaseIterable, Identifiable {
    case recent
    case issues
    case bridge
    case checks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            "近期事件"
        case .issues:
            "异常与恢复"
        case .bridge:
            "Bridge / Sidecar"
        case .checks:
            "检查项"
        }
    }

    var subtitle: String {
        switch self {
        case .recent:
            "最近刷新的结构化事件"
        case .issues:
            "重连、异常、待恢复"
        case .bridge:
            "sidecar 与 snapshot 边界"
        case .checks:
            "当前可判定的检查结果"
        }
    }

    var systemImage: String {
        switch self {
        case .recent:
            "clock.arrow.circlepath"
        case .issues:
            "exclamationmark.triangle"
        case .bridge:
            "point.3.connected.trianglepath.dotted"
        case .checks:
            "checklist"
        }
    }
}

private struct DiagnosticEntry: Identifiable {
    let id: String
    let scope: DiagnosticScope
    let level: DiagnosticLevel
    let timestamp: String
    let component: String
    let summary: String
    let detail: String?

    static func build(
        runRecoverySnapshot: RunRecoverySnapshotResult?,
        registrySnapshot: RegistrySnapshotResult?,
        runRecoveryError: BridgeErrorInfo?,
        registryError: BridgeErrorInfo?,
        bridgeExecutablePath: String?,
        isBridgeAvailable: Bool
    ) -> [DiagnosticEntry] {
        let baseEpoch = max(
            runRecoverySnapshot?.refreshedAtEpochSeconds ?? 0,
            registrySnapshot?.refreshedAtEpochSeconds ?? 0
        )
        var minuteOffset = 0
        var items: [DiagnosticEntry] = []

        func nextTimestamp() -> String {
            defer { minuteOffset += 1 }

            guard baseEpoch > 0 else {
                return "--:--:--"
            }

            let date = Date(timeIntervalSince1970: TimeInterval(baseEpoch - UInt64(minuteOffset * 60)))
            return DateFormatter.relayDockConsole.string(from: date)
        }

        if let action = runRecoverySnapshot?.lastAction {
            items.append(
                DiagnosticEntry(
                    id: "last-action",
                    scope: action.ok ? .recent : .issues,
                    level: action.ok ? .notice : .error,
                    timestamp: nextTimestamp(),
                    component: "recovery.action",
                    summary: action.message,
                    detail: action.error?.detail
                )
            )
        }

        if let runtimeEvents = runRecoverySnapshot?.events {
            items.append(
                contentsOf: runtimeEvents.map { event in
                    DiagnosticEntry(
                        id: "runtime-event-\(event.id)",
                        scope: event.level.diagnosticScope,
                        level: event.level.diagnosticLevel,
                        timestamp: DiagnosticEntry.formatTimestamp(event.occurredAtEpochSeconds),
                        component: event.component,
                        summary: event.summary,
                        detail: event.detail ?? DiagnosticEntry.eventContext(for: event)
                    )
                }
            )
        }

        items.append(
            DiagnosticEntry(
                id: "bridge-sidecar",
                scope: .bridge,
                level: isBridgeAvailable ? .info : .error,
                timestamp: nextTimestamp(),
                component: "bridge.sidecar",
                summary: isBridgeAvailable ? "已连接 RelayDock bridge sidecar" : "未找到 RelayDock bridge sidecar",
                detail: bridgeExecutablePath
            )
        )

        if let runRecoverySnapshot {
            items.append(
                DiagnosticEntry(
                    id: "runtime-snapshot",
                    scope: .checks,
                    level: runRecoverySnapshot.summary.issueCount > 0 ? .warning : .info,
                    timestamp: nextTimestamp(),
                    component: "runtime.snapshot",
                    summary: "读取到 \(runRecoverySnapshot.summary.runningForwards) 个运行态条目 / \(runRecoverySnapshot.summary.recoverableCount) 个待恢复条目",
                    detail: runRecoverySnapshot.summary.message
                )
            )

            for host in runRecoverySnapshot.hosts {
                let issueCount = host.rows.filter { $0.state == .error || $0.state == .reconnecting }.count
                let recoverableCount = host.rows.filter { $0.state == .recoverable }.count
                items.append(
                    DiagnosticEntry(
                        id: "host-\(host.id)",
                        scope: issueCount > 0 || recoverableCount > 0 ? .issues : .recent,
                        level: issueCount > 0 ? .warning : .info,
                        timestamp: nextTimestamp(),
                        component: "runtime.host",
                        summary: "\(host.name) 当前有 \(issueCount) 条异常 / \(recoverableCount) 条待恢复",
                        detail: "\(host.endpoint) · \(host.providerSummary)"
                    )
                )

                for row in host.rows where row.state != .connected {
                    items.append(
                        DiagnosticEntry(
                            id: row.id,
                            scope: .issues,
                            level: row.level,
                            timestamp: nextTimestamp(),
                            component: row.state.componentName,
                            summary: "\(row.serviceName) · \(row.statusText)",
                            detail: row.error?.summary ?? row.telemetry ?? row.portSummary
                        )
                    )
                }
            }
        } else if let runRecoveryError {
            items.append(
                DiagnosticEntry(
                    id: "runtime-error",
                    scope: .issues,
                    level: .error,
                    timestamp: nextTimestamp(),
                    component: "runtime.snapshot",
                    summary: runRecoveryError.summary,
                    detail: runRecoveryError.detail
                )
            )
        }

        if let registrySnapshot {
            let offlineCount = registrySnapshot.hosts.filter { $0.status == .offline }.count
            let providerCount = registrySnapshot.hosts.flatMap(\.providerTargets).count
            items.append(
                DiagnosticEntry(
                    id: "registry-snapshot",
                    scope: .checks,
                    level: offlineCount > 0 ? .warning : .info,
                    timestamp: nextTimestamp(),
                    component: "registry.snapshot",
                    summary: "读取到 \(registrySnapshot.hosts.count) 个资源主机 / \(providerCount) 个 provider target",
                    detail: offlineCount > 0 ? "\(offlineCount) 个主机离线" : "资源快照结构完整"
                )
            )
        } else if let registryError {
            items.append(
                DiagnosticEntry(
                    id: "registry-error",
                    scope: .issues,
                    level: .error,
                    timestamp: nextTimestamp(),
                    component: "registry.snapshot",
                    summary: registryError.summary,
                    detail: registryError.detail
                )
            )
        }

        return items
    }

    private static func formatTimestamp(_ epochSeconds: UInt64) -> String {
        guard epochSeconds > 0 else {
            return "--:--:--"
        }

        return DateFormatter.relayDockConsole.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    private static func eventContext(for event: RunRecoveryEvent) -> String? {
        [
            event.hostId.map { "host=\($0)" },
            event.ruleId.map { "rule=\($0)" },
            event.runtimeId.map { "runtime=\($0)" },
            event.providerTargetId.map { "target=\($0)" },
            event.kind.isEmpty ? nil : "kind=\(event.kind)",
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .diagnosticNilIfEmpty
    }
}

private extension String {
    var diagnosticNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum DiagnosticLevel {
    case info
    case notice
    case warning
    case error

    var title: String {
        switch self {
        case .info:
            "INFO"
        case .notice:
            "NOTE"
        case .warning:
            "WARN"
        case .error:
            "ERR "
        }
    }

    var color: Color {
        switch self {
        case .info:
            return .secondary
        case .notice:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private extension RunRecoveryEventLevel {
    var diagnosticLevel: DiagnosticLevel {
        switch self {
        case .info:
            return .info
        case .notice:
            return .notice
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }

    var diagnosticScope: DiagnosticScope {
        switch self {
        case .warning, .error:
            return .issues
        case .info, .notice:
            return .recent
        }
    }
}

private struct DiagnosticConsoleRow: View {
    let entry: DiagnosticEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.timestamp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 68, alignment: .leading)

                Text(entry.level.title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(entry.level.color)
                    .lineLimit(1)
                    .frame(width: 38, alignment: .leading)

                Text(entry.component)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 118, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summary)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
    }
}

private struct DiagnosticCheckItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let status: DiagnosticCheckStatus

    static func build(
        runRecoverySnapshot: RunRecoverySnapshotResult?,
        registrySnapshot: RegistrySnapshotResult?,
        runRecoveryError: BridgeErrorInfo?,
        registryError: BridgeErrorInfo?,
        bridgeExecutablePath: String?,
        isBridgeAvailable: Bool
    ) -> [DiagnosticCheckItem] {
        let issueCount = runRecoverySnapshot?.summary.issueCount ?? 0
        let recoverableCount = runRecoverySnapshot?.summary.recoverableCount ?? 0
        let providerTargets = registrySnapshot?.hosts.flatMap(\.providerTargets) ?? []
        let offlineCount = registrySnapshot?.hosts.filter { $0.status == .offline }.count ?? 0

        return [
            DiagnosticCheckItem(
                id: "bridge",
                title: "Bridge sidecar",
                value: isBridgeAvailable ? "已接入" : "缺失",
                detail: bridgeExecutablePath ?? "等待 target/debug/relaydock-bridge",
                status: isBridgeAvailable ? .pass : .fail
            ),
            DiagnosticCheckItem(
                id: "runtime",
                title: "运行快照",
                value: runRecoverySnapshot == nil ? "未读取" : "已读取",
                detail: runRecoveryError?.summary ?? (runRecoverySnapshot?.summary.message ?? "等待 bridge 返回运行态"),
                status: runRecoverySnapshot == nil ? .warn : .pass
            ),
            DiagnosticCheckItem(
                id: "registry",
                title: "资源快照",
                value: registrySnapshot == nil ? "未读取" : "已读取",
                detail: registryError?.summary ?? (registrySnapshot == nil ? "等待 bridge 返回资源态" : "主机 \(registrySnapshot?.hosts.count ?? 0) 个"),
                status: registrySnapshot == nil ? .warn : .pass
            ),
            DiagnosticCheckItem(
                id: "issues",
                title: "异常运行实例",
                value: "\(issueCount) 条",
                detail: issueCount == 0 ? "当前没有 error / reconnecting 项" : "需要重试或处理 provider / 端口异常",
                status: issueCount == 0 ? .pass : .warn
            ),
            DiagnosticCheckItem(
                id: "recovery",
                title: "恢复集合",
                value: "\(recoverableCount) 条",
                detail: recoverableCount == 0 ? "没有待恢复项" : "支持恢复 / 改本地端口 / 清除",
                status: recoverableCount == 0 ? .info : .warn
            ),
            DiagnosticCheckItem(
                id: "providers",
                title: "Provider 覆盖",
                value: "\(providerTargets.count) 个 target",
                detail: providerTargets.isEmpty ? "当前未读取 provider target" : providerTargets.map(\.label).joined(separator: " · "),
                status: providerTargets.isEmpty ? .warn : .info
            ),
            DiagnosticCheckItem(
                id: "offline",
                title: "离线主机",
                value: "\(offlineCount) 个",
                detail: offlineCount == 0 ? "当前资源分组全部在线" : "需要在资源登记或 provider 检查中复核",
                status: offlineCount == 0 ? .pass : .warn
            ),
        ]
    }
}

private enum DiagnosticCheckStatus {
    case pass
    case warn
    case fail
    case info

    var title: String {
        switch self {
        case .pass:
            "通过"
        case .warn:
            "关注"
        case .fail:
            "失败"
        case .info:
            "说明"
        }
    }

    var color: Color {
        switch self {
        case .pass:
            return .green
        case .warn:
            return .orange
        case .fail:
            return .red
        case .info:
            return .secondary
        }
    }
}

private struct DiagnosticCheckRow: View {
    let item: DiagnosticCheckItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(item.value)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 82, alignment: .trailing)
                Text(item.status.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.status.color)
                    .lineLimit(1)
                    .frame(width: 28, alignment: .trailing)
            }

            Text(item.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct InspectorRecoveryRow: View {
    let row: RunRecoveryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(row.serviceName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(row.providerLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text("\(row.alias) · \(row.portSummary)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(row.actions.map(\.label).joined(separator: " / "))
                .font(.system(size: 10))
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct InspectorKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

private struct InspectorEmptyState: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ConsoleFooterMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

private extension RunRecoveryRow {
    var level: DiagnosticLevel {
        switch state {
        case .connected:
            return .info
        case .reconnecting:
            return .warning
        case .error:
            return .error
        case .recoverable:
            return .notice
        }
    }
}

private extension RunRecoveryRowState {
    var componentName: String {
        switch self {
        case .connected:
            "runtime.connected"
        case .reconnecting:
            "runtime.retry"
        case .error:
            "runtime.error"
        case .recoverable:
            "runtime.recovery"
        }
    }
}

private extension DateFormatter {
    static let relayDockConsole: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
