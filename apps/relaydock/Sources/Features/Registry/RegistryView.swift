import SwiftUI
#if os(macOS)
import AppKit
#endif

private enum RegistryStyle {
    static let hostListBackground = RelayDockColor.sidebarBackground.opacity(0.82)
    static let workSurface = Color(red: 0.980, green: 0.980, blue: 0.980)
    static let cardBackground = Color.white
    static let cardBorder = Color.black.opacity(0.055)
    static let shallowDivider = Color.black.opacity(0.055)
    static let toolbarBackground = RelayDockColor.controlBackground.opacity(0.72)
}

struct RegistryView: View {
    let snapshot: RegistrySnapshotResult?
    @Binding var selectedHostId: String?
    let bridgeError: BridgeErrorInfo?
    let shellCommand: RegistryShellCommand?
    let onSaveHost: (RegistryHostDraft) throws -> RegistrySnapshotResult
    let onParseSshCommand: (String) throws -> ParseSshCommandResult
    let onTestProviderTargetConnectivity: (String, UInt16) throws -> ProviderTargetConnectivityResult
    let onSaveRule: (RegistryRuleDraft) throws -> RegistrySnapshotResult
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

            Rectangle()
                .fill(RegistryStyle.shallowDivider)
                .frame(width: 1)

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
            RegistrySheetView(
                sheet: sheet,
                hosts: snapshot?.hosts ?? [],
                onSaveHost: onSaveHost,
                onParseSshCommand: onParseSshCommand,
                onTestProviderTargetConnectivity: onTestProviderTargetConnectivity,
                onSaveRule: onSaveRule
            ) {
                activeSheet = nil
            }
        }
        .onChange(of: shellCommand) { _, command in
            guard command?.kind == .newHost else {
                return
            }

            activeSheet = .newHost
        }
    }

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("资源分组")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
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
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if let snapshot {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(snapshot.hosts) { host in
                            RegistryHostRow(
                                host: host,
                                selected: selectedHost?.id == host.id
                            ) {
                                selectedHostId = host.id
                            }
                        }
                    }
                    .padding(.horizontal, 10)
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
        .frame(width: 252)
        .background(RegistryStyle.hostListBackground)
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
            HStack(spacing: 9) {
                ZStack {
                    Image(systemName: host.osHint.systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? RelayDockColor.sidebarAccent : .secondary)
                }
                .frame(width: 16)

                VStack(alignment: .leading, spacing: 0) {
                    Text(host.name)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Circle()
                    .fill(host.status.color)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? RelayDockColor.sidebarSelection : Color.clear)
            }
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(RelayDockColor.sidebarAccent)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(host.name), \(host.endpoint)")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
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
                            onShowSheet(.editMapping(host, rule))
                        },
                        onEditRule: { rule in
                            onShowSheet(.editRule(host, rule))
                        },
                        onRecoverRule: onRecoverRule,
                        onRetryRule: onRetryRule,
                        onStopRule: onStopRule
                    )
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .background(RegistryStyle.workSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RegistryStyle.workSurface)
    }
}

private struct RegistryHostHeader: View {
    let host: RegistryHost
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: host.osHint.systemImage)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)

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
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(RelayDockColor.contentBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RegistryStyle.shallowDivider)
                .frame(height: 1)
        }
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
            .padding(.horizontal, 2)

            if presets.isEmpty {
                Text("没有配置启动预设")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(.horizontal, 2)
                    .padding(.top, 1)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(presets) { preset in
                        RegistryPresetRow(preset: preset)
                    }
                }
                .padding(.top, 1)
            }
        }
    }
}

private struct RegistryPresetRow: View {
    let preset: RegistryPreset

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(preset.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if preset.derivedFrom != nil {
                        Text("派生")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(RelayDockColor.controlBackground.opacity(0.72))
                            }
                    }
                }

                if preset.rules.isEmpty {
                    Text("没有规则")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(preset.rules.enumerated()), id: \.offset) { _, rule in
                            HStack(spacing: 5) {
                                Text(rule.serviceName)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 138, alignment: .leading)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.tertiary)

                                Text(rule.targetLabel)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 160, alignment: .leading)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RegistryRuleGroup: Identifiable {
    let kind: RegistryRuleGroupKind
    let rules: [RegistryRule]

    var id: String {
        kind.id
    }

    var title: String {
        kind.title
    }

    var tint: Color {
        kind.color
    }
}

private enum RegistryRuleGroupKind: Identifiable {
    case forwarded(RegistryRuleRuntimeState)
    case direct
    case local

    var id: String {
        switch self {
        case let .forwarded(state):
            "forwarded-\(state.rawValue)"
        case .direct:
            "direct"
        case .local:
            "local"
        }
    }

    var title: String {
        switch self {
        case let .forwarded(state):
            state.groupTitle
        case .direct:
            "直达应用"
        case .local:
            "本机应用"
        }
    }

    var color: Color {
        switch self {
        case let .forwarded(state):
            state.color
        case .direct:
            .blue
        case .local:
            .green
        }
    }

    func contains(_ rule: RegistryRule) -> Bool {
        switch self {
        case let .forwarded(state):
            rule.accessMode == .forwarded && rule.runtimeState == state
        case .direct:
            rule.accessMode == .direct
        case .local:
            rule.accessMode == .local
        }
    }

    static var displayOrder: [RegistryRuleGroupKind] {
        [.forwarded(.running), .direct, .local, .forwarded(.recoverable), .forwarded(.error), .forwarded(.stopped)]
    }
}

private struct RegistryRuleGroupCard: View {
    let group: RegistryRuleGroup
    let onEditMapping: (RegistryRule) -> Void
    let onEditRule: (RegistryRule) -> Void
    let onRecoverRule: (String) -> Void
    let onRetryRule: (String) -> Void
    let onStopRule: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(group.tint)
                    .frame(width: 5, height: 5)

                Text("\(group.title) \(group.rules.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(RegistryStyle.shallowDivider)
                    .frame(height: 1)
            }

            ForEach(Array(group.rules.enumerated()), id: \.element.id) { index, rule in
                RegistryRuleRow(
                    rule: rule,
                    onEditMapping: onEditMapping,
                    onEditRule: onEditRule,
                    onRecoverRule: onRecoverRule,
                    onRetryRule: onRetryRule,
                    onStopRule: onStopRule
                )

                if index < group.rules.count - 1 {
                    Rectangle()
                        .fill(RegistryStyle.shallowDivider)
                        .frame(height: 1)
                        .padding(.leading, 38)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(RegistryStyle.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(RegistryStyle.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.018), radius: 2, x: 0, y: 1)
    }
}

private struct RegistryRuleToolbar: View {
    @Binding var ruleQuery: String
    let onImportSSH: () -> Void
    let onNewRule: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RegistryRuleFilterField(text: $ruleQuery)
                .frame(width: 164)

            toolbarDivider

