import SwiftUI

struct PreferencesView: View {
    let runRecoverySnapshot: RunRecoverySnapshotResult?
    let registrySnapshot: RegistrySnapshotResult?
    let runRecoveryError: BridgeErrorInfo?
    let registryError: BridgeErrorInfo?
    let bridgeExecutablePath: String?
    let isBridgeAvailable: Bool
    let onReload: () -> Void

    @State private var selectedSection: PreferencesSection = .bridge
    @State private var recoveryStrategy: RecoveryStrategy = .automatic
    @State private var reloadAtLaunch = true
    @State private var retryAfterWake = true
    @State private var activeSheet: PreferencesSheet?

    private var providerCoverage: [RegistryProviderKind: Int] {
        Dictionary(
            grouping: registrySnapshot?.hosts.flatMap(\.providerTargets) ?? [],
            by: \.kind
        ).mapValues(\.count)
    }

    private var recoverableCount: Int {
        runRecoverySnapshot?.summary.recoverableCount ?? 0
    }

    private var issueCount: Int {
        runRecoverySnapshot?.summary.issueCount ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)

            Divider()

            detailPane
        }
        .background(RelayDockColor.contentBackground)
        .sheet(item: $activeSheet) { sheet in
            PreferencesSheetView(sheet: sheet) {
                activeSheet = nil
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置范围")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 7)

            ForEach(PreferencesSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 12))
                            .foregroundStyle(selectedSection == section ? .primary : .secondary)
                            .frame(width: 16, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.system(size: 12, weight: selectedSection == section ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(section.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 8)

                        if let badge = badgeText(for: section) {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    .frame(height: 34)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selectedSection == section ? RelayDockColor.sidebarSelection : Color.clear)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: section))
                .accessibilityValue(selectedSection == section ? "已选择" : "未选择")
                .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text("MVP 边界")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("当前切片先把设置入口收敛到 native 工具视图，局部交互只保留会话内状态，不写入持久化。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .background(RelayDockColor.sidebarBackground)
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()

                switch selectedSection {
                case .bridge:
                    bridgePane
                case .recovery:
                    recoveryPane
                case .providers:
                    providersPane
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSection.title)
                    .font(.system(size: 16, weight: .semibold))
                Text(selectedSection.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("重新检查", action: onReload)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var bridgePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            preferenceSectionTitle("Bridge sidecar")

            PreferenceInfoRow(
                title: "状态",
                value: isBridgeAvailable ? "已接入" : "未找到",
                detail: isBridgeAvailable ? "当前 shell 会通过 sidecar 获取运行与资源 snapshot" : "需要可执行文件 `target/debug/relaydock-bridge`",
                accent: isBridgeAvailable ? .green : .red
            )
            Divider()
            PreferenceInfoRow(
                title: "可执行路径",
                value: bridgeExecutablePath ?? "等待开发环境 sidecar",
                detail: "路径读取来自 shell bridge executor；本切片不在这里修改配置路径。",
                accent: .secondary
            )
            Divider()
            PreferenceInfoRow(
                title: "运行快照",
                value: runRecoverySnapshot == nil ? "未读取" : "已读取",
                detail: runRecoveryError?.summary ?? (runRecoverySnapshot?.summary.message ?? "等待运行态返回"),
                accent: runRecoveryError == nil ? .secondary : .orange
            )
            Divider()
            PreferenceInfoRow(
                title: "资源快照",
                value: registrySnapshot == nil ? "未读取" : "已读取",
                detail: registryError?.summary ?? (registrySnapshot == nil ? "等待资源态返回" : "\(registrySnapshot?.hosts.count ?? 0) 个主机已加载"),
                accent: registryError == nil ? .secondary : .orange
            )
            Divider()
            PreferenceActionRow(
                title: "接入边界",
                detail: "查看当前 sidecar / snapshot 路径与后续持久化边界",
                buttonTitle: "说明"
            ) {
                activeSheet = .bridgeBoundary
            }
        }
        .padding(.bottom, 18)
    }

    private var recoveryPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            preferenceSectionTitle("启动恢复策略")

            PreferenceControlGroup(
                recoveryStrategy: $recoveryStrategy,
                reloadAtLaunch: $reloadAtLaunch,
                retryAfterWake: $retryAfterWake
            )

            Divider()

            PreferenceInfoRow(
                title: "恢复集合",
                value: "\(recoverableCount) 条",
                detail: recoverableCount == 0 ? "当前没有待恢复条目" : "支持恢复、改本地端口、清除；运行规则仍由 run/recovery snapshot 决定",
                accent: recoverableCount == 0 ? .secondary : .blue
            )
            Divider()
            PreferenceInfoRow(
                title: "异常实例",
                value: "\(issueCount) 条",
                detail: issueCount == 0 ? "当前没有异常中的 runtime" : "可在诊断页查看具体 provider / 端口异常",
                accent: issueCount == 0 ? .secondary : .orange
            )
            Divider()
            PreferenceActionRow(
                title: "恢复预览",
                detail: "查看当前待恢复集合与启动后恢复边界",
                buttonTitle: "查看"
            ) {
                activeSheet = .recoveryPreview(
                    recoverableCount: recoverableCount,
                    strategyTitle: recoveryStrategy.title
                )
            }
        }
        .padding(.bottom, 18)
    }

    private var providersPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            preferenceSectionTitle("Provider 与权限入口")

            PreferenceInfoRow(
                title: "SSH target",
                value: "\(providerCoverage[.ssh, default: 0]) 个",
                detail: "当前资源登记中已识别的 SSH provider target",
                accent: providerCoverage[.ssh, default: 0] > 0 ? .secondary : .orange
            )
            Divider()
            PreferenceInfoRow(
                title: "Tailscale target",
                value: "\(providerCoverage[.tailscale, default: 0]) 个",
                detail: "当前资源登记中已识别的 Tailscale provider target",
                accent: providerCoverage[.tailscale, default: 0] > 0 ? .secondary : .orange
            )
            Divider()
            PreferenceActionRow(
                title: "OpenSSH 检查入口",
                detail: "查看 provider 接入范围和当前主机覆盖情况",
                buttonTitle: "检查"
            ) {
                activeSheet = .providerCheck(
                    title: "OpenSSH 检查入口",
                    detail: "当前将优先复用系统 OpenSSH。真实可执行探测与错误归因后续应由 bridge / Rust provider 层返回结构化结果。"
                )
            }
            Divider()
            PreferenceActionRow(
                title: "Tailscale 检查入口",
                detail: "查看当前资源中 Tailscale 覆盖和后续 CLI 探测边界",
                buttonTitle: "检查"
            ) {
                activeSheet = .providerCheck(
                    title: "Tailscale 检查入口",
                    detail: "本切片先保留入口和上下文，不在 Swift 里发明 provider 状态机。后续 CLI 可用性应从 bridge snapshot 返回。"
                )
            }
            Divider()
            PreferenceActionRow(
                title: "权限与系统集成",
                detail: "辅助功能、自动化、日志目录与 LaunchAgent 的 MVP 边界说明",
                buttonTitle: "说明"
            ) {
                activeSheet = .permissionGuide
            }
        }
        .padding(.bottom, 18)
    }

    private func preferenceSectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func badgeText(for section: PreferencesSection) -> String? {
        switch section {
        case .bridge:
            return isBridgeAvailable ? "正常" : "缺失"
        case .recovery:
            return recoverableCount > 0 ? "\(recoverableCount)" : nil
        case .providers:
            return registrySnapshot == nil ? nil : "\(providerCoverage.values.reduce(0, +))"
        }
    }

    private func accessibilityLabel(for section: PreferencesSection) -> String {
        if let badge = badgeText(for: section) {
            return "\(section.title)，\(badge)"
        }

        return section.title
    }
}

