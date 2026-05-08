import Foundation

@MainActor
final class RelayDockShellViewModel: ObservableObject {
    @Published var selection: RelayDockSection = .runAndRecovery
    @Published var runRecoveryCollapseCommand: RunRecoveryCollapseCommand?
    @Published var registryCommand: RegistryShellCommand?
    @Published private(set) var runRecoverySnapshot: RunRecoverySnapshotResult?
    @Published private(set) var isLoadingRunRecovery = false
    @Published private(set) var runRecoveryError: BridgeErrorInfo?
    @Published private(set) var registrySnapshot: RegistrySnapshotResult?
    @Published private(set) var registryError: BridgeErrorInfo?
    @Published var selectedRegistryHostId: String?

    private let bridgeExecutor: RelayDockBridgeExecutor?
    private let visualQAFixtures: RelayDockVisualQAFixtures?

    init(
        bridgeExecutor: RelayDockBridgeExecutor? = RelayDockBridgeExecutor.defaultDevelopmentExecutor(),
        visualQAFixtures: RelayDockVisualQAFixtures? = RelayDockVisualQAFixtures.fromEnvironment()
    ) {
        self.bridgeExecutor = bridgeExecutor
        self.visualQAFixtures = visualQAFixtures
    }

    var statusSummary: StatusSummary {
        guard let snapshot = runRecoverySnapshot else {
            if isLoadingRunRecovery {
                return StatusSummary(
                    connectedHosts: 0,
                    runningForwards: 0,
                    issueCount: 0,
                    message: "正在读取运行数据"
                )
            }

            if let runRecoveryError {
                return StatusSummary(
                    connectedHosts: 0,
                    runningForwards: 0,
                    issueCount: 1,
                    message: runRecoveryError.summary
                )
            }

            return StatusSummary(
                connectedHosts: 0,
                runningForwards: 0,
                issueCount: 0,
                message: "等待运行数据"
            )
        }

        return StatusSummary(
            connectedHosts: snapshot.summary.connectedHosts,
            runningForwards: snapshot.summary.runningForwards,
            issueCount: snapshot.summary.issueCount,
            message: snapshot.summary.message
        )
    }

    var bridgeExecutablePath: String? {
        bridgeExecutor?.executablePath
    }

    var isBridgeAvailable: Bool {
        bridgeExecutor != nil
    }

    func loadRunRecoverySnapshot() {
        guard !isLoadingRunRecovery else {
            return
        }

        if let visualQAFixtures {
            applySnapshot(visualQAFixtures.runRecoverySnapshot)
            return
        }

        guard let bridgeExecutor else {
            runRecoveryError = BridgeErrorInfo(
                code: .processFailed,
                summary: "未找到 RelayDock bridge sidecar",
                detail: "Expected target/debug/relaydock-bridge in the development workspace.",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "Run cargo build -p relaydock-core --bin relaydock-bridge."
            )
            return
        }

        isLoadingRunRecovery = true
        do {
            applySnapshot(try bridgeExecutor.loadRunRecoverySnapshot())
        } catch {
            applyBridgeFailure(error)
        }
        isLoadingRunRecovery = false
    }

    func startRule(ruleId: String) {
        guard visualQAFixtures == nil else {
            return
        }

        guard let bridgeExecutor else {
            loadRunRecoverySnapshot()
            return
        }

        isLoadingRunRecovery = true
        do {
            applySnapshot(try bridgeExecutor.startRule(ruleId: ruleId))
        } catch {
            applyBridgeFailure(error)
        }
        isLoadingRunRecovery = false
    }

    func recoverItem(ruleId: String) {
        guard visualQAFixtures == nil else {
            return
        }

        guard let bridgeExecutor else {
            loadRunRecoverySnapshot()
            return
        }

        isLoadingRunRecovery = true
        do {
            applySnapshot(try bridgeExecutor.recoverItem(ruleId: ruleId))
        } catch {
            applyBridgeFailure(error)
        }
        isLoadingRunRecovery = false
    }

