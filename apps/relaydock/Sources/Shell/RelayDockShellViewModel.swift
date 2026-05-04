import Foundation

@MainActor
final class RelayDockShellViewModel: ObservableObject {
    @Published var selection: RelayDockSection = .runAndRecovery
    @Published private(set) var runRecoverySnapshot: RunRecoverySnapshotResult?
    @Published private(set) var isLoadingRunRecovery = false
    @Published private(set) var runRecoveryError: BridgeErrorInfo?

    private let bridgeExecutor: RelayDockBridgeExecutor?

    init(bridgeExecutor: RelayDockBridgeExecutor? = RelayDockBridgeExecutor.defaultDevelopmentExecutor()) {
        self.bridgeExecutor = bridgeExecutor
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

    func loadRunRecoverySnapshot() {
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

    func recoverDemoRule(ruleId: String) {
        performSnapshotAction { executor, snapshot in
            try executor.startDemoRule(ruleId: ruleId, snapshot: snapshot)
        }
    }

    func stopDemoRuntime(runtimeId: String) {
        performSnapshotAction { executor, snapshot in
            try executor.stopDemoRuntime(runtimeId: runtimeId, snapshot: snapshot)
        }
    }

    func clearDemoRecoveryItem(recoveryId: String) {
        performSnapshotAction { executor, snapshot in
            try executor.clearDemoRecoveryItem(recoveryId: recoveryId, snapshot: snapshot)
        }
    }

    func changeLocalPortForDemoRule(ruleId: String) {
        runRecoveryError = BridgeErrorInfo(
            code: .invalidDemoAction,
            summary: "demo 运行流暂未实现本地端口改写",
            detail: "rule_id=\(ruleId)",
            affectedPort: nil,
            affectedRuleId: ruleId,
            affectedRuntimeId: nil,
            affectedRecoveryId: nil,
            suggestedRecovery: "当前垂直切片先覆盖恢复、停止和清除。"
        )
    }

    private func performSnapshotAction(
        _ action: (RelayDockBridgeExecutor, RunRecoverySnapshotResult) throws -> RunRecoverySnapshotResult
    ) {
        guard let bridgeExecutor else {
            loadRunRecoverySnapshot()
            return
        }

        guard let snapshot = runRecoverySnapshot else {
            loadRunRecoverySnapshot()
            return
        }

        do {
            applySnapshot(try action(bridgeExecutor, snapshot))
        } catch {
            applyBridgeFailure(error)
        }
    }

    private func applySnapshot(_ snapshot: RunRecoverySnapshotResult) {
        runRecoverySnapshot = snapshot
        runRecoveryError = snapshot.lastAction?.error
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

enum RelayDockSection: String, CaseIterable, Identifiable {
    case runAndRecovery
    case registry
    case logsAndDiagnostics
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runAndRecovery:
            "运行与恢复"
        case .registry:
            "资源登记"
        case .logsAndDiagnostics:
            "日志与诊断"
        case .preferences:
            "偏好设置"
        }
    }

    var systemImage: String {
        switch self {
        case .runAndRecovery:
            "waveform.path.ecg"
        case .registry:
            "server.rack"
        case .logsAndDiagnostics:
            "doc.text.magnifyingglass"
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
