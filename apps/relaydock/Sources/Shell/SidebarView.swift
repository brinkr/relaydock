import SwiftUI

struct SidebarView: View {
    @Binding var selection: RelayDockSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: 52)

            VStack(alignment: .leading, spacing: 4) {
                SidebarGroupTitle("监控与工作流")

                SidebarButton(section: .runAndRecovery, selection: $selection)
                SidebarButton(section: .registry, selection: $selection)
                SidebarButton(section: .logsAndDiagnostics, selection: $selection)

                SidebarGroupTitle("系统")
                    .padding(.top, 18)

                SidebarButton(section: .preferences, selection: $selection)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()
        }
        .frame(width: 220)
        .background(RelayDockColor.sidebarBackground)
        .overlay(alignment: .trailing) {
            Divider()
                .opacity(0.55)
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
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
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
            HStack(spacing: 10) {
                Image(systemName: section.sidebarSystemImage)
                    .font(.system(size: 16, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? RelayDockColor.sidebarAccent : Color.secondary.opacity(0.78))
                    .frame(width: 18, alignment: .center)

                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 30)
            .padding(.horizontal, 10)
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
