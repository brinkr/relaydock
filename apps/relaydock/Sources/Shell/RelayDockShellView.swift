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
                onRecover: { ruleId in
                    viewModel.recoverDemoRule(ruleId: ruleId)
                },
                onStop: { runtimeId in
                    viewModel.stopDemoRuntime(runtimeId: runtimeId)
                },
                onClear: { recoveryId in
                    viewModel.clearDemoRecoveryItem(recoveryId: recoveryId)
                },
                onChangeLocalPort: { ruleId in
                    viewModel.changeLocalPortForDemoRule(ruleId: ruleId)
                },
                onReload: {
                    viewModel.loadRunRecoverySnapshot()
                }
            )
        case .registry:
            RegistryView()
        case .logsAndDiagnostics:
            LogsAndDiagnosticsView()
        case .preferences:
            PreferencesView()
        }
    }
}
