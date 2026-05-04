import SwiftUI

struct RegistryView: View {
    let snapshot: RegistrySnapshotResult?
    @Binding var selectedHostId: String?
    let bridgeError: BridgeErrorInfo?
    let onSaveHost: (RegistryHostDraft) throws -> Void
    let onSaveRule: (RegistryRuleDraft) throws -> Void
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
            RegistrySheetView(
                sheet: sheet,
                onSaveHost: onSaveHost,
                onSaveRule: onSaveRule
            ) {
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
            "创建第一份保存配置，并建立至少一个 provider target。"
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
            "这里会填写服务名、别名、本地端口、远端地址和 provider target。"
        case .editMapping:
            "这里会调整端口映射；运行态的临时本地端口覆盖仍从运行页处理。"
        case .editRule:
            "这里会编辑配置规则本身，不直接操作当前运行实例。"
        }
    }
}

private struct RegistrySheetView: View {
    let sheet: RegistrySheet
    let onSaveHost: (RegistryHostDraft) throws -> Void
    let onSaveRule: (RegistryRuleDraft) throws -> Void
    let onClose: () -> Void

    var body: some View {
        switch sheet {
        case .newHost:
            RegistryHostEditorSheet(
                title: sheet.title,
                subtitle: sheet.subtitle,
                initialDraft: .blank,
                onSave: onSaveHost,
                onClose: onClose
            )
        case let .hostSettings(host):
            RegistryHostEditorSheet(
                title: sheet.title,
                subtitle: sheet.subtitle,
                initialDraft: host.hostDraft,
                onSave: onSaveHost,
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
        case .newPreset, .importSSH:
            RegistryPlaceholderSheet(sheet: sheet, onClose: onClose)
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
    let onSave: (RegistryHostDraft) throws -> Void
    let onClose: () -> Void

    @State private var name: String
    @State private var address: String
    @State private var portText: String
    @State private var user: String
    @State private var tagsText: String
    @State private var osHint: RegistryHostOsHint
    @State private var osDistro: String
    @State private var status: RegistryHostStatus
    @State private var providerTargets: [RegistryProviderTargetDraft]
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        title: String,
        subtitle: String,
        initialDraft: RegistryHostDraft,
        onSave: @escaping (RegistryHostDraft) throws -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.initialDraft = initialDraft
        self.onSave = onSave
        self.onClose = onClose
        _name = State(initialValue: initialDraft.name)
        _address = State(initialValue: initialDraft.address)
        _portText = State(initialValue: initialDraft.port.map(String.init) ?? "")
        _user = State(initialValue: initialDraft.user ?? "")
        _tagsText = State(initialValue: initialDraft.tags.joined(separator: ", "))
        _osHint = State(initialValue: initialDraft.osHint)
        _osDistro = State(initialValue: initialDraft.osDistro ?? "")
        _status = State(initialValue: initialDraft.status)
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
                        RegistryEnumPicker("状态提示", selection: $status, options: RegistryHostStatus.editorOptions)
                        RegistryLabeledField("发行版", text: $osDistro, prompt: "可选")
                    }

                    RegistryEditorSection("Provider Targets") {
                        ForEach(Array(providerTargets.indices), id: \.self) { index in
                            RegistryProviderTargetDraftEditor(
                                title: "链路 \(index + 1)",
                                draft: $providerTargets[index],
                                canRemove: providerTargets.count > 1
                            ) {
                                providerTargets.remove(at: index)
                            }
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
        .frame(width: 560, height: 620)
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
            try onSave(
                RegistryHostDraft(
                    id: initialDraft.id,
                    name: name,
                    address: address,
                    port: parseOptionalPort(portText),
                    user: normalized(user),
                    tags: tags(from: tagsText),
                    osHint: osHint,
                    osDistro: normalized(osDistro),
                    status: status,
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
}

private struct RegistryRuleEditorSheet: View {
    let title: String
    let subtitle: String
    let host: RegistryHost
    let initialDraft: RegistryRuleDraft
    let onSave: (RegistryRuleDraft) throws -> Void
    let onClose: () -> Void

    @State private var serviceName: String
    @State private var alias: String
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
        onSave: @escaping (RegistryRuleDraft) throws -> Void,
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
        _providerTargetId = State(initialValue: initialDraft.providerTargetId)
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
                        RegistryTargetPicker(
                            selection: $providerTargetId,
                            targets: host.providerTargets
                        )
                        RegistryLabeledField("类型", text: $kind, prompt: "可选")
                        RegistryLabeledField("标签", text: $tagsText, prompt: "用逗号分隔")
                    }

                    RegistryEditorSection("端口映射") {
                        RegistryLabeledField("远端主机", text: $remoteHost)
                        RegistryLabeledField("本地主端口", text: $mainLocalPortText)
                        RegistryLabeledField("远端主端口", text: $mainRemotePortText)

                        ForEach(Array(secondaryPorts.indices), id: \.self) { index in
                            RegistrySecondaryPortEditor(
                                title: "附属端口 \(index + 1)",
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
            try onSave(
                RegistryRuleDraft(
                    id: initialDraft.id,
                    hostId: host.id,
                    serviceName: serviceName,
                    alias: normalized(alias),
                    providerTargetId: providerTargetId,
                    remoteHost: remoteHost,
                    mainLocalPort: try parseRequiredPort(mainLocalPortText, label: "本地主端口"),
                    mainRemoteHost: remoteHost,
                    mainRemotePort: try parseRequiredPort(mainRemotePortText, label: "远端主端口"),
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

            RegistryLabeledField("本地端口", text: Binding(
                get: { mapping.localPort == 0 ? "" : String(mapping.localPort) },
                set: { mapping.localPort = UInt16($0) ?? 0 }
            ))
            RegistryLabeledField("远端主机", text: Binding(
                get: { mapping.remoteHost },
                set: { mapping.remoteHost = $0 }
            ))
            RegistryLabeledField("远端端口", text: Binding(
                get: { mapping.remotePort == 0 ? "" : String(mapping.remotePort) },
                set: { mapping.remotePort = UInt16($0) ?? 0 }
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
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
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

private struct RegistryEditorValidationError: Error {
    let summary: String
    let detail: String?
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

private func normalized(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
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
            providerTargets: [.blank]
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
    func ruleDraft(hostId: String) -> RegistryRuleDraft {
        RegistryRuleDraft(
            id: id,
            hostId: hostId,
            serviceName: serviceName,
            alias: alias.isEmpty ? nil : alias,
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

private extension RegistryRuleDraft {
    static func blank(hostId: String, providerTargetId: String?) -> RegistryRuleDraft {
        RegistryRuleDraft(
            id: nil,
            hostId: hostId,
            serviceName: "",
            alias: nil,
            providerTargetId: providerTargetId ?? "",
            remoteHost: "127.0.0.1",
            mainLocalPort: 3000,
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
