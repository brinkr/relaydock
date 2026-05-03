import SwiftUI

struct RelayDockShellView: View {
    @ObservedObject var viewModel: RelayDockShellViewModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $viewModel.selection)

            VStack(spacing: 0) {
                ToolbarView(selection: viewModel.selection)
                    .frame(height: 52)

                Divider()

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
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selection {
        case .runAndRecovery:
            RunAndRecoveryView()
        case .registry:
            RegistryView()
        case .logsAndDiagnostics:
            LogsAndDiagnosticsView()
        case .preferences:
            PreferencesView()
        }
    }
}
