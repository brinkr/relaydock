import Foundation

enum RelayDockBridgeCommand: Encodable {
    case checkPortClaim(CheckPortClaimCommand)
    case loadRunRecoverySnapshot
    case loadRegistrySnapshot
    case startDemoRule(DemoRuleActionCommand)
    case stopDemoRuntime(DemoRuntimeActionCommand)
    case clearDemoRecoveryItem(DemoRecoveryActionCommand)

    private enum CodingKeys: String, CodingKey {
        case command
        case claim
        case knownUsages = "known_usages"
        case ruleId = "rule_id"
        case runtimeId = "runtime_id"
        case recoveryId = "recovery_id"
        case snapshot
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .checkPortClaim(command):
            try container.encode("check_port_claim", forKey: .command)
            try container.encode(command.claim, forKey: .claim)
            try container.encode(command.knownUsages, forKey: .knownUsages)
        case .loadRunRecoverySnapshot:
            try container.encode("load_run_recovery_snapshot", forKey: .command)
        case .loadRegistrySnapshot:
            try container.encode("load_registry_snapshot", forKey: .command)
        case let .startDemoRule(command):
            try container.encode("start_demo_rule", forKey: .command)
            try container.encode(command.ruleId, forKey: .ruleId)
            try container.encode(command.snapshot, forKey: .snapshot)
        case let .stopDemoRuntime(command):
            try container.encode("stop_demo_runtime", forKey: .command)
            try container.encode(command.runtimeId, forKey: .runtimeId)
            try container.encode(command.snapshot, forKey: .snapshot)
        case let .clearDemoRecoveryItem(command):
            try container.encode("clear_demo_recovery_item", forKey: .command)
            try container.encode(command.recoveryId, forKey: .recoveryId)
            try container.encode(command.snapshot, forKey: .snapshot)
        }
    }
}

struct CheckPortClaimCommand: Codable, Equatable {
    var claim: BridgePortClaim
    var knownUsages: [BridgePortUsage]
}

struct DemoRuleActionCommand: Codable, Equatable {
    var ruleId: String
    var snapshot: RunRecoverySnapshotResult
}

struct DemoRuntimeActionCommand: Codable, Equatable {
    var runtimeId: String
    var snapshot: RunRecoverySnapshotResult
}

struct DemoRecoveryActionCommand: Codable, Equatable {
    var recoveryId: String
    var snapshot: RunRecoverySnapshotResult
}

struct BridgeResponse: Decodable, Equatable {
    var ok: Bool
    var result: BridgeCommandResult?
    var error: BridgeErrorInfo?
}

enum BridgeCommandResult: Decodable, Equatable {
    case portClaimCheck(PortClaimCheckResult)
    case runRecoverySnapshot(RunRecoverySnapshotResult)
    case registrySnapshot(RegistrySnapshotResult)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ResultType: String, Decodable {
        case portClaimCheck = "port_claim_check"
        case runRecoverySnapshot = "run_recovery_snapshot"
        case registrySnapshot = "registry_snapshot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(ResultType.self, forKey: .type) {
        case .portClaimCheck:
            self = .portClaimCheck(try PortClaimCheckResult(from: decoder))
        case .runRecoverySnapshot:
            self = .runRecoverySnapshot(try RunRecoverySnapshotResult(from: decoder))
        case .registrySnapshot:
            self = .registrySnapshot(try RegistrySnapshotResult(from: decoder))
        }
    }
}

struct PortClaimCheckResult: Codable, Equatable {
    var claim: BridgePortClaim
    var available: Bool
    var conflict: BridgePortConflict?
    var suggestedPort: UInt16?
}

struct RunRecoverySnapshotResult: Codable, Equatable {
    var refreshedAtEpochSeconds: UInt64
    var hosts: [RunRecoveryHost]
    var summary: RunRecoverySummary
    var lastAction: RunRecoveryActionStatus?
}

struct RunRecoveryHost: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var endpoint: String
    var providerSummary: String
    var rows: [RunRecoveryRow]
}

struct RunRecoveryRow: Codable, Equatable, Identifiable {
    var id: String
    var ruleId: String
    var runtimeId: String?
    var recoveryId: String?
    var hostId: String
    var serviceName: String
    var alias: String
    var providerLabel: String
    var portSummary: String
    var state: RunRecoveryRowState
    var statusText: String
    var telemetry: String?
    var error: RunRecoveryRowError?
    var actions: [RunRecoveryAction]
}

enum RunRecoveryRowState: String, Codable {
    case connected
    case reconnecting
    case error
    case recoverable
}

struct RunRecoveryRowError: Codable, Equatable {
    var code: String
    var summary: String
    var detail: String?
}

struct RunRecoveryAction: Codable, Equatable {
    var action: RunRecoveryActionKind
    var label: String
}

enum RunRecoveryActionKind: String, Codable {
    case recover
    case changeLocalPort = "change_local_port"
    case stop
    case clear
}

struct RunRecoverySummary: Codable, Equatable {
    var connectedHosts: Int
    var runningForwards: Int
    var issueCount: Int
    var recoverableCount: Int
    var message: String
}

struct RunRecoveryActionStatus: Codable, Equatable {
    var ok: Bool
    var message: String
    var affectedRuleId: String?
    var affectedRuntimeId: String?
    var affectedRecoveryId: String?
    var error: BridgeErrorInfo?
}

struct RegistrySnapshotResult: Codable, Equatable {
    var refreshedAtEpochSeconds: UInt64
    var hosts: [RegistryHost]
    var selectedHostId: String
}

struct RegistryHost: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var endpoint: String
    var status: RegistryHostStatus
    var osHint: RegistryHostOsHint
    var providerTargets: [RegistryProviderTarget]
    var presets: [RegistryPreset]
    var rules: [RegistryRule]
}

enum RegistryHostStatus: String, Codable {
    case online
    case offline
}

enum RegistryHostOsHint: String, Codable {
    case macos
    case ubuntu
    case windows
    case linux
    case raspberryPi = "raspberry_pi"
}

struct RegistryProviderTarget: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var kind: RegistryProviderKind
}

enum RegistryProviderKind: String, Codable {
    case ssh
    case tailscale
}

struct RegistryPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var derivedFrom: String?
    var rules: [RegistryPresetRule]
}

struct RegistryPresetRule: Codable, Equatable {
    var serviceName: String
    var targetLabel: String
}

struct RegistryRule: Codable, Equatable, Identifiable {
    var id: String
    var serviceName: String
    var alias: String
    var providerLabel: String
    var portSummary: String
    var runtimeState: RegistryRuleRuntimeState
}

enum RegistryRuleRuntimeState: String, Codable {
    case running
    case recoverable
    case stopped
    case error
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
    var affectedRuleId: String?
    var affectedRuntimeId: String?
    var affectedRecoveryId: String?
    var suggestedRecovery: String?
}

enum BridgeErrorCode: String, Codable {
    case invalidCommand = "invalid_command"
    case internalError = "internal_error"
    case invalidDemoAction = "invalid_demo_action"
    case processFailed = "process_failed"
    case responseDecodeFailed = "response_decode_failed"
}
