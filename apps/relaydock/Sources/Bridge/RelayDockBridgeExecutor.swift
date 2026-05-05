import Foundation

final class RelayDockBridgeExecutor {
    private let executableURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(executableURL: URL) {
        self.executableURL = executableURL

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    var executablePath: String {
        executableURL.path
    }

    func execute(_ command: RelayDockBridgeCommand) throws -> BridgeCommandResult {
        let commandData = try encoder.encode(command)
        let responseData = try runBridgeProcess(commandData: commandData)
        let response = try decodeResponse(from: responseData)

        if response.ok, let result = response.result {
            return result
        }

        throw response.error ?? BridgeErrorInfo(
            code: .responseDecodeFailed,
            summary: "Bridge response did not include a result or error",
            detail: String(data: responseData, encoding: .utf8),
            affectedPort: nil,
            affectedRuleId: nil,
            affectedRuntimeId: nil,
            affectedRecoveryId: nil,
            suggestedRecovery: nil
        )
    }

    func checkPortClaim(_ command: CheckPortClaimCommand) throws -> PortClaimCheckResult {
        let result = try execute(.checkPortClaim(command))

        guard case let .portClaimCheck(portClaimResult) = result else {
            throw BridgeErrorInfo(
                code: .responseDecodeFailed,
                summary: "Bridge returned an unexpected result type",
                detail: nil,
                affectedPort: command.claim.port,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: nil
            )
        }

        return portClaimResult
    }

    func parseSshCommand(_ commandText: String) throws -> ParseSshCommandResult {
        let result = try execute(.parseSshCommand(ParseSshCommandCommand(commandText: commandText)))

        guard case let .sshCommandParse(parseResult) = result else {
            throw BridgeErrorInfo(
                code: .responseDecodeFailed,
                summary: "Bridge returned an unexpected result type",
                detail: "Expected ssh_command_parse for parse SSH command.",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: nil
            )
        }

        return parseResult
    }

    func loadRunRecoverySnapshot() throws -> RunRecoverySnapshotResult {
        let result = try execute(.loadRunRecoverySnapshot)
        return try unwrapRunRecoverySnapshot(result, actionDescription: "load run/recovery snapshot")
    }

    func loadRegistrySnapshot() throws -> RegistrySnapshotResult {
        let result = try execute(.loadRegistrySnapshot)

        guard case let .registrySnapshot(snapshot) = result else {
            throw BridgeErrorInfo(
                code: .responseDecodeFailed,
                summary: "Bridge returned an unexpected result type",
                detail: "Expected registry_snapshot for load registry snapshot.",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: nil
            )
        }

        return snapshot
    }

    func saveRegistryHost(_ host: RegistryHostDraft) throws -> RegistrySnapshotResult {
        let result = try execute(.saveRegistryHost(SaveRegistryHostCommand(host: host)))
        return try unwrapRegistrySnapshot(result, actionDescription: "save registry host")
    }

    func saveRegistryRule(_ rule: RegistryRuleDraft) throws -> RegistrySnapshotResult {
        let result = try execute(.saveRegistryRule(SaveRegistryRuleCommand(rule: rule)))
        return try unwrapRegistrySnapshot(result, actionDescription: "save registry rule")
    }

    func startRule(ruleId: String) throws -> RunRecoverySnapshotResult {
        let command = StartRuleCommand(ruleId: ruleId)
        let result = try execute(.startRule(command))
        return try unwrapRunRecoverySnapshot(result, actionDescription: "start rule")
    }

    func startDemoRule(ruleId: String, snapshot: RunRecoverySnapshotResult) throws -> RunRecoverySnapshotResult {
        let command = DemoRuleActionCommand(ruleId: ruleId, snapshot: snapshot)
        let result = try execute(.startDemoRule(command))
        return try unwrapRunRecoverySnapshot(result, actionDescription: "start demo rule")
    }

    func retryDemoRuntime(runtimeId: String, snapshot: RunRecoverySnapshotResult) throws -> RunRecoverySnapshotResult {
        let command = DemoRuntimeActionCommand(runtimeId: runtimeId, snapshot: snapshot)
        let result = try execute(.retryDemoRuntime(command))
        return try unwrapRunRecoverySnapshot(result, actionDescription: "retry demo runtime")
    }

    func stopDemoRuntime(runtimeId: String, snapshot: RunRecoverySnapshotResult) throws -> RunRecoverySnapshotResult {
        let command = DemoRuntimeActionCommand(runtimeId: runtimeId, snapshot: snapshot)
        let result = try execute(.stopDemoRuntime(command))
        return try unwrapRunRecoverySnapshot(result, actionDescription: "stop demo runtime")
    }

    func applyDemoLocalPortOverride(
        ruleId: String,
        localPort: UInt16,
        snapshot: RunRecoverySnapshotResult
    ) throws -> RunRecoverySnapshotResult {
        let command = DemoLocalPortOverrideCommand(
            ruleId: ruleId,
            localPort: localPort,
            snapshot: snapshot
        )
        let result = try execute(.applyDemoLocalPortOverride(command))
        return try unwrapRunRecoverySnapshot(result, actionDescription: "apply demo local port override")
    }

    func clearDemoRecoveryItem(
        recoveryId: String,
        snapshot: RunRecoverySnapshotResult
    ) throws -> RunRecoverySnapshotResult {
        let command = DemoRecoveryActionCommand(recoveryId: recoveryId, snapshot: snapshot)
        let result = try execute(.clearDemoRecoveryItem(command))
        return try unwrapRunRecoverySnapshot(result, actionDescription: "clear demo recovery item")
    }

    private func runBridgeProcess(commandData: Data) throws -> Data {
        let process = Process()
        process.executableURL = executableURL

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw BridgeErrorInfo(
                code: .processFailed,
                summary: "Bridge process could not be started",
                detail: error.localizedDescription,
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: "Check the configured RelayDock bridge executable path."
            )
        }

        inputPipe.fileHandleForWriting.write(commandData)
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let responseData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus == 0 {
            return responseData
        }

        if let decodedError = try? decodeResponse(from: responseData).error {
            throw decodedError
        }

        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        throw BridgeErrorInfo(
            code: .processFailed,
            summary: "Bridge process failed",
            detail: String(data: stderr, encoding: .utf8),
            affectedPort: nil,
            affectedRuleId: nil,
            affectedRuntimeId: nil,
            affectedRecoveryId: nil,
            suggestedRecovery: "Check the configured RelayDock bridge executable path."
        )
    }

