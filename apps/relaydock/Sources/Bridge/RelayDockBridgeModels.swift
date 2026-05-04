import Foundation

enum RelayDockBridgeCommand: Encodable {
    case checkPortClaim(CheckPortClaimCommand)

    private enum CodingKeys: String, CodingKey {
        case command
        case claim
        case knownUsages = "known_usages"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .checkPortClaim(command):
            try container.encode("check_port_claim", forKey: .command)
            try container.encode(command.claim, forKey: .claim)
            try container.encode(command.knownUsages, forKey: .knownUsages)
        }
    }
}

struct CheckPortClaimCommand: Codable, Equatable {
    var claim: BridgePortClaim
    var knownUsages: [BridgePortUsage]
}

struct BridgeResponse: Decodable, Equatable {
    var ok: Bool
    var result: BridgeCommandResult?
    var error: BridgeErrorInfo?
}

enum BridgeCommandResult: Decodable, Equatable {
    case portClaimCheck(PortClaimCheckResult)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ResultType: String, Decodable {
        case portClaimCheck = "port_claim_check"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(ResultType.self, forKey: .type) {
        case .portClaimCheck:
            self = .portClaimCheck(try PortClaimCheckResult(from: decoder))
        }
    }
}

struct PortClaimCheckResult: Codable, Equatable {
    var claim: BridgePortClaim
    var available: Bool
    var conflict: BridgePortConflict?
    var suggestedPort: UInt16?
}

struct BridgePortConflict: Codable, Equatable {
    var requested: BridgePortClaim
    var usage: BridgePortUsage
}

struct BridgePortClaim: Codable, Equatable {
    var port: UInt16
    var `protocol`: BridgePortProtocol
    var ownerType: BridgePortOwnerType
    var ownerRef: String?
}

struct BridgePortUsage: Codable, Equatable {
    var port: UInt16
    var `protocol`: BridgePortProtocol
    var pid: UInt32?
    var processName: String?
    var command: String?
    var ownerType: BridgePortOwnerType
    var ownerRef: String?
    var killable: Bool
}

enum BridgePortProtocol: String, Codable {
    case tcp = "Tcp"
    case udp = "Udp"
}

enum BridgePortOwnerType: String, Codable {
    case relayDockRuntime = "RelayDockRuntime"
    case localProcess = "LocalProcess"
    case unknown = "Unknown"
}

struct BridgeErrorInfo: Codable, Error, Equatable {
    var code: BridgeErrorCode
    var summary: String
    var detail: String?
    var affectedPort: UInt16?
    var suggestedRecovery: String?
}

enum BridgeErrorCode: String, Codable {
    case invalidCommand = "invalid_command"
    case internalError = "internal_error"
    case processFailed = "process_failed"
    case responseDecodeFailed = "response_decode_failed"
}