            Button {
                onImportSSH()
            } label: {
                Label("导入 SSH", systemImage: "terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 7)

            toolbarDivider

            Button {
                onNewRule()
            } label: {
                Label("新增规则", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 7)
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(RegistryStyle.toolbarBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(RegistryStyle.cardBorder, lineWidth: 1)
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(RegistryStyle.shallowDivider)
            .frame(width: 1, height: 15)
            .padding(.horizontal, 4)
    }
}

private struct RegistryRuleSummaryLine: View {
    let runningCount: Int
    let visibleCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("运行中 \(runningCount)")
            Text("/")
                .foregroundStyle(.tertiary)
            Text("当前显示 \(visibleCount)")
            Text("/")
                .foregroundStyle(.tertiary)
            Text("全部 \(totalCount)")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
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

    private var ruleGroups: [RegistryRuleGroup] {
        RegistryRuleGroupKind.displayOrder.compactMap { kind in
            let groupRules = rules.filter { kind.contains($0) }
            guard !groupRules.isEmpty else {
                return nil
            }

            return RegistryRuleGroup(kind: kind, rules: groupRules)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RegistrySectionHeader("规则清单")

                Spacer()

                RegistryRuleToolbar(
                    ruleQuery: $ruleQuery,
                    onImportSSH: onImportSSH,
                    onNewRule: onNewRule
                )
            }
            .padding(.horizontal, 2)

            RegistryRuleSummaryLine(
                runningCount: runningRules.count,
                visibleCount: rules.count,
                totalCount: totalRuleCount
            )

            if rules.isEmpty {
                RegistryRulesEmptyState()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(ruleGroups) { group in
                        RegistryRuleGroupCard(
                            group: group,
                            onEditMapping: onEditMapping,
                            onEditRule: onEditRule,
                            onRecoverRule: onRecoverRule,
                            onRetryRule: onRetryRule,
                            onStopRule: onStopRule
                        )
                    }
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

    private enum Metrics {
        static let actionWidth: CGFloat = 132
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ServiceGlyph(name: rule.serviceName)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rule.serviceName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(rule.alias)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 10)

                    Label(rule.registryStatusTitle, systemImage: "circle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(rule.registryStatusColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 7) {
                    RegistryRulePortSummary(accessMode: rule.accessMode, portSummary: rule.portSummary)

                    Text("|")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    Text("\(rule.accessMode.providerLabelPrefix)：\(rule.providerLabel)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ruleActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var ruleActions: some View {
        HStack(spacing: 8) {
            actionButton(rule.accessMode.entryActionTitle) {
                onEditMapping(rule)
            }

            actionButton("规则") {
                onEditRule(rule)
            }

            runtimeActionButton
        }
        .font(.system(size: 11, weight: .medium))
        .buttonStyle(.borderless)
        .controlSize(.mini)
        .frame(width: Metrics.actionWidth, alignment: .trailing)
        .padding(.top, 13)
    }

    private func actionButton(
        _ title: String,
        role: ButtonRole? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, role: role, action: action)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 30, alignment: .trailing)
            .disabled(disabled)
    }

    @ViewBuilder
    private var runtimeActionButton: some View {
        if rule.accessMode != .forwarded {
            actionButton("打开", disabled: rule.entryURL == nil) {
                openRuleEntry(rule)
            }
        } else {
            switch rule.runtimeState {
            case .running:
                actionButton("停止", role: .destructive) {
                    onStopRule(rule.id)
                }
            case .recoverable:
                actionButton("恢复") {
                    onRecoverRule(rule.id)
                }
            case .error:
                actionButton("重试") {
                    onRetryRule(rule.id)
                }
            case .stopped:
                actionButton("启动") {
                    onRecoverRule(rule.id)
                }
            }
        }
    }

    private func openRuleEntry(_ rule: RegistryRule) {
        #if os(macOS)
        guard let url = rule.entryURL else {
            return
        }
        NSWorkspace.shared.open(url)
        #endif
    }
}

private struct RegistryRulePortSummary: View {
    let accessMode: RegistryRuleAccessMode
    let portSummary: String

    var body: some View {
        HStack(spacing: 5) {
            Text(accessMode.portPrefix)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(portSummary)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.78))
        }
        .lineLimit(1)
        .truncationMode(.tail)
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
                .accessibilityLabel("清除规则筛选")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
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
    case editMapping(RegistryHost, RegistryRule)
    case editRule(RegistryHost, RegistryRule)

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
        case let .editMapping(host, rule):
            "edit-mapping-\(host.id)-\(rule.id)"
        case let .editRule(host, rule):
            "edit-rule-\(host.id)-\(rule.id)"
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
            "创建第一份保存配置；直达或本机资源可以先不添加 provider target。"
        case let .hostSettings(host), let .newPreset(host), let .importSSH(host), let .newRule(host):
            "\(host.name) · \(host.endpoint)"
        case let .editMapping(_, rule), let .editRule(_, rule):
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
            "这里会填写服务名、访问方式、入口地址和需要时的 provider target。"
        case .editMapping:
            "这里会调整访问入口；运行态的临时本地端口覆盖仍从运行页处理。"
        case .editRule:
            "这里会编辑配置规则本身，不直接操作当前运行实例。"
        }
    }
}

private struct RegistrySheetView: View {
    let sheet: RegistrySheet
    let hosts: [RegistryHost]
    let onSaveHost: (RegistryHostDraft) throws -> RegistrySnapshotResult
    let onParseSshCommand: (String) throws -> ParseSshCommandResult
    let onTestProviderTargetConnectivity: (String, UInt16) throws -> ProviderTargetConnectivityResult
    let onSaveRule: (RegistryRuleDraft) throws -> RegistrySnapshotResult
    let onClose: () -> Void

    var body: some View {
        switch sheet {
        case .newHost:
            RegistryHostEditorSheet(
                title: sheet.title,
                subtitle: sheet.subtitle,
                initialDraft: .blank,
                onSave: onSaveHost,
                onTestConnectivity: onTestProviderTargetConnectivity,
                onClose: onClose
            )
        case let .hostSettings(host):
            RegistryHostEditorSheet(
                title: sheet.title,
                subtitle: sheet.subtitle,
                initialDraft: host.hostDraft,
                onSave: onSaveHost,
                onTestConnectivity: onTestProviderTargetConnectivity,
                onClose: onClose
            )
        case let .newRule(host):
            RegistryRuleEditorSheet(
                title: sheet.title,
                subtitle: sheet.subtitle,
                host: host,
                initialDraft: .blank(hostId: host.id, providerTargetId: host.providerTargets.first?.id),
                onSave: onSaveRule,
                onClose: onClose
            )
        case let .editMapping(host, rule), let .editRule(host, rule):
            RegistryRuleEditorSheet(
                title: sheet.title,
                subtitle: sheet.subtitle,
                host: host,
                initialDraft: rule.ruleDraft(hostId: host.id),
                onSave: onSaveRule,
                onClose: onClose
            )
        case let .importSSH(host):
            RegistrySshImportSheet(
                title: sheet.title,
                subtitle: sheet.subtitle,
                hosts: hosts,
                fallbackHost: host,
                onParse: onParseSshCommand,
                onSaveHost: onSaveHost,
                onSaveRule: onSaveRule,
                onClose: onClose
            )
        case .newPreset:
            RegistryPlaceholderSheet(sheet: sheet, onClose: onClose)
        }
    }
}

private struct RegistrySshImportSheet: View {
    let title: String
    let subtitle: String
    let hosts: [RegistryHost]
    let fallbackHost: RegistryHost
    let onParse: (String) throws -> ParseSshCommandResult
    let onSaveHost: (RegistryHostDraft) throws -> RegistrySnapshotResult
    let onSaveRule: (RegistryRuleDraft) throws -> RegistrySnapshotResult
    let onClose: () -> Void

    @State private var commandText = ""
    @State private var selectedTargetOptionId: String
    @State private var parseResult: ParseSshCommandResult?
    @State private var previewDrafts: [RegistryImportedRuleDraftState] = []
    @State private var errorMessage: String?
    @State private var isParsing = false
    @State private var isSaving = false
    @State private var lastParsedCommandText = ""
    @State private var autoMatchedTargetOptionId: String?
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostPortText = "22"
    @State private var newHostUser = ""
    @State private var newTargetLabel = ""

    init(
        title: String,
        subtitle: String,
        hosts: [RegistryHost],
        fallbackHost: RegistryHost,
        onParse: @escaping (String) throws -> ParseSshCommandResult,
        onSaveHost: @escaping (RegistryHostDraft) throws -> RegistrySnapshotResult,
        onSaveRule: @escaping (RegistryRuleDraft) throws -> RegistrySnapshotResult,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.hosts = hosts
        self.fallbackHost = fallbackHost
        self.onParse = onParse
        self.onSaveHost = onSaveHost
        self.onSaveRule = onSaveRule
        self.onClose = onClose
        let fallbackTargetId = fallbackHost.importDefaultProviderTargetId
        let initialOptionId = fallbackTargetId.isEmpty
            ? ""
            : registryImportExistingTargetId(hostId: fallbackHost.id, targetId: fallbackTargetId)
        _selectedTargetOptionId = State(initialValue: initialOptionId)
    }

    private var commandIsStale: Bool {
        !lastParsedCommandText.isEmpty
            && normalizedCommandText(commandText) != normalizedCommandText(lastParsedCommandText)
    }

    private var canSave: Bool {
        !previewDrafts.isEmpty
            && resolvedTargetCanSave
            && !commandIsStale
            && !lastParsedCommandText.isEmpty
            && !isSaving
            && !isParsing
    }

    private var diagnostics: [SshCommandParseDiagnostic] {
        parseResult?.diagnostics ?? []
    }

    private var existingTargetOptions: [RegistryImportTargetOption] {
        hosts.flatMap { host in
            host.providerTargets.filter { $0.kind == .ssh }.map { target in
                RegistryImportTargetOption(host: host, target: target)
            }
        }
    }

    private var selectedNewTargetForExistingHostOption: RegistryImportTargetOption? {
        targetOptions.first(where: {
            $0.id == selectedTargetOptionId && $0.isNewTargetForExistingHost
        })
    }

    private var canCreateTargetFromParse: Bool {
        parseResult?.providerTargetHint != nil
    }

    private var targetOptions: [RegistryImportTargetOption] {
        var options = existingTargetOptions
        if let newTargetOption = newTargetForExistingHostOption() {
            options.append(newTargetOption)
        }
        if canCreateTargetFromParse {
            options.append(.newFromParsedDestination)
        }
        return options
    }

    private var selectedExistingTargetOption: RegistryImportTargetOption? {
        existingTargetOptions.first(where: {
            $0.id == selectedTargetOptionId && $0.isExistingTarget
        })
    }

    private var selectedTargetCreatesNewHost: Bool {
        canCreateTargetFromParse
            && selectedTargetOptionId == RegistryImportTargetOption.newFromParsedDestination.id
    }

    private var selectedTargetAddsToExistingHost: Bool {
        selectedNewTargetForExistingHostOption != nil
    }

    private var selectedDestinationSummary: RegistryImportDestinationSummaryModel? {
        if selectedTargetCreatesNewHost {
            return RegistryImportDestinationSummaryModel(
                modeTitle: "将新建资源分组",
                hostName: newHostName,
                targetLabel: newTargetLabel,
                targetAddress: newHostAddress,
                targetPortText: normalizedCommandText(newHostPortText).isEmpty ? "默认 22" : newHostPortText,
                matchedAutomatically: false
            )
        }

        if let option = selectedNewTargetForExistingHostOption {
            return RegistryImportDestinationSummaryModel(
                modeTitle: "将补充现有资源分组",
                hostName: option.hostName,
                targetLabel: newTargetLabel,
                targetAddress: newHostAddress,
                targetPortText: normalizedCommandText(newHostPortText).isEmpty ? "默认 22" : newHostPortText,
                matchedAutomatically: autoMatchedTargetOptionId == option.id
            )
        }

        guard let option = selectedExistingTargetOption else {
            return nil
        }

        return RegistryImportDestinationSummaryModel(
            modeTitle: "将保存到现有目标",
            hostName: option.hostName,
            targetLabel: option.targetLabel,
            targetAddress: option.targetAddress,
            targetPortText: option.targetPort.map(String.init) ?? "默认 22",
            matchedAutomatically: autoMatchedTargetOptionId == option.id
        )
    }

