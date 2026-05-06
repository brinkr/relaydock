import SwiftUI

struct RelayDockShellView: View {
    @ObservedObject var viewModel: RelayDockShellViewModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $viewModel.selection)

            VStack(spacing: 0) {
                ShellTopBar(
                    section: viewModel.selection,
                    onReload: {
                        viewModel.reloadCurrentSection()
                    },
                    onCollapseAll: {
                        viewModel.collapseAllRunRecoveryHosts()
                    },
                    onStopAll: {
                        viewModel.stopAllRunningRuntimes()
                    },
                    onClearRecovery: {
                        viewModel.clearAllRecoveryItems()
                    },
                    onNewHost: {
                        viewModel.registryCommand = RegistryShellCommand(kind: .newHost)
                    }
                )
                .frame(height: 52)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RelayDockColor.contentBackground)

                Divider()

                StatusBarView(summary: viewModel.statusSummary)
                    .frame(height: 28)
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(RelayDockColor.windowBackground)
        .ignoresSafeArea(.container, edges: .top)
        .task {
            viewModel.loadRunRecoverySnapshot()
            viewModel.loadRegistrySnapshot()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selection {
        case .runAndRecovery:
            RunAndRecoveryView(
                snapshot: viewModel.runRecoverySnapshot,
                isLoading: viewModel.isLoadingRunRecovery,
                bridgeError: viewModel.runRecoveryError,
                collapseCommand: viewModel.runRecoveryCollapseCommand,
                onRecover: { ruleId in
                    viewModel.recoverItem(ruleId: ruleId)
                },
                onRetry: { runtimeId in
                    viewModel.retryRuntimeInstance(runtimeId: runtimeId)
                },
                onStop: { runtimeId in
                    viewModel.stopRuntimeInstance(runtimeId: runtimeId)
                },
                onClear: { recoveryId in
                    viewModel.clearRecoveryItem(recoveryId: recoveryId)
                },
                onChangeLocalPort: { ruleId, localPort in
                    viewModel.applyLocalPortOverride(ruleId: ruleId, localPort: localPort)
                },
                onReload: {
                    viewModel.loadRunRecoverySnapshot()
                }
            )
        case .registry:
            RegistryView(
                snapshot: viewModel.registrySnapshot,
                selectedHostId: $viewModel.selectedRegistryHostId,
                bridgeError: viewModel.registryError,
                shellCommand: viewModel.registryCommand,
                onSaveHost: { draft in
                    try viewModel.saveRegistryHost(draft)
                },
                onParseSshCommand: { commandText in
                    try viewModel.parseSshCommand(commandText)
                },
                onSaveRule: { draft in
                    try viewModel.saveRegistryRule(draft)
                },
                onRecoverRule: { ruleId in
                    viewModel.startRule(ruleId: ruleId)
                    viewModel.selection = .runAndRecovery
                },
                onRetryRule: { ruleId in
                    viewModel.retryRuntimeForRule(ruleId)
                    viewModel.selection = .runAndRecovery
                },
                onStopRule: { ruleId in
                    viewModel.stopRuntimeForRule(ruleId)
                    viewModel.selection = .runAndRecovery
                },
                onReload: {
                    viewModel.loadRegistrySnapshot()
                }
            )
        case .logsAndDiagnostics:
            LogsAndDiagnosticsView(
                runRecoverySnapshot: viewModel.runRecoverySnapshot,
                registrySnapshot: viewModel.registrySnapshot,
                runRecoveryError: viewModel.runRecoveryError,
                registryError: viewModel.registryError,
                bridgeExecutablePath: viewModel.bridgeExecutablePath,
                isBridgeAvailable: viewModel.isBridgeAvailable,
                onReload: {
                    viewModel.reloadDiagnosticsWorkspace()
                }
            )
        case .preferences:
            PreferencesView(
                runRecoverySnapshot: viewModel.runRecoverySnapshot,
                registrySnapshot: viewModel.registrySnapshot,
                runRecoveryError: viewModel.runRecoveryError,
                registryError: viewModel.registryError,
                bridgeExecutablePath: viewModel.bridgeExecutablePath,
                isBridgeAvailable: viewModel.isBridgeAvailable,
                onReload: {
                    viewModel.reloadDiagnosticsWorkspace()
                }
            )
        }
    }
}

private struct ShellTopBar: View {
    let section: RelayDockSection
    let onReload: () -> Void
    let onCollapseAll: () -> Void
    let onStopAll: () -> Void
    let onClearRecovery: () -> Void
    let onNewHost: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: section.topBarSystemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 16)

            if section.showsSearch {
                ShellSearchField()
                    .frame(width: 300)
            }

            HStack(spacing: 4) {
                switch section {
                case .runAndRecovery:
                    ToolbarTextButton("重新检查", systemImage: "arrow.clockwise", action: onReload)
                    ToolbarTextButton("全部折叠", systemImage: nil, action: onCollapseAll)
                    ToolbarTextButton("停止全部运行", systemImage: "stop.fill", role: .destructive, action: onStopAll)
                    ToolbarTextButton("清空恢复列表", systemImage: "xmark.circle", role: .destructive, action: onClearRecovery)
                case .registry:
                    ToolbarTextButton("重新读取", systemImage: "arrow.clockwise", action: onReload)
                    ToolbarTextButton("新主机", systemImage: "plus", prominence: .primary, action: onNewHost)
                case .logsAndDiagnostics:
                    ToolbarTextButton("重新读取", systemImage: "arrow.clockwise", action: onReload)
                    ToolbarTextButton("筛选", systemImage: "line.3.horizontal.decrease.circle", action: {})
                case .preferences:
                    ToolbarTextButton("重新读取", systemImage: "arrow.clockwise", action: onReload)
                }
            }
            .controlSize(.small)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .background(RelayDockColor.topBarBackground)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.6)
        }
    }
}

private struct ShellSearchField: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            Text("搜索主机 / 服务 / 别名")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(RelayDockColor.controlBackground.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(RelayDockColor.subtleBorder.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct ToolbarTextButton: View {
    enum Prominence {
        case plain
        case primary
    }

    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let prominence: Prominence
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String?,
        role: ButtonRole? = nil,
        prominence: Prominence = .plain,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.prominence = prominence
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, prominence == .primary ? 10 : 7)
            .frame(height: 26)
            .foregroundStyle(foregroundStyle)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderStyle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var foregroundStyle: Color {
        if prominence == .primary {
            return .white
        }

        return role == .destructive ? .red : .secondary
    }

    private var backgroundStyle: Color {
        if prominence == .primary {
            return RelayDockColor.sidebarAccent
        }

        return role == .destructive ? Color.red.opacity(0.001) : Color.clear
    }

    private var borderStyle: Color {
        if prominence == .primary {
            return Color.clear
        }

        return role == .destructive ? Color.red.opacity(0.001) : Color.clear
    }
}

private extension RelayDockSection {
    var showsSearch: Bool {
        self != .preferences
    }
}