private enum PreferencesSection: String, CaseIterable, Identifiable {
    case bridge
    case recovery
    case providers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bridge:
            "Bridge 与 Sidecar"
        case .recovery:
            "启动与恢复"
        case .providers:
            "Provider 与权限"
        }
    }

    var subtitle: String {
        switch self {
        case .bridge:
            "路径、状态、快照边界"
        case .recovery:
            "启动恢复策略与会话内控制"
        case .providers:
            "provider 覆盖与系统入口"
        }
    }

    var description: String {
        switch self {
        case .bridge:
            "设置页只展示当前 shell 与 sidecar 的接入状态，不在这里发明新的 bridge 行为。"
        case .recovery:
            "恢复策略先保持为会话内控制，后续真实策略应继续由 Rust core 与持久化层接管。"
        case .providers:
            "第一段先把 provider / 权限入口收敛出来，真实探测结果后续通过 bridge 返回结构化 snapshot。"
        }
    }

    var systemImage: String {
        switch self {
        case .bridge:
            "point.3.connected.trianglepath.dotted"
        case .recovery:
            "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .providers:
            "key.horizontal"
        }
    }
}

private enum RecoveryStrategy: String, CaseIterable, Identifiable {
    case automatic
    case retainSet
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "自动恢复"
        case .retainSet:
            "仅保留待恢复"
        case .manual:
            "完全手动"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            "应用启动后优先尝试恢复上次成功运行过且仍有效的集合。"
        case .retainSet:
            "只恢复恢复集合元数据，不自动启动，由用户在运行页手动恢复。"
        case .manual:
            "启动后只读取快照，不自动恢复任何 runtime。"
        }
    }
}

