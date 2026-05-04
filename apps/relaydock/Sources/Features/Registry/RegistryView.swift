import SwiftUI

struct RegistryView: View {
    let snapshot: RegistrySnapshotResult?
    @Binding var selectedHostId: String?
    let bridgeError: BridgeErrorInfo?
    let onReload: () -> Void

    private var selectedHost: RegistryHost? {
        guard let snapshot else { return nil }

        if let selectedHostId,
           let host = snapshot.hosts.first(where: { $0.id == selectedHostId }) {
            return host
        }

        return snapshot.hosts.first(where: { $0.id == snapshot.selectedHostId }) ?? snapshot.hosts.first
    }

    var body: some View {
        HStack(spacing: 0) {
            hostList

            Divider()

            if let bridgeError {
                BridgeErrorBanner(error: bridgeError, onReload: onReload)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(RelayDockColor.contentBackground)
            } else if let selectedHost {
                RegistryHostDetail(host: selectedHost)
            } else {
                EmptyRegistryState(onReload: onReload)
            }
        }
        .background(RelayDockColor.contentBackground)
    }

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("资源分组")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("新建资源分组")
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if let snapshot {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(snapshot.hosts) { host in
                            RegistryHostRow(
                                host: host,
                                selected: selectedHost?.id == host.id
                            ) {
                                selectedHostId = host.id
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取资源登记")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                Spacer()
            }
        }
        .frame(width: 260)
        .background(RelayDockColor.sidebarBackground.opacity(0.56))
    }
}

private struct EmptyRegistryState: View {
    let onReload: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("没有资源登记数据")
                .font(.system(size: 13, weight: .semibold))
            Button("重新读取", action: onReload)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RegistryHostRow: View {
    let host: RegistryHost
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: host.osHint.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(host.endpoint)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Circle()
                    .fill(host.status.color)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? RelayDockColor.sidebarSelection : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(host.name)
    }
}

private struct RegistryHostDetail: View {
    let host: RegistryHost

    private var runningRules: [RegistryRule] {
        host.rules.filter { $0.runtimeState == .running }
    }

    var body: some View {
        VStack(spacing: 0) {
            RegistryHostHeader(host: host)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RegistryPresetsSection(presets: host.presets)
                    RegistryRulesSection(rules: host.rules, runningRules: runningRules)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RelayDockColor.contentBackground)
    }
}

private struct RegistryHostHeader: View {
    let host: RegistryHost

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: host.osHint.systemImage)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(host.name)
                        .font(.system(size: 15, weight: .semibold))

                    Label(host.status.title, systemImage: "circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(host.status.color)
                }

                Text("\(host.endpoint)  |  可用入口: \(providerSummary)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
            } label: {
                Label("设置", systemImage: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RelayDockColor.contentBackground)
    }

    private var providerSummary: String {
        host.providerTargets.map(\.label).joined(separator: "   ")
    }
}

private struct RegistryPresetsSection: View {
    let presets: [RegistryPreset]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RegistrySectionHeader("启动预设")

                Spacer()

                Button {
                } label: {
                    Label("新建预设", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            LazyVStack(spacing: 8) {
                ForEach(presets) { preset in
                    RegistryPresetRow(preset: preset)
                }
            }
        }
    }
}

private struct RegistryPresetRow: View {
    let preset: RegistryPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(preset.name)
                    .font(.system(size: 12, weight: .semibold))

                if preset.derivedFrom != nil {
                    Text("派生")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(RelayDockColor.controlBackground)
                        }
                }

                Spacer()
            }

            ForEach(preset.rules, id: \.serviceName) { rule in
                HStack(spacing: 6) {
                    Text(rule.serviceName)
                        .font(.system(size: 11))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(rule.targetLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(RelayDockColor.controlBackground.opacity(0.56))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
        }
    }
}

private struct RegistryRulesSection: View {
    let rules: [RegistryRule]
    let runningRules: [RegistryRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                RegistrySectionHeader("规则清单")

                Spacer()

                RegistryFilterPlaceholder()
                    .frame(width: 180)

                Button {
                } label: {
                    Label("导入 SSH", systemImage: "terminal")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)

                Button {
                } label: {
                    Label("新增规则", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            RegistrySubsectionTitle("运行中 (\(runningRules.count))")

            LazyVStack(spacing: 0) {
                ForEach(rules) { rule in
                    RegistryRuleRow(rule: rule)
                    Divider()
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(RelayDockColor.contentBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
            }
        }
    }
}

private struct RegistryRuleRow: View {
    let rule: RegistryRule

    var body: some View {
        HStack(spacing: 10) {
            ServiceGlyph(name: rule.serviceName)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(rule.serviceName)
                        .font(.system(size: 12, weight: .semibold))

                    Text(rule.alias)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("本地 \(rule.portSummary)  |  链路: \(rule.providerLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Label(rule.runtimeState.title, systemImage: "circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(rule.runtimeState.color)
                .frame(width: 68, alignment: .leading)

            Button("编辑映射") {}
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
            Button("编辑规则") {}
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)

            if rule.runtimeState == .running {
                Button("停止", role: .destructive) {}
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderless)
            } else if rule.runtimeState == .recoverable {
                Button("立即重试") {}
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct RegistryFilterPlaceholder: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("筛选当前主机规则")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(RelayDockColor.controlBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
        }
    }
}

private struct RegistrySectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.none)
    }
}

private struct RegistrySubsectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.green)
    }
}

private extension RegistryHostStatus {
    var title: String {
        switch self {
        case .online:
            "在线"
        case .offline:
            "离线"
        }
    }

    var color: Color {
        switch self {
        case .online:
            .green
        case .offline:
            .secondary
        }
    }
}

private extension RegistryHostOsHint {
    var systemImage: String {
        switch self {
        case .macos:
            "desktopcomputer"
        case .ubuntu:
            "server.rack"
        case .windows:
            "display"
        case .linux:
            "cpu"
        case .raspberryPi:
            "memorychip"
        }
    }
}

private extension RegistryRuleRuntimeState {
    var title: String {
        switch self {
        case .running:
            "运行中"
        case .recoverable:
            "待恢复"
        case .stopped:
            "已停止"
        case .error:
            "异常"
        }
    }

    var color: Color {
        switch self {
        case .running:
            .green
        case .recoverable:
            .secondary
        case .stopped:
            .secondary
        case .error:
            .red
        }
    }
}