    func stopRuntimeInstance(runtimeId: String) {
        guard visualQAFixtures == nil else {
            return
        }

        guard let bridgeExecutor else {
            loadRunRecoverySnapshot()
            return
        }

        isLoadingRunRecovery = true
        do {
            applySnapshot(try bridgeExecutor.stopRuntimeInstance(runtimeId: runtimeId))
        } catch {
            applyBridgeFailure(error)
        }
        isLoadingRunRecovery = false
    }

    func retryRuntimeInstance(runtimeId: String) {
        guard visualQAFixtures == nil else {
            return
        }

        guard let bridgeExecutor else {
            loadRunRecoverySnapshot()
            return
        }

        isLoadingRunRecovery = true
        do {
            applySnapshot(try bridgeExecutor.retryRuntimeInstance(runtimeId: runtimeId))
        } catch {
            applyBridgeFailure(error)
        }
        isLoadingRunRecovery = false
    }

    func clearRecoveryItem(recoveryId: String) {
        guard visualQAFixtures == nil else {
            return
        }

        guard let bridgeExecutor else {
            loadRunRecoverySnapshot()
            return
        }

        isLoadingRunRecovery = true
        do {
            applySnapshot(try bridgeExecutor.clearRecoveryItem(recoveryId: recoveryId))
        } catch {
            applyBridgeFailure(error)
        }
        isLoadingRunRecovery = false
    }

    func applyLocalPortOverride(ruleId: String, localPort: UInt16) {
        guard visualQAFixtures == nil else {
            return
        }

        guard let bridgeExecutor else {
            loadRunRecoverySnapshot()
            return
        }

        isLoadingRunRecovery = true
        do {
            applySnapshot(try bridgeExecutor.applyLocalPortOverride(ruleId: ruleId, localPort: localPort))
        } catch {
            applyBridgeFailure(error)
        }
        isLoadingRunRecovery = false
    }

    func retryRuntimeForRule(_ ruleId: String) {
        guard let runtimeId = runRecoverySnapshot?
            .hosts
            .flatMap(\.rows)
            .first(where: { $0.ruleId == ruleId })?
            .runtimeId else {
            runRecoveryError = BridgeErrorInfo(
                code: .invalidDemoAction,
                summary: "未找到可重试的运行实例",
                detail: "rule_id=\(ruleId)",
                affectedPort: nil,
                affectedRuleId: ruleId,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "重新读取运行状态后再试。"
            )
            return
        }

        retryRuntimeInstance(runtimeId: runtimeId)
    }

    func stopRuntimeForRule(_ ruleId: String) {
        guard let runtimeId = runRecoverySnapshot?
            .hosts
            .flatMap(\.rows)
            .first(where: { $0.ruleId == ruleId })?
            .runtimeId else {
            runRecoveryError = BridgeErrorInfo(
                code: .invalidDemoAction,
                summary: "未找到可停止的运行实例",
                detail: "rule_id=\(ruleId)",
                affectedPort: nil,
                affectedRuleId: ruleId,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "重新读取运行状态后再试。"
            )
            return
        }

        stopRuntimeInstance(runtimeId: runtimeId)
    }

    func reloadCurrentSection() {
        switch selection {
        case .runAndRecovery:
            loadRunRecoverySnapshot()
        case .registry:
            loadRegistrySnapshot()
        case .logs, .diagnostics, .preferences:
            reloadDiagnosticsWorkspace()
        }
    }

    func reloadDiagnosticsWorkspace() {
        loadRunRecoverySnapshot()
        loadRegistrySnapshot()
    }

    func collapseAllRunRecoveryHosts() {
        runRecoveryCollapseCommand = RunRecoveryCollapseCommand(kind: .collapseAll)
    }

    func expandAllRunRecoveryHosts() {
        runRecoveryCollapseCommand = RunRecoveryCollapseCommand(kind: .expandAll)
    }

