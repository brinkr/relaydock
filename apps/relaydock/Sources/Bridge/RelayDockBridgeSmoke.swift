import Foundation

enum RelayDockBridgeSmoke {
    static func run(executableURL: URL) throws -> PortClaimCheckResult {
        let executor = RelayDockBridgeExecutor(executableURL: executableURL)
        let command = CheckPortClaimCommand(
            claim: BridgePortClaim(
                port: 8088,
                protocol: .tcp,
                ownerType: .relayDockRuntime,
                ownerRef: "swift-smoke"
            ),
            knownUsages: [
                BridgePortUsage(
                    port: 8088,
                    protocol: .tcp,
                    pid: 2233,
                    processName: "node",
                    command: "npm run dev",
                    ownerType: .localProcess,
                    ownerRef: nil,
                    killable: true
                )
            ]
        )

        return try executor.checkPortClaim(command)
    }

    static func runRunRecoveryFlow(executableURL: URL) throws -> RunRecoverySnapshotResult {
        let executor = RelayDockBridgeExecutor(executableURL: executableURL)
        let loaded = try executor.loadRunRecoverySnapshot()
        let retried = try executor.retryDemoRuntime(
            runtimeId: "runtime-rule-rabbitmq",
            snapshot: loaded
        )
        let recoveredWithOverride = try executor.applyDemoLocalPortOverride(
            ruleId: "rule-postgres-main",
            localPort: 15432,
            snapshot: retried
        )
        let stoppedOverride = try executor.stopDemoRuntime(
            runtimeId: "runtime-rule-postgres-main",
            snapshot: recoveredWithOverride
        )
        let clearedOverride = try executor.clearDemoRecoveryItem(
            recoveryId: "recovery-rule-postgres-main",
            snapshot: stoppedOverride
        )
        let started = try executor.startDemoRule(
            ruleId: "rule-elasticsearch",
            snapshot: clearedOverride
        )
        let stopped = try executor.stopDemoRuntime(
            runtimeId: "runtime-rule-elasticsearch",
            snapshot: started
        )

        return try executor.clearDemoRecoveryItem(
            recoveryId: "recovery-rule-elasticsearch",
            snapshot: stopped
        )
    }
}
