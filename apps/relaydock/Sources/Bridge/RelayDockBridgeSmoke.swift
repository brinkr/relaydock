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
        let started = try executor.startDemoRule(ruleId: "rule-postgres-main", snapshot: loaded)
        let stopped = try executor.stopDemoRuntime(
            runtimeId: "runtime-rule-postgres-main",
            snapshot: started
        )

        return try executor.clearDemoRecoveryItem(
            recoveryId: "recovery-rule-postgres-main",
            snapshot: stopped
        )
    }
}
