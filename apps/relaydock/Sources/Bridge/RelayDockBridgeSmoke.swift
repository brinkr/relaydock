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
}