    private func decodeResponse(from data: Data) throws -> BridgeResponse {
        do {
            return try decoder.decode(BridgeResponse.self, from: data)
        } catch {
            throw BridgeErrorInfo(
                code: .responseDecodeFailed,
                summary: "Bridge response JSON could not be decoded",
                detail: error.localizedDescription,
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: nil
            )
        }
    }

    private func unwrapRunRecoverySnapshot(
        _ result: BridgeCommandResult,
        actionDescription: String
    ) throws -> RunRecoverySnapshotResult {
        guard case let .runRecoverySnapshot(snapshot) = result else {
            throw BridgeErrorInfo(
                code: .responseDecodeFailed,
                summary: "Bridge returned an unexpected result type",
                detail: "Expected run_recovery_snapshot for \(actionDescription).",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: nil
            )
        }

        return snapshot
    }

    private func unwrapRegistrySnapshot(
        _ result: BridgeCommandResult,
        actionDescription: String
    ) throws -> RegistrySnapshotResult {
        guard case let .registrySnapshot(snapshot) = result else {
            throw BridgeErrorInfo(
                code: .responseDecodeFailed,
                summary: "Bridge returned an unexpected result type",
                detail: "Expected registry_snapshot for \(actionDescription).",
                affectedPort: nil,
                affectedRuleId: nil,
                affectedRuntimeId: nil,
                affectedRecoveryId: nil,
                suggestedRecovery: nil
            )
        }

        return snapshot
    }
}