    private var resolvedTargetCanSave: Bool {
        if selectedTargetCreatesNewHost {
            return canCreateTargetFromParse
                && !newHostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !newTargetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if selectedTargetAddsToExistingHost {
            return canCreateTargetFromParse
                && !newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !newTargetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return selectedExistingTargetOption != nil
    }

    private var parseState: RegistrySshImportParseState {
        if normalizedCommandText(commandText).isEmpty {
            return .empty
        }

        if isParsing {
            return .parsing
        }

        if lastParsedCommandText.isEmpty {
            return .needsParsing
        }

        if commandIsStale {
            return .stale
        }

        return previewDrafts.isEmpty ? .parsedEmpty : .parsed(count: previewDrafts.count)
    }

    private var destinationSummary: String? {
        guard let hint = parseResult?.destinationHint else {
            return nil
        }

        var parts: [String] = []
        if let user = hint.user, !user.isEmpty {
            parts.append("\(user)@\(hint.host)")
        } else {
            parts.append(hint.host)
        }

        if let port = hint.port {
            parts.append("端口 \(port)")
        }

        return "命令目标：\(parts.joined(separator: " · "))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RegistryEditorSection("SSH 命令") {
                        HStack(spacing: 10) {
                            RegistrySshParseBadge(state: parseState)

                            if let destinationSummary {
                                Text(destinationSummary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("粘贴后点击解析；解析结果不会在命令修改后继续冒充当前状态。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                pasteCommandFromPasteboard()
                            } label: {
                                Label("粘贴", systemImage: "doc.on.clipboard")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.borderless)

                            Button(isParsing ? "解析中..." : "解析命令") {
                                parseCommand()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isParsing || isSaving || normalizedCommandText(commandText).isEmpty)
                        }

                        ZStack(alignment: .topLeading) {
                            RegistryCommandTextView(text: $commandText)
                                .frame(height: 132)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
                                }

                            if commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("粘贴一整行 ssh -L ... 命令")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: commandText) { _, _ in
                            markCommandNeedsParsing()
                        }

                        if commandIsStale {
                            RegistryInlineNotice(message: "命令已经修改，请重新解析后再保存预览规则。")
                        }
                    }

                    RegistryEditorSection("保存目标") {
                        RegistryImportTargetPicker(
                            selection: $selectedTargetOptionId,
                            options: targetOptions
                        )

                        if let selectedDestinationSummary {
                            RegistryImportDestinationSummary(summary: selectedDestinationSummary)
                        } else {
                            RegistryInlineNotice(message: "还没有可保存的目标。请先创建资源分组，或解析 SSH 命令后从解析目标新建。")
                        }

                        if selectedTargetCreatesNewHost {
                            RegistryNewImportHostEditor(
                                hostName: $newHostName,
                                address: $newHostAddress,
                                portText: $newHostPortText,
                                user: $newHostUser,
                                targetLabel: $newTargetLabel
                            )
                        } else if selectedTargetAddsToExistingHost {
                            RegistryImportSshTargetEditor(
                                address: $newHostAddress,
                                portText: $newHostPortText,
                                user: $newHostUser,
                                targetLabel: $newTargetLabel
                            )
                        }
                    }

                    if !diagnostics.isEmpty {
                        RegistryEditorSection("解析提示") {
                            RegistryDiagnosticList(diagnostics: diagnostics)
                        }
                    }

                    RegistryEditorSection("批量预览") {
                        HStack {
                            RegistrySubsectionTitle(parseState.previewTitle)
                            Spacer()
                        }

                        if previewDrafts.isEmpty {
                            RegistrySshImportEmptyState()
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach($previewDrafts) { $draft in
                                    RegistryImportedRuleDraftEditor(draft: $draft)
                                }
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                RegistryInlineError(message: errorMessage)
            }

            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button(isSaving ? "批量保存中…" : "保存全部预览规则") {
                    saveAll()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 760, height: 680)
    }

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func parseCommand() {
        errorMessage = nil
        isParsing = true
        defer { isParsing = false }

        do {
            let result = try onParse(commandText)
            parseResult = result
            previewDrafts = buildImportedRuleDraftStates(
                from: result,
                existingRules: hosts.flatMap(\.rules)
            )
            prepareNewHostDraft(from: result)
            selectTarget(for: result)
            lastParsedCommandText = commandText
        } catch {
            errorMessage = registryEditorMessage(from: error)
        }
    }

    private func saveAll() {
        errorMessage = nil

        guard !commandIsStale else {
            errorMessage = "命令已经修改，请重新解析后再保存预览规则。"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let assignment = try resolveSaveAssignment()
            var savedCount = 0
            for preview in previewDrafts {
                let draft = try preview.makeRegistryRuleDraft(
                    hostId: assignment.hostId,
                    providerTargetId: assignment.providerTargetId
                )

                do {
                    _ = try onSaveRule(draft)
                    savedCount += 1
                } catch {
                    throw RegistryImportBatchSaveError(
                        savedCount: savedCount,
                        underlying: error
                    )
                }
            }

            onClose()
        } catch let error as RegistryImportBatchSaveError {
            let detail = registryEditorMessage(from: error.underlying)
            if error.savedCount > 0 {
                errorMessage = "前 \(error.savedCount) 条规则已保存，后续保存失败。\n\(detail)"
            } else {
                errorMessage = detail
            }
        } catch {
            errorMessage = registryEditorMessage(from: error)
        }
    }

    private func pasteCommandFromPasteboard() {
        #if os(macOS)
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "剪贴板没有可粘贴的文本。"
            return
        }

        commandText = text
        errorMessage = nil
        #endif
    }

    private func markCommandNeedsParsing() {
        guard normalizedCommandText(commandText) != normalizedCommandText(lastParsedCommandText) else {
            return
        }

        parseResult = nil
        previewDrafts = []
        lastParsedCommandText = ""
        autoMatchedTargetOptionId = nil
        errorMessage = nil
        if selectedTargetCreatesNewHost || selectedTargetAddsToExistingHost || selectedExistingTargetOption == nil {
            selectedTargetOptionId = fallbackTargetOption()?.id ?? ""
        }
    }

    private func prepareNewHostDraft(from result: ParseSshCommandResult) {
        guard let hint = result.providerTargetHint else {
            newHostAddress = ""
            newHostPortText = "22"
            newHostUser = ""
            newHostName = ""
            newTargetLabel = ""
            return
        }

        let port = hint.targetPort ?? 22
        newHostAddress = hint.targetAddress
        newHostPortText = String(port)
        newHostUser = hint.user ?? ""
        newHostName = importHostName(from: hint.targetAddress)
        newTargetLabel = "SSH · \(hint.targetAddress)"
    }

    private func selectTarget(for result: ParseSshCommandResult) {
        if let matchedOption = matchingTargetOption(for: result) {
            selectedTargetOptionId = matchedOption.id
            autoMatchedTargetOptionId = matchedOption.id
            return
        }

        if let newTargetOption = newTargetForExistingHostOption(for: result) {
            selectedTargetOptionId = newTargetOption.id
            autoMatchedTargetOptionId = newTargetOption.id
            return
        }

        autoMatchedTargetOptionId = nil

        if canCreateTargetFromParse {
            selectedTargetOptionId = RegistryImportTargetOption.newFromParsedDestination.id
        } else if let fallbackOption = fallbackTargetOption() {
            selectedTargetOptionId = fallbackOption.id
        } else {
            selectedTargetOptionId = ""
        }
    }

    private func matchingTargetOption(for result: ParseSshCommandResult) -> RegistryImportTargetOption? {
        guard let hint = result.providerTargetHint else {
            return nil
        }

        let targetPort = hint.targetPort ?? 22
        return existingTargetOptions.first {
            let optionPort = $0.targetPort ?? 22
            return $0.providerKind == .ssh
                && optionPort == targetPort
                && $0.targetAddress.caseInsensitiveCompare(hint.targetAddress) == .orderedSame
        }
    }

    private func fallbackTargetOption() -> RegistryImportTargetOption? {
        if let sameHostOption = existingTargetOptions.first(where: { $0.hostId == fallbackHost.id }) {
            return sameHostOption
        }

        return existingTargetOptions.first
    }

    private func newTargetForExistingHostOption() -> RegistryImportTargetOption? {
        guard let result = parseResult else {
            return nil
        }

        return newTargetForExistingHostOption(for: result)
    }

    private func newTargetForExistingHostOption(
        for result: ParseSshCommandResult
    ) -> RegistryImportTargetOption? {
        guard let hint = result.providerTargetHint,
              let host = matchingHostForParsedDestination(hint) else {
            return nil
        }

        guard !host.providerTargets.contains(where: { targetMatchesParsedSshHint($0, hint: hint) }) else {
            return nil
        }

        return RegistryImportTargetOption(
            newSshTargetFor: host,
            hint: hint,
            label: newTargetLabel
        )
    }

    private func matchingHostForParsedDestination(_ hint: SshProviderTargetHint) -> RegistryHost? {
        let targetPort = hint.targetPort ?? 22
        if let exactHost = hosts.first(where: {
            $0.address.caseInsensitiveCompare(hint.targetAddress) == .orderedSame
                && (($0.port ?? 22) == targetPort)
        }) {
            return exactHost
        }

        return hosts.first(where: {
            $0.address.caseInsensitiveCompare(hint.targetAddress) == .orderedSame
        })
    }

    private func targetMatchesParsedSshHint(
        _ target: RegistryProviderTarget,
        hint: SshProviderTargetHint
    ) -> Bool {
        target.kind == .ssh
            && target.targetAddress.caseInsensitiveCompare(hint.targetAddress) == .orderedSame
            && ((target.targetPort ?? 22) == (hint.targetPort ?? 22))
    }

    private func resolveSaveAssignment() throws -> RegistryImportSaveAssignment {
        if selectedTargetCreatesNewHost {
            let hostDraft = try makeNewHostDraft()
            let snapshot = try onSaveHost(hostDraft)
            let createdHost = try findSavedHost(in: snapshot, draft: hostDraft)
            let createdTarget = try findCreatedTarget(in: createdHost, draft: hostDraft.providerTargets[0])
            return RegistryImportSaveAssignment(
                hostId: createdHost.id,
                providerTargetId: createdTarget.id
            )
        }

        if selectedTargetAddsToExistingHost {
            let hostDraft = try makeExistingHostDraftWithNewSshTarget()
            let snapshot = try onSaveHost(hostDraft)
            let updatedHost = try findSavedHost(in: snapshot, draft: hostDraft)
            guard let targetDraft = hostDraft.providerTargets.last else {
                throw RegistryEditorValidationError(
                    summary: "保存目标无效",
                    detail: "没有找到要新增的 SSH 链路。"
                )
            }
            let createdTarget = try findCreatedTarget(in: updatedHost, draft: targetDraft)
            return RegistryImportSaveAssignment(
                hostId: updatedHost.id,
                providerTargetId: createdTarget.id
            )
        }

        guard let option = selectedExistingTargetOption else {
            throw RegistryEditorValidationError(
                summary: "保存目标无效",
                detail: "请选择一个现有 SSH 链路，或从解析目标新建。"
            )
        }

        return RegistryImportSaveAssignment(
            hostId: option.hostId,
            providerTargetId: option.targetId
        )
    }

    private func makeNewHostDraft() throws -> RegistryHostDraft {
        guard canCreateTargetFromParse else {
            throw RegistryEditorValidationError(
                summary: "缺少可新建的 SSH 目标",
                detail: "请先解析包含登录目标的 SSH 命令。"
            )
        }

        let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw RegistryEditorValidationError(
                summary: "资源分组名称不能为空",
                detail: "请填写从解析目标新建的资源分组名称。"
            )
        }

        let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw RegistryEditorValidationError(
                summary: "SSH 地址不能为空",
                detail: "请填写从解析目标新建的 SSH 地址。"
            )
        }

        let targetDraft = try makeParsedSshTargetDraft()

        return RegistryHostDraft(
            id: nil,
            name: trimmedName,
            address: trimmedAddress,
            port: targetDraft.targetPort,
            user: normalized(newHostUser),
            tags: [],
            osHint: .linux,
            osDistro: nil,
            status: .unknown,
            providerTargets: [targetDraft]
        )
    }

