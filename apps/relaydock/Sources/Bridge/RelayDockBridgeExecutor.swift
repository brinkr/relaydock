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
                suggestedRecovery: nil
            )
        }

        return portClaimResult
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
                suggestedRecovery: nil
            )
        }
    }
}