private enum PreferencesSheet: Identifiable {
    case bridgeBoundary
    case recoveryPreview(recoverableCount: Int, strategyTitle: String)
    case providerCheck(title: String, detail: String)
    case permissionGuide

    var id: String {
        switch self {
        case .bridgeBoundary:
            "bridge-boundary"
        case let .recoveryPreview(recoverableCount, strategyTitle):
            "recovery-preview-\(recoverableCount)-\(strategyTitle)"
        case let .providerCheck(title, _):
            "provider-\(title)"
        case .permissionGuide:
            "permission-guide"
        }
    }

    var title: String {
        switch self {
        case .bridgeBoundary:
            "Bridge / Sidecar 边界"
        case .recoveryPreview:
            "恢复策略预览"
        case let .providerCheck(title, _):
            title
        case .permissionGuide:
            "权限与系统集成"
        }
    }

    var subtitle: String {
        switch self {
        case .bridgeBoundary:
            "当前开发环境只读取 sidecar 路径和 bridge snapshot。"
        case let .recoveryPreview(recoverableCount, strategyTitle):
            "当前策略：\(strategyTitle) · 待恢复 \(recoverableCount) 条"
        case .providerCheck:
            "第一段只提供入口和上下文，不执行真实系统探测。"
        case .permissionGuide:
            "后续会接系统权限、日志目录、LaunchAgent 与 Keychain。"
        }
    }

    var bodyText: String {
        switch self {
        case .bridgeBoundary:
            "本页只显示 shell 当前拿到的可执行路径、bridge 是否可用、运行 / 资源 snapshot 是否已返回。若后续需要用户可编辑路径，应保持粗粒度设置并同步 bridge executor。"
        case let .recoveryPreview(recoverableCount, strategyTitle):
            "当前会话内选择的是“\(strategyTitle)”。共有 \(recoverableCount) 条待恢复项；真实恢复策略、休眠唤醒恢复和持久化集合仍应由 Rust core 负责。"
        case let .providerCheck(_, detail):
            detail
        case .permissionGuide:
            "辅助功能、自动化、日志目录、LaunchAgent、Keychain 等系统集成暂未接进本页；这一段先把入口、命名和 native 结构收敛好，避免后续散落在 placeholder 里。"
        }
    }
}

private struct PreferenceInfoRow: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 90, alignment: .leading)

                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 118, alignment: .leading)

                Spacer()
            }

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 100)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct PreferenceActionRow: View {
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct PreferenceControlGroup: View {
    @Binding var recoveryStrategy: RecoveryStrategy
    @Binding var reloadAtLaunch: Bool
    @Binding var retryAfterWake: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                Text("恢复策略")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 90, alignment: .leading)

                Picker("恢复策略", selection: $recoveryStrategy) {
                    ForEach(RecoveryStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()
            }

            Text(recoveryStrategy.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 102)
                .lineLimit(2)
                .truncationMode(.tail)

            Toggle("启动后先读取上次运行集合", isOn: $reloadAtLaunch)
                .font(.system(size: 12))
                .padding(.leading, 100)

            Toggle("唤醒后优先重试 KeepAlive 中断", isOn: $retryAfterWake)
                .font(.system(size: 12))
                .padding(.leading, 100)

            Text("当前仅保留在本次会话内，用于确认 native 设置结构；后续真实策略应落回 Rust core / storage。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 102)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct PreferencesSheetView: View {
    let sheet: PreferencesSheet
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
        .frame(width: 430)
    }
}