    private func makeExistingHostDraftWithNewSshTarget() throws -> RegistryHostDraft {
        guard let option = selectedNewTargetForExistingHostOption,
              let host = hosts.first(where: { $0.id == option.hostId }) else {
            throw RegistryEditorValidationError(
                summary: "保存目标无效",
                detail: "请选择要补充 SSH 链路的资源分组。"
            )
        }

        let targetDraft = try makeParsedSshTargetDraft()
        guard !host.providerTargets.contains(where: {
            $0.kind == .ssh
                && $0.targetAddress.caseInsensitiveCompare(targetDraft.targetAddress) == .orderedSame
                && (($0.targetPort ?? 22) == (targetDraft.targetPort ?? 22))
        }) else {
            throw RegistryEditorValidationError(
                summary: "SSH 链路已存在",
                detail: "这个资源分组已经有相同地址和端口的 SSH 链路，请直接选择现有链路保存。"
            )
        }

        var draft = host.hostDraft
        if normalized(draft.user ?? "") == nil {
            draft.user = normalized(newHostUser)
        }
        draft.providerTargets.append(targetDraft)
        return draft
    }

    private func makeParsedSshTargetDraft() throws -> RegistryProviderTargetDraft {
        let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw RegistryEditorValidationError(
                summary: "SSH 地址不能为空",
                detail: "请填写从解析目标生成的 SSH 地址。"
            )
        }

        let trimmedTargetLabel = newTargetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTargetLabel.isEmpty else {
            throw RegistryEditorValidationError(
                summary: "链路标签不能为空",
                detail: "请填写从解析目标生成的 SSH 链路标签。"
            )
        }

        return RegistryProviderTargetDraft(
            id: nil,
            label: trimmedTargetLabel,
            kind: .ssh,
            targetAddress: trimmedAddress,
            targetPort: try parseOptionalPortStrict(newHostPortText, label: "SSH 端口") ?? 22
        )
    }

    private func findSavedHost(
        in snapshot: RegistrySnapshotResult,
        draft: RegistryHostDraft
    ) throws -> RegistryHost {
        if let draftId = draft.id,
           let host = snapshot.hosts.first(where: { $0.id == draftId }) {
            return host
        }

        if let host = snapshot.hosts.first(where: { $0.id == snapshot.selectedHostId }) {
            return host
        }

        if let host = snapshot.hosts.first(where: {
            $0.address.caseInsensitiveCompare(draft.address) == .orderedSame
                && (($0.port ?? 22) == (draft.port ?? 22))
        }) {
            return host
        }

        throw RegistryEditorValidationError(
            summary: "资源分组已保存但无法定位",
            detail: "Bridge 已返回新的资源快照，但没有找到刚保存的 SSH 目标。"
        )
    }

    private func findCreatedTarget(
        in host: RegistryHost,
        draft: RegistryProviderTargetDraft
    ) throws -> RegistryProviderTarget {
        if let target = host.providerTargets.first(where: {
            $0.kind == .ssh
                && $0.targetAddress.caseInsensitiveCompare(draft.targetAddress) == .orderedSame
                && (($0.targetPort ?? 22) == (draft.targetPort ?? 22))
        }) {
            return target
        }

        throw RegistryEditorValidationError(
            summary: "新资源分组缺少 SSH 链路",
            detail: "请重新读取资源登记后检查刚创建的资源分组。"
        )
    }
}

private struct RegistryImportedRuleDraftEditor: View {
    @Binding var draft: RegistryImportedRuleDraftState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("转发 \(draft.forwardIndex)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(draft.localPortText) -> \(draft.remoteHost):\(draft.remotePortText)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 12) {
                RegistryLabeledField("名称", text: $draft.serviceName)
                    .frame(maxWidth: .infinity)
                RegistryLabeledField("别名", text: $draft.alias, prompt: "可选")
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 12) {
                RegistryLabeledField("远端主机", text: $draft.remoteHost)
                    .frame(maxWidth: .infinity)
                RegistryLabeledField("类型", text: $draft.kind, prompt: "可选")
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 12) {
                RegistryLabeledField("本地端口", text: $draft.localPortText)
                    .frame(maxWidth: .infinity)
                RegistryLabeledField("远端端口", text: $draft.remotePortText)
                    .frame(maxWidth: .infinity)
            }

            RegistryLabeledField("标签", text: $draft.tagsText, prompt: "用逗号分隔")
        }
        .padding(12)
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

#if os(macOS)
private struct RegistryCommandTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = RegistryCommandNSTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }

        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
        }
    }
}

private final class RegistryCommandNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
#else
private struct RegistryCommandTextView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .padding(4)
    }
}
#endif

private struct RegistrySshParseBadge: View {
    let state: RegistrySshImportParseState

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(state.tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(state.tint.opacity(0.10))
            }
    }
}

private struct RegistryImportTargetPicker: View {
    @Binding var selection: String
    let options: [RegistryImportTargetOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("导入到")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("", selection: $selection) {
                ForEach(options) { option in
                    Text(option.menuTitle).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)
        }
    }
}

private struct RegistryImportDestinationSummary: View {
    let summary: RegistryImportDestinationSummaryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(summary.modeTitle)
                    .font(.system(size: 11, weight: .semibold))
                if summary.matchedAutomatically {
                    Text("自动匹配")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green.opacity(0.10))
                        }
                }
            }

            HStack(spacing: 14) {
                RegistryImportSummaryField(label: "资源分组", value: summary.hostName)
                RegistryImportSummaryField(label: "链路", value: summary.targetLabel)
                RegistryImportSummaryField(
                    label: "目标",
                    value: "\(summary.targetAddress):\(summary.targetPortText)"
                )
            }
        }
        .padding(10)
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