    func stopAllRunningRuntimes() {
        guard let rows = runRecoverySnapshot?.hosts.flatMap(\.rows) else {
            return
        }

        rows.compactMap(\.runtimeId).forEach(stopRuntimeInstance)
    }

    func clearAllRecoveryItems() {
        guard let rows = runRecoverySnapshot?.hosts.flatMap(\.rows) else {
            return
        }

        rows.compactMap(\.recoveryId).forEach(clearRecoveryItem)
    }

    func loadRegistrySnapshot() {
        if let visualQAFixtures {
            applyRegistrySnapshot(visualQAFixtures.registrySnapshot)
            return
        }

        guard let bridgeExecutor else {
            registryError = BridgeErrorInfo(
                code: .processFailed,
                summary: "未找到 RelayDock bridge sidecar",
                detail: "Expected target/debug/relaydock-bridge in the development workspace.",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "Run cargo build -p relaydock-core --bin relaydock-bridge."
            )
            return
        }

        do {
            applyRegistrySnapshot(try bridgeExecutor.loadRegistrySnapshot())
        } catch {
            if let bridgeError = error as? BridgeErrorInfo {
                registryError = bridgeError
            } else {
                registryError = BridgeErrorInfo(
                    code: .internalError,
                    summary: "资源登记读取失败",
                    detail: error.localizedDescription,
                    affectedPort: nil,
                    affectedRuleId: nil,
                    affectedRuntimeId: nil,
                    affectedRecoveryId: nil,
                    suggestedRecovery: nil
                )
            }
        }
    }

    func saveRegistryHost(_ host: RegistryHostDraft) throws -> RegistrySnapshotResult {
        guard let bridgeExecutor else {
            throw BridgeErrorInfo(
                code: .processFailed,
                summary: "未找到 RelayDock bridge sidecar",
                detail: "Expected target/debug/relaydock-bridge in the development workspace.",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "Run cargo build -p relaydock-core --bin relaydock-bridge."
            )
        }

        let snapshot = try bridgeExecutor.saveRegistryHost(host)
        applyRegistrySnapshot(snapshot)
        return snapshot
    }

    func parseSshCommand(_ commandText: String) throws -> ParseSshCommandResult {
        guard let bridgeExecutor else {
            throw BridgeErrorInfo(
                code: .processFailed,
                summary: "未找到 RelayDock bridge sidecar",
                detail: "Expected target/debug/relaydock-bridge in the development workspace.",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "Run cargo build -p relaydock-core --bin relaydock-bridge."
            )
        }

        return try bridgeExecutor.parseSshCommand(commandText)
    }

    func testProviderTargetConnectivity(
        targetAddress: String,
        targetPort: UInt16
    ) throws -> ProviderTargetConnectivityResult {
        guard let bridgeExecutor else {
            throw BridgeErrorInfo(
                code: .processFailed,
                summary: "未找到 RelayDock bridge sidecar",
                detail: "Expected target/debug/relaydock-bridge in the development workspace.",
                affectedPort: targetPort,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "Run cargo build -p relaydock-core --bin relaydock-bridge."
            )
        }

        return try bridgeExecutor.testProviderTargetConnectivity(
            targetAddress: targetAddress,
            targetPort: targetPort
        )
    }

    func saveRegistryRule(_ rule: RegistryRuleDraft) throws -> RegistrySnapshotResult {
        guard let bridgeExecutor else {
            throw BridgeErrorInfo(
                code: .processFailed,
                summary: "未找到 RelayDock bridge sidecar",
                detail: "Expected target/debug/relaydock-bridge in the development workspace.",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "Run cargo build -p relaydock-core --bin relaydock-bridge."
            )
        }

        let snapshot = try bridgeExecutor.saveRegistryRule(rule)
        applyRegistrySnapshot(snapshot)
        return snapshot
    }

    private func applySnapshot(_ snapshot: RunRecoverySnapshotResult) {
        runRecoverySnapshot = snapshot
        runRecoveryError = snapshot.lastAction?.error
    }

