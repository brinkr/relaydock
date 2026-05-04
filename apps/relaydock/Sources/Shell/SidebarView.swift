import SwiftUI

struct SidebarView: View {
    @Binding var selection: RelayDockSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: 14)

            SidebarGroupTitle("监控与工作流")

            SidebarButton(section: .runAndRecovery, selection: $selection)
            SidebarButton(section: .registry, selection: $selection)
            SidebarButton(section: .logsAndDiagnostics, selection: $selection)

            SidebarGroupTitle("系统")
                .padding(.top, 18)

            SidebarButton(section: .preferences, selection: $selection)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 220)
        .background(RelayDockColor.sidebarBackground)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}

private struct SidebarGroupTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
    }
}

private struct SidebarButton: View {
    let section: RelayDockSection
    @Binding var selection: RelayDockSection

    private var isSelected: Bool {
        selection == section
    }

    var body: some View {
        Button {
            selection = section
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? RelayDockColor.sidebarSelection : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
    }
}