private struct RegistryImportSummaryField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "未填写" : value)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RegistryNewImportHostEditor: View {
    @Binding var hostName: String
    @Binding var address: String
    @Binding var portText: String
    @Binding var user: String
    @Binding var targetLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RegistrySubsectionTitle("从解析目标新建")
            HStack(alignment: .top, spacing: 12) {
                RegistryLabeledField("资源分组名称", text: $hostName)
                RegistryLabeledField("SSH 地址", text: $address)
            }
            HStack(alignment: .top, spacing: 12) {
                RegistryLabeledField("SSH 端口", text: $portText)
                RegistryLabeledField("用户", text: $user, prompt: "可选")
            }
            RegistryLabeledField("链路标签", text: $targetLabel)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(RelayDockColor.listBandBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
        }
    }
}

private struct RegistryImportSshTargetEditor: View {
    @Binding var address: String
    @Binding var portText: String
    @Binding var user: String
    @Binding var targetLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RegistrySubsectionTitle("补充 SSH 链路")
            HStack(alignment: .top, spacing: 12) {
                RegistryLabeledField("SSH 地址", text: $address)
                RegistryLabeledField("SSH 端口", text: $portText)
            }
            HStack(alignment: .top, spacing: 12) {
                RegistryLabeledField("用户", text: $user, prompt: "可选")
                RegistryLabeledField("链路标签", text: $targetLabel)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(RelayDockColor.listBandBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
        }
    }
}

private struct RegistrySshImportEmptyState: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text("还没有可保存的导入预览，先解析一条 ssh -L 命令。")
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

private struct RegistryDiagnosticList: View {
    let diagnostics: [SshCommandParseDiagnostic]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(diagnostics) { diagnostic in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: diagnostic.severity == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.orange)
                        Text(diagnostic.summary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    if let detail = diagnostic.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let forwardSpec = diagnostic.forwardSpec {
                        Text(forwardSpec)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            diagnostic.severity == .error
                                ? Color.red.opacity(0.08)
                                : Color.orange.opacity(0.08)
                        )
                }
            }
        }
    }
}

private struct RegistryInlineNotice: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.08))
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

private struct RegistryHostEditorSheet: View {
    let title: String
    let subtitle: String
    let initialDraft: RegistryHostDraft
    let onSave: (RegistryHostDraft) throws -> RegistrySnapshotResult
    let onTestConnectivity: (String, UInt16) throws -> ProviderTargetConnectivityResult
    let onClose: () -> Void

    @State private var name: String
    @State private var address: String
    @State private var portText: String
    @State private var user: String
    @State private var tagsText: String
    @State private var osHint: RegistryHostOsHint
    @State private var osDistro: String
    @State private var providerTargets: [RegistryProviderTargetDraft]
    @State private var errorMessage: String?
    @State private var connectivityResult: RegistryConnectivityTestState?
    @State private var isSaving = false
    @State private var isTestingConnectivity = false

