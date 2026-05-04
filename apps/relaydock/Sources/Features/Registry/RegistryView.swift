import SwiftUI

struct RegistryView: View {
    let snapshot: RegistrySnapshotResult?
    @Binding var selectedHostId: String?
    let bridgeError: BridgeErrorInfo?
    let onRecoverRule: (String) -> Void
    let onRetryRule: (String) -> Void
    let onStopRule: (String) -> Void
    let onReload: () -> Void

    @State private var ruleQuery = ""
    @State private var activeSheet: RegistrySheet?

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
                RegistryHostDetail(
                    host: selectedHost,
                    ruleQuery: $ruleQuery,
                    onShowSheet: { activeSheet = $0 },
                    onRecoverRule: onRecoverRule,
                    onRetryRule: onRetryRule,
                    onStopRule: onStopRule
                )
            } else {
                EmptyRegistryState(onReload: onReload)
            }
        }
        .background(RelayDockColor.contentBackground)
        .sheet(item: $activeSheet) { sheet in
            RegistryPlaceholderSheet(sheet: sheet) {
                activeSheet = nil
            }
        }
    }

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("资源分组")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    activeSheet = .newHost
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
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
    @Binding var ruleQuery: String
    let onShowSheet: (RegistrySheet) -> Void
    let onRecoverRule: (String) -> Void
    let onRetryRule: (String) -> Void
    let onStopRule: (String) -> Void

    private var runningRules: [RegistryRule] {
        host.rules.filter { $0.runtimeState == .running }
    }

    private var filteredRules: [RegistryRule] {
        let normalizedQuery = ruleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return host.rules
        }

        return host.rules.filter { rule in
            rule.serviceName.localizedCaseInsensitiveContains(normalizedQuery)
                || rule.alias.localizedCaseInsensitiveContains(normalizedQuery)
                || rule.providerLabel.localizedCaseInsensitiveContains(normalizedQuery)
                || rule.portSummary.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RegistryHostHeader(
                host: host,
                onSettings: {
                    onShowSheet(.hostSettings(host))
                }
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RegistryPresetsSection(
                        presets: host.presets,
                        onNewPreset: {
                            onShowSheet(.newPreset(host))
                        }
                    )
                    RegistryRulesSection(
                        rules: filteredRules,
                        totalRuleCount: host.rules.count,
                        runningRules: runningRules,
                        ruleQuery: $ruleQuery,
                        onImportSSH: {
                            onShowSheet(.importSSH(host))
                        },
                        onNewRule: {
                            onShowSheet(.newRule(host))
                        },
                        onEditMapping: { rule in
                            onShowSheet(.editMapping(rule))
                        },
                        onEditRule: { rule in
                            onShowSheet(.editRule(rule))
                        },
                        onRecoverRule: onRecoverRule,
                        onRetryRule: onRetryRule,
                        onStopRule: onStopRule
                    )
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
    let onSettings: () -> Void

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
                onSettings()
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
    let onNewPreset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RegistrySectionHeader("启动预设")

                Spacer()

                Button {
                    onNewPreset()
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
    let totalRuleCount: Int
    let runningRules: [RegistryRule]
    @Binding var ruleQuery: String
    let onImportSSH: () -> Void
    let onNewRule: () -> Void
    let onEditMapping: (RegistryRule) -> Void
    let onEditRule: (RegistryRule) -> Void
    let onRecoverRule: (String) -> Void
    let onRetryRule: (String) -> Void
    let onStopRule: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                RegistrySectionHeader("规则清单")

                Spacer()

                RegistryRuleFilterField(text: $ruleQuery)
                    .frame(width: 180)

                Button {
                    onImportSSH()
                } label: {
                    Label("导入 SSH", systemImage: "terminal")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)

                Button {
                    onNewRule()
                } label: {
                    Label("新增规则", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            RegistrySubsectionTitle("运行中 \(runningRules.count) / 当前显示 \(rules.count) / 全部 \(totalRuleCount)")

            if rules.isEmpty {
                RegistryRulesEmptyState()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rules) { rule in
                        RegistryRuleRow(
                            rule: rule,
                            onEditMapping: onEditMapping,
                            onEditRule: onEditRule,
                            onRecoverRule: onRecoverRule,
                            onRetryRule: onRetryRule,
                            onStopRule: onStopRule
                        )
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
}

private struct RegistryRuleRow: View {
    let rule: RegistryRule
    let onEditMapping: (RegistryRule) -> Void
    let onEditRule: (RegistryRule) -> Void
    let onRecoverRule: (String) -> Void
    let onRetryRule: (String) -> Void
    let onStopRule: (String) -> Void

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

            Button("编辑映射") {
                onEditMapping(rule)
            }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
            Button("编辑规则") {
                onEditRule(rule)
            }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)

            if rule.runtimeState == .running {
                Button("停止", role: .destructive) {
                    onStopRule(rule.id)
                }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderless)
            } else if rule.runtimeState == .recoverable {
                Button("恢复") {
                    onRecoverRule(rule.id)
                }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderless)
            } else if rule.runtimeState == .error {
                Button("重试") {
                    onRetryRule(rule.id)
                }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct RegistryRuleFilterField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            TextField("筛选当前主机规则", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
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

private struct RegistryRulesEmptyState: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            Text("没有匹配的规则")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(RelayDockColor.controlBackground.opacity(0.42))
        }
    }
}

private enum RegistrySheet: Identifiable {
    case newHost
    case hostSettings(RegistryHost)
    case newPreset(RegistryHost)
    case importSSH(RegistryHost)
    case newRule(RegistryHost)
    case editMapping(RegistryRule)
    case editRule(RegistryRule)

    var id: String {
        switch self {
        case .newHost:
            "new-host"
        case let .hostSettings(host):
            "host-settings-\(host.id)"
        case let .newPreset(host):
            "new-preset-\(host.id)"
        case let .importSSH(host):
            "import-ssh-\(host.id)"
        case let .newRule(host):
            "new-rule-\(host.id)"
        case let .editMapping(rule):
            "edit-mapping-\(rule.id)"
        case let .editRule(rule):
            "edit-rule-\(rule.id)"
        }
    }

    var title: String {
        switch self {
        case .newHost:
            "新建资源分组"
        case .hostSettings:
            "主机设置"
        case .newPreset:
            "新建启动预设"
        case .importSSH:
            "导入 SSH 命令"
        case .newRule:
            "新增规则"
        case .editMapping:
            "编辑映射"
        case .editRule:
            "编辑规则"
        }
    }

    var subtitle: String {
        switch self {
        case .newHost:
            "后续会写入资源登记存储；当前 demo 先固定结构和入口。"
        case let .hostSettings(host), let .newPreset(host), let .importSSH(host), let .newRule(host):
            "\(host.name) · \(host.endpoint)"
        case let .editMapping(rule), let .editRule(rule):
            "\(rule.serviceName) · \(rule.alias)"
        }
    }

    var bodyText: String {
        switch self {
        case .newHost:
            "这里会承载主机名称、系统类型、入口地址和 provider target。"
        case .hostSettings:
            "这里会承载连接策略、保活参数、provider target 和主机标签。"
        case .newPreset:
            "这里会选择当前主机下的一组规则，并支持基础预设与局部覆盖。"
        case .importSSH:
            "这里会粘贴 ssh -L 命令，由 Rust core 解析成主机、target 和规则草稿。"
        case .newRule:
            "这里会填写服务名、别名、本地端口、远端地址和 provider target。"
        case .editMapping:
            "这里会调整端口映射；运行态的临时本地端口覆盖仍从运行页处理。"
        case .editRule:
            "这里会编辑配置规则本身，不直接操作当前运行实例。"
        }
    }
}

private struct RegistryPlaceholderSheet: View {
    let sheet: RegistrySheet
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(sheet.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(sheet.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(sheet.bodyText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("关闭", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
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