    private func applyRegistrySnapshot(_ snapshot: RegistrySnapshotResult) {
        registrySnapshot = snapshot
        registryError = nil
        if snapshot.hosts.isEmpty {
            selectedRegistryHostId = nil
            return
        }

        if let selectedRegistryHostId,
           snapshot.hosts.contains(where: { $0.id == selectedRegistryHostId }) {
            return
        }

        selectedRegistryHostId = snapshot.selectedHostId
    }

    private func applyBridgeFailure(_ error: Error) {
        if let bridgeError = error as? BridgeErrorInfo {
            runRecoveryError = bridgeError
        } else {
            runRecoveryError = BridgeErrorInfo(
                code: .internalError,
                summary: "运行数据读取失败",
                detail: error.localizedDescription,
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: nil
            )
        }
    }
}

struct RunRecoveryCollapseCommand: Identifiable, Equatable {
    let id = UUID()
    var kind: RunRecoveryCollapseCommandKind
}

enum RunRecoveryCollapseCommandKind: Equatable {
    case collapseAll
    case expandAll
}

struct RegistryShellCommand: Identifiable, Equatable {
    let id = UUID()
    var kind: RegistryShellCommandKind
}

enum RegistryShellCommandKind: Equatable {
    case newHost
}

enum RelayDockSection: String, CaseIterable, Identifiable {
    case runAndRecovery
    case registry
    case logs
    case diagnostics
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runAndRecovery:
            "运行与恢复"
        case .registry:
            "资源登记"
        case .logs:
            "日志"
        case .diagnostics:
            "诊断"
        case .preferences:
            "偏好设置"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .runAndRecovery:
            "waveform.path.ecg"
        case .registry:
            "server.rack"
        case .logs:
            "doc.text"
        case .diagnostics:
            "stethoscope"
        case .preferences:
            "gearshape"
        }
    }

    var topBarSystemImage: String {
        switch self {
        case .runAndRecovery:
            "waveform.path.ecg"
        case .registry:
            "book"
        case .logs:
            "doc.text"
        case .diagnostics:
            "stethoscope"
        case .preferences:
            "gearshape"
        }
    }
}

struct StatusSummary {
    var connectedHosts: Int
    var runningForwards: Int
    var issueCount: Int
    var message: String
}

extension RelayDockBridgeExecutor {
    static func defaultDevelopmentExecutor(
        fileManager: FileManager = .default
    ) -> RelayDockBridgeExecutor? {
        guard let executableURL = findDevelopmentBridgeExecutable(fileManager: fileManager) else {
            return nil
        }

        return RelayDockBridgeExecutor(executableURL: executableURL)
    }

    private static func findDevelopmentBridgeExecutable(fileManager: FileManager) -> URL? {
        let candidates = developmentBridgeExecutableCandidates()
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func developmentBridgeExecutableCandidates() -> [URL] {
        var candidates: [URL] = []

        if let configuredPath = ProcessInfo.processInfo.environment["RELAYDOCK_BRIDGE_PATH"],
           !configuredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: configuredPath))
        }

        let currentDirectory = URL(fileURLWithPath: fileManagerCurrentDirectory())
        candidates.append(contentsOf: bridgeExecutableCandidates(from: currentDirectory))

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("relaydock-bridge"))
        }

        if let executableURL = Bundle.main.executableURL {
            candidates.append(contentsOf: bridgeExecutableCandidates(from: executableURL))
        }

        return candidates
    }

    private static func bridgeExecutableCandidates(from startURL: URL) -> [URL] {
        var candidates: [URL] = []
        var directory = startURL.hasDirectoryPath ? startURL : startURL.deletingLastPathComponent()

        for _ in 0..<8 {
            candidates.append(directory.appendingPathComponent("target/debug/relaydock-bridge"))
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        return candidates
    }

    private static func fileManagerCurrentDirectory() -> String {
        FileManager.default.currentDirectoryPath
    }
}