    init(
        title: String,
        subtitle: String,
        initialDraft: RegistryHostDraft,
        onSave: @escaping (RegistryHostDraft) throws -> RegistrySnapshotResult,
        onTestConnectivity: @escaping (String, UInt16) throws -> ProviderTargetConnectivityResult,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.initialDraft = initialDraft
        self.onSave = onSave
        self.onTestConnectivity = onTestConnectivity
        self.onClose = onClose
        _name = State(initialValue: initialDraft.name)
        _address = State(initialValue: initialDraft.address)
        _portText = State(initialValue: initialDraft.port.map(String.init) ?? "")
        _user = State(initialValue: initialDraft.user ?? "")
        _tagsText = State(initialValue: initialDraft.tags.joined(separator: ", "))
        _osHint = State(initialValue: initialDraft.osHint)
        _osDistro = State(initialValue: initialDraft.osDistro ?? "")
        _providerTargets = State(initialValue: initialDraft.providerTargets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RegistryEditorSection("主机信息") {
                        RegistryLabeledField("名称", text: $name)
                        RegistryLabeledField("地址", text: $address)
                        RegistryLabeledField("端口", text: $portText)
                        RegistryLabeledField("用户", text: $user)
                        RegistryLabeledField("标签", text: $tagsText, prompt: "用逗号分隔")
                        RegistryEnumPicker("系统类型", selection: $osHint, options: RegistryHostOsHint.editorOptions)
                        RegistryLabeledField("发行版", text: $osDistro, prompt: "可选")
                    }

                    RegistryEditorSection("Provider Targets") {
                        ForEach(Array(providerTargets.indices), id: \.self) { index in
                            RegistryProviderTargetDraftEditor(
                                title: "链路 \(index + 1)",
                                draft: $providerTargets[index],
                                canRemove: true
                            ) {
                                providerTargets.remove(at: index)
                            }
                        }

                        if providerTargets.isEmpty {
                            RegistryInlineNotice(message: "当前主机没有 provider target。直达应用和本机应用可以直接登记；需要 SSH 本地转发时再新增链路。")
                        }

                        Button {
                            providerTargets.append(.blank)
                        } label: {
                            Label("新增链路", systemImage: "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if let connectivityResult {
                RegistryConnectivityResultBanner(state: connectivityResult)
            }

            if let errorMessage {
                RegistryInlineError(message: errorMessage)
            }

            HStack {
                Button(isTestingConnectivity ? "测试中..." : "测试连接") {
                    testConnectivity()
                }
                .disabled(isSaving || isTestingConnectivity || !canTestConnectivity)

                Spacer()
                Button("取消", action: onClose)
                Button(isSaving ? "保存中…" : "保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 560, height: 620)
    }

    private var canTestConnectivity: Bool {
        do {
            _ = try resolvedConnectivityTarget()
            return true
        } catch {
            return false
        }
    }

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try onSave(
                RegistryHostDraft(
                    id: initialDraft.id,
                    name: name,
                    address: address,
                    port: parseOptionalPort(portText),
                    user: normalized(user),
                    tags: tags(from: tagsText),
                    osHint: osHint,
                    osDistro: normalized(osDistro),
                    status: statusFromConnectivity(),
                    providerTargets: providerTargets.map {
                        RegistryProviderTargetDraft(
                            id: $0.id,
                            label: $0.label,
                            kind: $0.kind,
                            targetAddress: $0.targetAddress,
                            targetPort: parseOptionalPort($0.targetPort.map(String.init) ?? "")
                        )
                    }
                )
            )
            onClose()
        } catch let error as BridgeErrorInfo {
            errorMessage = [error.summary, error.detail].compactMap { $0 }.joined(separator: "\n")
        } catch let error as RegistryEditorValidationError {
            errorMessage = [error.summary, error.detail].compactMap { $0 }.joined(separator: "\n")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testConnectivity() {
        errorMessage = nil
        isTestingConnectivity = true
        defer { isTestingConnectivity = false }

        do {
            let target = try resolvedConnectivityTarget()
            let result = try onTestConnectivity(target.address, target.port)
            connectivityResult = .finished(result)
        } catch let error as BridgeErrorInfo {
            connectivityResult = .failed(summary: error.summary, detail: error.detail)
        } catch let error as RegistryEditorValidationError {
            connectivityResult = .failed(summary: error.summary, detail: error.detail)
        } catch {
            connectivityResult = .failed(summary: "连接测试失败", detail: error.localizedDescription)
        }
    }

    private func resolvedConnectivityTarget() throws -> RegistryConnectivityTarget {
        let firstTarget = providerTargets.first
        let targetAddress = normalized(firstTarget?.targetAddress ?? "") ?? normalized(address)
        let portSource = firstTarget?.targetPort.map(String.init) ?? portText
        let targetPort = try parseOptionalPortStrict(portSource, label: "测试端口")
            ?? defaultPort(for: firstTarget?.kind ?? .ssh)

        guard let targetAddress else {
            throw RegistryEditorValidationError(
                summary: "测试目标不完整",
                detail: "请先填写目标地址或主机地址。"
            )
        }

        return RegistryConnectivityTarget(address: targetAddress, port: targetPort)
    }

    private func statusFromConnectivity() -> RegistryHostStatus {
        guard !connectivityTargetChangedSinceInitialDraft else {
            return .unknown
        }

        guard let connectivityResult else {
            return initialDraft.status
        }

        return connectivityResult.hostStatus
    }

    private var connectivityTargetChangedSinceInitialDraft: Bool {
        do {
            let currentTarget = try resolvedConnectivityTarget()
            let initialTarget = initialConnectivityTarget
            return currentTarget.address != initialTarget.address || currentTarget.port != initialTarget.port
        } catch {
            return true
        }
    }

    private var initialConnectivityTarget: RegistryConnectivityTarget {
        let firstTarget = initialDraft.providerTargets.first
        let targetAddress = normalized(firstTarget?.targetAddress ?? "")
            ?? normalized(initialDraft.address)
            ?? ""
        let targetPort = firstTarget?.targetPort
            ?? initialDraft.port
            ?? defaultPort(for: firstTarget?.kind ?? .ssh)

        return RegistryConnectivityTarget(address: targetAddress, port: targetPort)
    }
}

private struct RegistryRuleEditorSheet: View {
    let title: String
    let subtitle: String
    let host: RegistryHost
    let initialDraft: RegistryRuleDraft
    let onSave: (RegistryRuleDraft) throws -> RegistrySnapshotResult
    let onClose: () -> Void

    @State private var serviceName: String
    @State private var alias: String
    @State private var accessMode: RegistryRuleAccessMode
    @State private var providerTargetId: String
    @State private var remoteHost: String
    @State private var mainLocalPortText: String
    @State private var mainRemotePortText: String
    @State private var secondaryPorts: [RegistryPortMapping]
    @State private var kind: String
    @State private var tagsText: String
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        title: String,
        subtitle: String,
        host: RegistryHost,
        initialDraft: RegistryRuleDraft,
        onSave: @escaping (RegistryRuleDraft) throws -> RegistrySnapshotResult,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.host = host
        self.initialDraft = initialDraft
        self.onSave = onSave
        self.onClose = onClose
        _serviceName = State(initialValue: initialDraft.serviceName)
        _alias = State(initialValue: initialDraft.alias ?? "")
        _accessMode = State(initialValue: initialDraft.accessMode)
        _providerTargetId = State(initialValue: initialDraft.providerTargetId ?? host.providerTargets.first?.id ?? "")
        _remoteHost = State(initialValue: initialDraft.mainRemoteHost)
        _mainLocalPortText = State(initialValue: String(initialDraft.mainLocalPort))
        _mainRemotePortText = State(initialValue: String(initialDraft.mainRemotePort))
        _secondaryPorts = State(initialValue: initialDraft.secondaryPorts)
        _kind = State(initialValue: initialDraft.kind ?? "")
        _tagsText = State(initialValue: initialDraft.tags.joined(separator: ", "))
        _notes = State(initialValue: initialDraft.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RegistryEditorSection("规则信息") {
                        RegistryLabeledField("名称", text: $serviceName)
                        RegistryLabeledField("别名", text: $alias, prompt: "可选")
                        RegistryAccessModePicker(selection: $accessMode)
                        if accessMode == .forwarded {
                            RegistryTargetPicker(
                                selection: $providerTargetId,
                                targets: host.providerTargets
                            )
                            if host.providerTargets.isEmpty {
                                RegistryInlineNotice(message: "本地转发需要先在主机设置里新增 SSH provider target；直达应用和本机应用不需要链路。")
                            }
                        } else {
                            RegistryModeHint(accessMode: accessMode)
                        }
                        RegistryLabeledField("类型", text: $kind, prompt: "可选")
                        RegistryLabeledField("标签", text: $tagsText, prompt: "用逗号分隔")
                    }

                    RegistryEditorSection(portSectionTitle) {
                        RegistryLabeledField(remoteHostLabel, text: $remoteHost)
                        if accessMode != .direct {
                            RegistryLabeledField(localPortLabel, text: $mainLocalPortText)
                        }
                        RegistryLabeledField(remotePortLabel, text: $mainRemotePortText)

                        ForEach(Array(secondaryPorts.indices), id: \.self) { index in
                            RegistrySecondaryPortEditor(
                                title: "附属端口 \(index + 1)",
                                accessMode: accessMode,
                                mapping: $secondaryPorts[index]
                            ) {
                                secondaryPorts.remove(at: index)
                            }
                        }

                        Button {
                            secondaryPorts.append(
                                RegistryPortMapping(localPort: 0, remoteHost: remoteHost, remotePort: 0)
                            )
                        } label: {
                            Label("新增附属端口", systemImage: "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                    }

                    RegistryEditorSection("备注") {
                        TextEditor(text: $notes)
                            .font(.system(size: 12))
                            .frame(height: 100)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(RelayDockColor.subtleBorder, lineWidth: 1)
                            }
                    }
                }
            }

            if let errorMessage {
                RegistryInlineError(message: errorMessage)
            }

            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button(isSaving ? "保存中…" : "保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try onSave(
                RegistryRuleDraft(
                    id: initialDraft.id,
                    hostId: host.id,
                    serviceName: serviceName,
                    alias: normalized(alias),
                    accessMode: accessMode,
                    providerTargetId: accessMode == .forwarded ? providerTargetId : nil,
                    remoteHost: remoteHost,
                    mainLocalPort: accessMode == .direct ? 0 : try parseRequiredPort(mainLocalPortText, label: localPortLabel),
                    mainRemoteHost: remoteHost,
                    mainRemotePort: try parseRequiredPort(mainRemotePortText, label: remotePortLabel),
                    secondaryPorts: secondaryPorts,
                    kind: normalized(kind),
                    tags: tags(from: tagsText),
                    notes: normalized(notes)
                )
            )
            onClose()
        } catch let error as BridgeErrorInfo {
            errorMessage = [error.summary, error.detail].compactMap { $0 }.joined(separator: "\n")
        } catch let error as RegistryEditorValidationError {
            errorMessage = [error.summary, error.detail].compactMap { $0 }.joined(separator: "\n")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var portSectionTitle: String {
        switch accessMode {
        case .forwarded:
            "端口映射"
        case .direct:
            "直达入口"
        case .local:
            "本机入口"
        }
    }

    private var remoteHostLabel: String {
        switch accessMode {
        case .forwarded:
            "远端主机"
        case .direct:
            "访问主机"
        case .local:
            "本机地址"
        }
    }

    private var localPortLabel: String {
        switch accessMode {
        case .forwarded:
            "本地主端口"
        case .direct:
            "本地端口"
        case .local:
            "本机端口"
        }
    }

    private var remotePortLabel: String {
        switch accessMode {
        case .forwarded:
            "远端主端口"
        case .direct:
            "应用端口"
        case .local:
            "服务端口"
        }
    }
}

private struct RegistryAccessModePicker: View {
    @Binding var selection: RegistryRuleAccessMode

    var body: some View {
        Picker("访问方式", selection: $selection) {
            ForEach(RegistryRuleAccessMode.registryOptions, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
    }
}

private struct RegistryModeHint: View {
    let accessMode: RegistryRuleAccessMode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: accessMode.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(accessMode.editorHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RelayDockColor.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct RegistryProviderTargetDraftEditor: View {
    let title: String
    @Binding var draft: RegistryProviderTargetDraft
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if canRemove {
                    Button("移除", role: .destructive, action: onRemove)
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.borderless)
                }
            }

            RegistryEnumPicker("类型", selection: $draft.kind, options: RegistryProviderKind.editorOptions)
            RegistryLabeledField("标签", text: $draft.label)
            RegistryLabeledField("目标地址", text: $draft.targetAddress)
            RegistryOptionalPortField("目标端口", port: Binding(
                get: { draft.targetPort },
                set: { draft.targetPort = $0 }
            ))
        }
        .padding(12)
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

private struct RegistrySecondaryPortEditor: View {
    let title: String
    let accessMode: RegistryRuleAccessMode
    @Binding var mapping: RegistryPortMapping
    let onRemove: () -> Void

    @State private var localPortText = ""
    @State private var remoteHostText = ""
    @State private var remotePortText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("移除", role: .destructive, action: onRemove)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderless)
            }

            if accessMode != .direct {
                RegistryLabeledField(accessMode.secondaryLocalPortLabel, text: Binding(
                    get: { mapping.localPort == 0 ? "" : String(mapping.localPort) },
                    set: { mapping.localPort = UInt16($0) ?? 0 }
                ))
            }
            if accessMode != .local {
                RegistryLabeledField(accessMode.secondaryRemoteHostLabel, text: Binding(
                    get: { mapping.remoteHost },
                    set: { mapping.remoteHost = $0 }
                ))
            }
            RegistryLabeledField(accessMode.secondaryRemotePortLabel, text: Binding(
                get: { mapping.remotePort == 0 ? "" : String(mapping.remotePort) },
                set: { mapping.remotePort = UInt16($0) ?? 0 }
            ))
            .onAppear {
                if accessMode == .direct {
                    mapping.localPort = 0
                }
                if accessMode == .local, mapping.remoteHost.isEmpty {
                    mapping.remoteHost = "127.0.0.1"
                }
            }
        }
        .padding(12)
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

private struct RegistryEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RegistrySectionHeader(title)
            content
        }
    }
}

private struct RegistryLabeledField: View {
    let label: String
    @Binding var text: String
    var prompt: String?

    init(_ label: String, text: Binding<String>, prompt: String? = nil) {
        self.label = label
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt ?? "", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.94))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(RegistryStyle.cardBorder.opacity(1.2), lineWidth: 1)
                }
        }
    }
}

private struct RegistryOptionalPortField: View {
    let label: String
    @Binding var port: UInt16?
    @State private var text: String

    init(_ label: String, port: Binding<UInt16?>) {
        self.label = label
        self._port = port
        self._text = State(initialValue: port.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        RegistryLabeledField(label, text: Binding(
            get: { text },
            set: {
                text = $0
                port = UInt16($0)
            }
        ), prompt: "可选")
    }
}

private struct RegistryTargetPicker: View {
    @Binding var selection: String
    let targets: [RegistryProviderTarget]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("链路")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Picker("", selection: $selection) {
                ForEach(targets) { target in
                    Text(target.label).tag(target.id)
                }
            }
            .labelsHidden()
        }
    }
}

private struct RegistryEnumPicker<T: Hashable & RawRepresentable & RegistryDisplayNameProviding>: View where T.RawValue == String {
    let label: String
    @Binding var selection: T
    let options: [T]

    init(_ label: String, selection: Binding<T>, options: [T]) {
        self.label = label
        self._selection = selection
        self.options = options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.registryDisplayName).tag(option)
                }
            }
            .labelsHidden()
        }
    }
}

