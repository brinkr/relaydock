import SwiftUI

struct SidebarView: View {
    @Binding var selection: RelayDockSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: 10)

            SidebarGroupTitle("监控与工作流")

            SidebarButton(section: .runAndRecovery, selection: $selection)
            SidebarButton(section: .registry, selection: $selection)
            SidebarButton(section: .logsAndDiagnostics, selection: $selection)

            SidebarGroupTitle("系统")
                .padding(.top, 14)

            SidebarButton(section: .preferences, selection: $selection)

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 212)
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
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.bottom, 5)
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
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18, alignment: .center)

                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 24)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? RelayDockColor.sidebarSelection : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }
}
