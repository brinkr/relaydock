import SwiftUI

struct RelayDockShellView: View {
    @ObservedObject var viewModel: RelayDockShellViewModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $viewModel.selection)

            VStack(spacing: 0) {
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
        .task {
            viewModel.loadRunRecoverySnapshot()
            viewModel.loadRegistrySnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .relayDockToolbarAction)) { notification in
            guard let rawValue = notification.object as? String,
                  let action = RelayDockToolbarAction(rawValue: rawValue) else {
                return
            }

            handleToolbarAction(action)
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
                    viewModel.recoverDemoRule(ruleId: ruleId)
                },
                onRetry: { runtimeId in
                    viewModel.retryDemoRuntime(runtimeId: runtimeId)
                },
                onStop: { runtimeId in
                    viewModel.stopDemoRuntime(runtimeId: runtimeId)
                },
                onClear: { recoveryId in
                    viewModel.clearDemoRecoveryItem(recoveryId: recoveryId)
                },
                onChangeLocalPort: { ruleId, localPort in
                    viewModel.applyDemoLocalPortOverride(ruleId: ruleId, localPort: localPort)
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
                onSaveHost: { draft in
                    try viewModel.saveRegistryHost(draft)
                },
                onSaveRule: { draft in
                    try viewModel.saveRegistryRule(draft)
                },
                onRecoverRule: { ruleId in
                    viewModel.recoverDemoRule(ruleId: ruleId)
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

private extension RelayDockShellView {
    func handleToolbarAction(_ action: RelayDockToolbarAction) {
        switch action {
        case .recheck:
            viewModel.reloadCurrentSection()
        case .collapseAll:
            viewModel.collapseAllRunRecoveryHosts()
        case .stopAll:
            viewModel.stopAllRunningDemoRuntimes()
        case .clearRecovery:
            viewModel.clearAllDemoRecoveryItems()
        }
    }
}