private struct RegistryInlineError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(0.08))
            }
    }
}

private struct RegistryConnectivityTarget {
    let address: String
    let port: UInt16
}

private enum RegistryConnectivityTestState {
    case finished(ProviderTargetConnectivityResult)
    case failed(summary: String, detail: String?)

    var hostStatus: RegistryHostStatus {
        switch self {
        case let .finished(result):
            result.reachable ? .online : .offline
        case .failed:
            .offline
        }
    }
}

private struct RegistryConnectivityResultBanner: View {
    let state: RegistryConnectivityTestState

    private var isReachable: Bool {
        if case let .finished(result) = state {
            return result.reachable
        }

        return false
    }

    private var title: String {
        switch state {
        case let .finished(result):
            if result.reachable {
                let latency = result.latencyMillis.map { " · \($0)ms" } ?? ""
                return "连接可达：\(result.targetAddress):\(result.targetPort)\(latency)"
            }

            return result.diagnostic?.summary ?? "连接不可达"
        case let .failed(summary, _):
            return summary
        }
    }

    private var detail: String? {
        switch state {
        case let .finished(result):
            return result.diagnostic?.detail
        case let .failed(_, detail):
            return detail
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isReachable ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isReachable ? Color.green.opacity(0.08) : Color.orange.opacity(0.09))
        }
    }
}

private struct RegistryEditorValidationError: Error {
    let summary: String
    let detail: String?
}

private struct RegistryImportBatchSaveError: Error {
    let savedCount: Int
    let underlying: Error
}

private struct RegistryImportSaveAssignment {
    let hostId: String
    let providerTargetId: String
}

private enum RegistrySshImportParseState {
    case empty
    case needsParsing
    case parsing
    case stale
    case parsed(count: Int)
    case parsedEmpty

    var title: String {
        switch self {
        case .empty:
            "等待粘贴"
        case .needsParsing:
            "待解析"
        case .parsing:
            "解析中"
        case .stale:
            "待重新解析"
        case let .parsed(count):
            "已解析 \(count) 条"
        case .parsedEmpty:
            "没有可导入转发"
        }
    }

    var previewTitle: String {
        switch self {
        case .empty:
            "粘贴后显示预览"
        case .needsParsing, .stale:
            "待解析后显示预览"
        case .parsing:
            "正在解析 SSH 命令"
        case let .parsed(count):
            "已解析 \(count) 条本地转发"
        case .parsedEmpty:
            "未解析到本地转发"
        }
    }

    var systemImage: String {
        switch self {
        case .empty:
            "doc.text"
        case .needsParsing, .stale:
            "clock"
        case .parsing:
            "arrow.triangle.2.circlepath"
        case .parsed:
            "checkmark.circle.fill"
        case .parsedEmpty:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .empty:
            .secondary
        case .needsParsing, .stale:
            .orange
        case .parsing:
            RelayDockColor.sidebarAccent
        case .parsed:
            .green
        case .parsedEmpty:
            .red
        }
    }
}

private struct RegistryImportDestinationSummaryModel {
    let modeTitle: String
    let hostName: String
    let targetLabel: String
    let targetAddress: String
    let targetPortText: String
    let matchedAutomatically: Bool
}

private struct RegistryImportTargetOption: Identifiable, Equatable {
    enum Kind: Equatable {
        case existingTarget
        case newTargetForExistingHost
        case newHostFromParsedDestination
    }

    let id: String
    let hostId: String
    let hostName: String
    let targetId: String
    let targetLabel: String
    let providerKind: RegistryProviderKind
    let targetAddress: String
    let targetPort: UInt16?
    let kind: Kind

    init(host: RegistryHost, target: RegistryProviderTarget) {
        id = registryImportExistingTargetId(hostId: host.id, targetId: target.id)
        hostId = host.id
        hostName = host.name
        targetId = target.id
        targetLabel = target.label
        providerKind = target.kind
        targetAddress = target.targetAddress
        targetPort = target.targetPort
        kind = .existingTarget
    }

    init(newSshTargetFor host: RegistryHost, hint: SshProviderTargetHint, label: String) {
        id = registryImportNewTargetId(hostId: host.id)
        hostId = host.id
        hostName = host.name
        targetId = ""
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        targetLabel = trimmedLabel.isEmpty ? "SSH · \(hint.targetAddress)" : trimmedLabel
        providerKind = .ssh
        targetAddress = hint.targetAddress
        targetPort = hint.targetPort ?? 22
        kind = .newTargetForExistingHost
    }

    private init() {
        id = Self.newFromParsedDestinationId
        hostId = ""
        hostName = "新建资源分组"
        targetId = ""
        targetLabel = "从解析目标新建 SSH 链路"
        providerKind = .ssh
        targetAddress = ""
        targetPort = nil
        kind = .newHostFromParsedDestination
    }

    var isExistingTarget: Bool {
        kind == .existingTarget
    }

    var isNewTargetForExistingHost: Bool {
        kind == .newTargetForExistingHost
    }

    var menuTitle: String {
        switch kind {
        case .existingTarget:
            let portText = targetPort.map { ":\($0)" } ?? ""
            return "\(hostName) · \(targetLabel) · \(targetAddress)\(portText)"
        case .newTargetForExistingHost:
            let portText = targetPort.map { ":\($0)" } ?? ""
            return "\(hostName) · 补充 \(targetLabel) · \(targetAddress)\(portText)"
        case .newHostFromParsedDestination:
            return "从解析目标新建资源分组"
        }
    }

    static let newFromParsedDestinationId = "new-from-parsed-destination"
    static let newFromParsedDestination = RegistryImportTargetOption()
}

private struct RegistryImportedRuleDraftState: Identifiable, Equatable {
    let id: String
    let forwardIndex: Int
    var serviceName: String
    var alias: String
    var remoteHost: String
    var localPortText: String
    var remotePortText: String
    var kind: String
    var tagsText: String

    init(candidate: SshImportedRuleDraft, serviceName: String, alias: String) {
        id = "forward-\(candidate.forwardIndex)-\(candidate.localPort)-\(candidate.remoteHost)-\(candidate.remotePort)"
        forwardIndex = candidate.forwardIndex
        self.serviceName = serviceName
        self.alias = alias
        remoteHost = candidate.remoteHost
        localPortText = String(candidate.localPort)
        remotePortText = String(candidate.remotePort)
        kind = candidate.kind ?? ""
        tagsText = candidate.tags.joined(separator: ", ")
    }

    func makeRegistryRuleDraft(
        hostId: String,
        providerTargetId: String
    ) throws -> RegistryRuleDraft {
        let trimmedName = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw RegistryEditorValidationError(
                summary: "规则名称不能为空",
                detail: "请至少为每条导入规则保留一个名称。"
            )
        }

        let trimmedRemoteHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemoteHost.isEmpty else {
            throw RegistryEditorValidationError(
                summary: "远端主机不能为空",
                detail: "请为每条导入规则填写远端主机。"
            )
        }

        return RegistryRuleDraft(
            id: nil,
            hostId: hostId,
            serviceName: trimmedName,
            alias: normalized(alias),
            accessMode: .forwarded,
            providerTargetId: providerTargetId,
            remoteHost: trimmedRemoteHost,
            mainLocalPort: try parseRequiredPort(localPortText, label: "本地端口"),
            mainRemoteHost: trimmedRemoteHost,
            mainRemotePort: try parseRequiredPort(remotePortText, label: "远端端口"),
            secondaryPorts: [],
            kind: normalized(kind),
            tags: tags(from: tagsText),
            notes: nil
        )
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

private protocol RegistryDisplayNameProviding {
    var registryDisplayName: String { get }
}

private func registryEditorMessage(from error: Error) -> String {
    if let bridgeError = error as? BridgeErrorInfo {
        return [bridgeError.summary, bridgeError.detail]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    if let validationError = error as? RegistryEditorValidationError {
        return [validationError.summary, validationError.detail]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    return error.localizedDescription
}

private func normalized(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedCommandText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func registryImportExistingTargetId(hostId: String, targetId: String) -> String {
    "existing::\(hostId)::\(targetId)"
}

private func registryImportNewTargetId(hostId: String) -> String {
    "new-target::\(hostId)"
}

private func importHostName(from address: String) -> String {
    let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedAddress.isEmpty ? "导入主机" : trimmedAddress
}

private func tags(from text: String) -> [String] {
    text
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func parseOptionalPort(_ text: String) -> UInt16? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return UInt16(trimmed)
}

private func parseOptionalPortStrict(_ text: String, label: String) throws -> UInt16? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    guard let value = UInt16(trimmed), value > 0 else {
        throw RegistryEditorValidationError(
            summary: "\(label)无效",
            detail: "请输入 1-65535 之间的端口。"
        )
    }

    return value
}

private func parseRequiredPort(_ text: String, label: String) throws -> UInt16 {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = UInt16(trimmed), value > 0 else {
        throw RegistryEditorValidationError(
            summary: "\(label)无效",
            detail: "请输入 1-65535 之间的端口。"
        )
    }

    return value
}

private func defaultPort(for kind: RegistryProviderKind) -> UInt16 {
    switch kind {
    case .ssh:
        22
    case .tailscale:
        22
    }
}

private func buildImportedRuleDraftStates(
    from result: ParseSshCommandResult,
    existingRules: [RegistryRule]
) -> [RegistryImportedRuleDraftState] {
    var usedNames = Set(
        existingRules.map { $0.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    )
    var usedAliases = Set(
        existingRules
            .compactMap { normalized($0.alias)?.lowercased() }
    )

    return result.ruleDrafts.map { candidate in
        let serviceName = uniquedServiceName(candidate.serviceName, usedNames: &usedNames)
        let alias = uniquedAlias(candidate.alias, usedAliases: &usedAliases) ?? ""
        return RegistryImportedRuleDraftState(
            candidate: candidate,
            serviceName: serviceName,
            alias: alias
        )
    }
}

private func uniquedServiceName(_ base: String, usedNames: inout Set<String>) -> String {
    let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = trimmedBase.isEmpty ? "导入规则" : trimmedBase
    let normalizedFallback = fallback.lowercased()
    if !usedNames.contains(normalizedFallback) {
        usedNames.insert(normalizedFallback)
        return fallback
    }

    var index = 2
    while true {
        let candidate = "\(fallback) \(index)"
        let normalizedCandidate = candidate.lowercased()
        if !usedNames.contains(normalizedCandidate) {
            usedNames.insert(normalizedCandidate)
            return candidate
        }
        index += 1
    }
}

private func uniquedAlias(_ base: String?, usedAliases: inout Set<String>) -> String? {
    guard let rawBase = base,
          let base = normalized(rawBase) else {
        return nil
    }

    let normalizedBase = base.lowercased()
    if !usedAliases.contains(normalizedBase) {
        usedAliases.insert(normalizedBase)
        return base
    }

    let separatorIndex = base.firstIndex(of: ".")
    let stem = separatorIndex.map { String(base[..<$0]) } ?? base
    let suffix = separatorIndex.map { String(base[$0...]) } ?? ""
    var index = 2

    while true {
        let candidate = "\(stem)-\(index)\(suffix)"
        let normalizedCandidate = candidate.lowercased()
        if !usedAliases.contains(normalizedCandidate) {
            usedAliases.insert(normalizedCandidate)
            return candidate
        }
        index += 1
    }
}

private extension RegistryHostStatus {
    var title: String {
        switch self {
        case .unknown:
            "未探测"
        case .online:
            "在线"
        case .offline:
            "离线"
        }
    }

    var color: Color {
        switch self {
        case .unknown:
            .secondary
        case .online:
            .green
        case .offline:
            .secondary
        }
    }

    static var editorOptions: [RegistryHostStatus] {
        [.unknown, .online, .offline]
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
        case .unknown:
            "questionmark.square.dashed"
        }
    }

    static var editorOptions: [RegistryHostOsHint] {
        [.macos, .ubuntu, .windows, .linux, .raspberryPi, .unknown]
    }
}

extension RegistryHostStatus: RegistryDisplayNameProviding {
    var registryDisplayName: String {
        switch self {
        case .unknown:
            "未探测"
        case .online:
            "在线"
        case .offline:
            "离线"
        }
    }
}

extension RegistryHostOsHint: RegistryDisplayNameProviding {
    var registryDisplayName: String {
        switch self {
        case .macos:
            "macOS"
        case .ubuntu:
            "Ubuntu"
        case .windows:
            "Windows"
        case .linux:
            "Linux"
        case .raspberryPi:
            "Raspberry Pi"
        case .unknown:
            "未知"
        }
    }
}

extension RegistryProviderKind: CaseIterable, RegistryDisplayNameProviding {
    static var allCases: [RegistryProviderKind] {
        [.ssh, .tailscale]
    }

    static var editorOptions: [RegistryProviderKind] {
        allCases
    }

    var registryDisplayName: String {
        switch self {
        case .ssh:
            "SSH"
        case .tailscale:
            "Tailscale"
        }
    }
}

private extension RegistryHost {
    var importDefaultProviderTargetId: String {
        providerTargets.first(where: { $0.kind == .ssh })?.id ?? ""
    }

    var hostDraft: RegistryHostDraft {
        RegistryHostDraft(
            id: id,
            name: name,
            address: address,
            port: port,
            user: user,
            tags: tags,
            osHint: osHint,
            osDistro: osDistro,
            status: status,
            providerTargets: providerTargets.map {
                RegistryProviderTargetDraft(
                    id: $0.id,
                    label: $0.label,
                    kind: $0.kind,
                    targetAddress: $0.targetAddress,
                    targetPort: $0.targetPort
                )
            }
        )
    }
}

private extension RegistryHostDraft {
    static var blank: RegistryHostDraft {
        RegistryHostDraft(
            id: nil,
            name: "",
            address: "",
            port: 22,
            user: "",
            tags: [],
            osHint: .macos,
            osDistro: nil,
            status: .unknown,
            providerTargets: []
        )
    }
}

private extension RegistryProviderTargetDraft {
    static var blank: RegistryProviderTargetDraft {
        RegistryProviderTargetDraft(
            id: nil,
            label: "",
            kind: .ssh,
            targetAddress: "",
            targetPort: 22
        )
    }
}

private extension RegistryRule {
    var registryStatusTitle: String {
        switch accessMode {
        case .forwarded:
            runtimeState.title
        case .direct, .local:
            "已登记"
        }
    }

    var registryStatusColor: Color {
        switch accessMode {
        case .forwarded:
            runtimeState.color
        case .direct:
            .blue
        case .local:
            .green
        }
    }

    var entryURL: URL? {
        let host = alias.isEmpty ? remoteHost : alias
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let port: UInt16 = {
            switch accessMode {
            case .forwarded, .local:
                return mainLocalPort == 0 ? mainRemotePort : mainLocalPort
            case .direct:
                return mainRemotePort == 0 ? mainLocalPort : mainRemotePort
            }
        }()

        guard port > 0 else {
            return nil
        }

        let scheme = port == 443 ? "https" : "http"
        let portSuffix = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            ? ""
            : ":\(port)"
        return URL(string: "\(scheme)://\(host)\(portSuffix)/")
    }

    func ruleDraft(hostId: String) -> RegistryRuleDraft {
        RegistryRuleDraft(
            id: id,
            hostId: hostId,
            serviceName: serviceName,
            alias: alias.isEmpty ? nil : alias,
            accessMode: accessMode,
            providerTargetId: providerTargetId,
            remoteHost: remoteHost,
            mainLocalPort: mainLocalPort,
            mainRemoteHost: mainRemoteHost,
            mainRemotePort: mainRemotePort,
            secondaryPorts: secondaryPorts,
            kind: kind,
            tags: tags,
            notes: notes
        )
    }
}

private extension RegistryRuleAccessMode {
    static var registryOptions: [RegistryRuleAccessMode] {
        [.forwarded, .direct, .local]
    }

    var title: String {
        switch self {
        case .forwarded:
            "本地转发"
        case .direct:
            "直达应用"
        case .local:
            "本机应用"
        }
    }

    var symbolName: String {
        switch self {
        case .forwarded:
            "arrow.left.arrow.right"
        case .direct:
            "point.3.connected.trianglepath.dotted"
        case .local:
            "desktopcomputer"
        }
    }

    var editorHint: String {
        switch self {
        case .forwarded:
            "通过 SSH/provider 建立本地端口入口，参与启动、恢复和端口冲突处理。"
        case .direct:
            "远程地址已经可直接访问，不创建本地端口，也不进入隧道启动流程。"
        case .local:
            "登记本机已有服务入口，可用于打开和后续端口诊断。"
        }
    }

    var portPrefix: String {
        switch self {
        case .forwarded:
            "本地"
        case .direct:
            "直达"
        case .local:
            "本机"
        }
    }

    var providerLabelPrefix: String {
        switch self {
        case .forwarded:
            "链路"
        case .direct:
            "入口"
        case .local:
            "来源"
        }
    }

    var entryActionTitle: String {
        switch self {
        case .forwarded:
            "映射"
        case .direct, .local:
            "入口"
        }
    }

    var secondaryLocalPortLabel: String {
        switch self {
        case .forwarded:
            "本地端口"
        case .direct:
            "本地端口"
        case .local:
            "本机端口"
        }
    }

    var secondaryRemoteHostLabel: String {
        switch self {
        case .forwarded:
            "远端主机"
        case .direct:
            "访问主机"
        case .local:
            "本机地址"
        }
    }

    var secondaryRemotePortLabel: String {
        switch self {
        case .forwarded:
            "远端端口"
        case .direct:
            "应用端口"
        case .local:
            "服务端口"
        }
    }
}

private extension RegistryRuleDraft {
    static func blank(hostId: String, providerTargetId: String?) -> RegistryRuleDraft {
        let accessMode: RegistryRuleAccessMode = providerTargetId == nil ? .direct : .forwarded
        return RegistryRuleDraft(
            id: nil,
            hostId: hostId,
            serviceName: "",
            alias: nil,
            accessMode: accessMode,
            providerTargetId: providerTargetId,
            remoteHost: "127.0.0.1",
            mainLocalPort: accessMode == .direct ? 0 : 3000,
            mainRemoteHost: "127.0.0.1",
            mainRemotePort: 3000,
            secondaryPorts: [],
            kind: nil,
            tags: [],
            notes: nil
        )
    }
}

private extension RegistryRuleRuntimeState {
    static var registryDisplayOrder: [RegistryRuleRuntimeState] {
        [.running, .recoverable, .error, .stopped]
    }

    var groupTitle: String {
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
