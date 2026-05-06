import Foundation

enum RelayDockBridgeCommand: Encodable {
    case checkPortClaim(CheckPortClaimCommand)
    case parseSshCommand(ParseSshCommandCommand)
    case loadRunRecoverySnapshot
    case loadRegistrySnapshot
    case saveRegistryHost(SaveRegistryHostCommand)
    case saveRegistryRule(SaveRegistryRuleCommand)
    case startRule(StartRuleCommand)
    case stopRuntimeInstance(StopRuntimeInstanceCommand)
    case recoverItem(RecoverItemCommand)
    case applyLocalPortOverride(ApplyLocalPortOverrideCommand)
    case clearRecoveryItem(ClearRecoveryItemCommand)
    case startDemoRule(DemoRuleActionCommand)
    case retryDemoRuntime(DemoRuntimeActionCommand)
    case stopDemoRuntime(DemoRuntimeActionCommand)
    case clearDemoRecoveryItem(DemoRecoveryActionCommand)
    case applyDemoLocalPortOverride(DemoLocalPortOverrideCommand)

    private enum CodingKeys: String, CodingKey {
        case command
        case claim
        case commandText = "command_text"
        case knownUsages = "known_usages"
        case host
        case rule
        case ruleId = "rule_id"
        case runtimeId = "runtime_id"
        case recoveryId = "recovery_id"
        case localPort = "local_port"
        case snapshot
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .checkPortClaim(command):
            try container.encode("check_port_claim", forKey: .command)
            try container.encode(command.claim, forKey: .claim)
            try container.encode(command.knownUsages, forKey: .knownUsages)
        case let .parseSshCommand(command):
            try container.encode("parse_ssh_command", forKey: .command)
            try container.encode(command.commandText, forKey: .commandText)
        case .loadRunRecoverySnapshot:
            try container.encode("load_run_recovery_snapshot", forKey: .command)
        case .loadRegistrySnapshot:
            try container.encode("load_registry_snapshot", forKey: .command)
        case let .saveRegistryHost(command):
            try container.encode("save_registry_host", forKey: .command)
            try container.encode(command.host, forKey: .host)
        case let .saveRegistryRule(command):
            try container.encode("save_registry_rule", forKey: .command)
            try container.encode(command.rule, forKey: .rule)
        case let .startRule(command):
            try container.encode("start_rule", forKey: .command)
            try container.encode(command.ruleId, forKey: .ruleId)
        case let .stopRuntimeInstance(command):
            try container.encode("stop_runtime_instance", forKey: .command)
            try container.encode(command.runtimeId, forKey: .runtimeId)
        case let .recoverItem(command):
            try container.encode("recover_item", forKey: .command)
            try container.encode(command.ruleId, forKey: .ruleId)
        case let .applyLocalPortOverride(command):
            try container.encode("apply_local_port_override", forKey: .command)
            try container.encode(command.ruleId, forKey: .ruleId)
            try container.encode(command.localPort, forKey: .localPort)
        case let .clearRecoveryItem(command):
            try container.encode("clear_recovery_item", forKey: .command)
            try container.encode(command.recoveryId, forKey: .recoveryId)
        case let .startDemoRule(command):
            try container.encode("start_demo_rule", forKey: .command)
            try container.encode(command.ruleId, forKey: .ruleId)
            try container.encode(command.snapshot, forKey: .snapshot)
        case let .retryDemoRuntime(command):
            try container.encode("retry_demo_runtime", forKey: .command)
            try container.encode(command.runtimeId, forKey: .runtimeId)
            try container.encode(command.snapshot, forKey: .snapshot)
        case let .stopDemoRuntime(command):
            try container.encode("stop_demo_runtime", forKey: .command)
            try container.encode(command.runtimeId, forKey: .runtimeId)
            try container.encode(command.snapshot, forKey: .snapshot)
        case let .clearDemoRecoveryItem(command):
            try container.encode("clear_demo_recovery_item", forKey: .command)
            try container.encode(command.recoveryId, forKey: .recoveryId)
            try container.encode(command.snapshot, forKey: .snapshot)
        case let .applyDemoLocalPortOverride(command):
            try container.encode("apply_demo_local_port_override", forKey: .command)
            try container.encode(command.ruleId, forKey: .ruleId)
            try container.encode(command.localPort, forKey: .localPort)
            try container.encode(command.snapshot, forKey: .snapshot)
        }
    }
}

struct CheckPortClaimCommand: Codable, Equatable {
    var claim: BridgePortClaim
    var knownUsages: [BridgePortUsage]
}

struct ParseSshCommandCommand: Codable, Equatable {
    var commandText: String
}

struct DemoRuleActionCommand: Codable, Equatable {
    var ruleId: String
    var snapshot: RunRecoverySnapshotResult
}

struct DemoRuntimeActionCommand: Codable, Equatable {
    var runtimeId: String
    var snapshot: RunRecoverySnapshotResult
}

struct DemoLocalPortOverrideCommand: Codable, Equatable {
    var ruleId: String
    var localPort: UInt16
    var snapshot: RunRecoverySnapshotResult
}

struct DemoRecoveryActionCommand: Codable, Equatable {
    var recoveryId: String
    var snapshot: RunRecoverySnapshotResult
}

struct SaveRegistryHostCommand: Codable, Equatable {
    var host: RegistryHostDraft
}

struct SaveRegistryRuleCommand: Codable, Equatable {
    var rule: RegistryRuleDraft
}

struct StartRuleCommand: Codable, Equatable {
    var ruleId: String
}

struct StopRuntimeInstanceCommand: Codable, Equatable {
    var runtimeId: String
}

struct RecoverItemCommand: Codable, Equatable {
    var ruleId: String
}

struct ApplyLocalPortOverrideCommand: Codable, Equatable {
    var ruleId: String
    var localPort: UInt16
}

struct ClearRecoveryItemCommand: Codable, Equatable {
    var recoveryId: String
}

struct RegistryHostDraft: Codable, Equatable {
    var id: String?
    var name: String
    var address: String
    var port: UInt16?
    var user: String?
    var tags: [String]
    var osHint: RegistryHostOsHint
    var osDistro: String?
    var status: RegistryHostStatus
    var providerTargets: [RegistryProviderTargetDraft]
}

struct RegistryProviderTargetDraft: Codable, Equatable, Identifiable {
    var id: String?
    var label: String
    var kind: RegistryProviderKind
    var targetAddress: String
    var targetPort: UInt16?

    var identity: String {
        id ?? [label, targetAddress, kind.rawValue].joined(separator: "::")
    }

    var stableId: String { identity }
}

struct RegistryRuleDraft: Codable, Equatable {
    var id: String?
    var hostId: String
    var serviceName: String
    var alias: String?
    var providerTargetId: String
    var remoteHost: String
    var mainLocalPort: UInt16
    var mainRemoteHost: String
    var mainRemotePort: UInt16
    var secondaryPorts: [RegistryPortMapping]
    var kind: String?
    var tags: [String]
    var notes: String?
}

struct BridgeResponse: Decodable, Equatable {
    var ok: Bool
    var result: BridgeCommandResult?
    var error: BridgeErrorInfo?
}

enum BridgeCommandResult: Decodable, Equatable {
    case portClaimCheck(PortClaimCheckResult)
    case sshCommandParse(ParseSshCommandResult)
    case runRecoverySnapshot(RunRecoverySnapshotResult)
    case registrySnapshot(RegistrySnapshotResult)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ResultType: String, Decodable {
        case portClaimCheck = "port_claim_check"
        case sshCommandParse = "ssh_command_parse"
        case runRecoverySnapshot = "run_recovery_snapshot"
        case registrySnapshot = "registry_snapshot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(ResultType.self, forKey: .type) {
        case .portClaimCheck:
            self = .portClaimCheck(try PortClaimCheckResult(from: decoder))
        case .sshCommandParse:
            self = .sshCommandParse(try ParseSshCommandResult(from: decoder))
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

struct ParseSshCommandResult: Codable, Equatable {
    var destinationHint: SshDestinationHint?
    var providerTargetHint: SshProviderTargetHint?
    var ruleDrafts: [SshImportedRuleDraft]
    var diagnostics: [SshCommandParseDiagnostic]
}

struct SshDestinationHint: Codable, Equatable {
    var host: String
    var user: String?
    var port: UInt16?
}

struct SshProviderTargetHint: Codable, Equatable {
    var targetAddress: String
    var targetPort: UInt16?
    var user: String?
}

struct SshImportedRuleDraft: Codable, Equatable {
    var forwardIndex: Int
    var serviceName: String
    var alias: String?
    var remoteHost: String
    var localPort: UInt16
    var remotePort: UInt16
    var kind: String?
    var tags: [String]
}

struct SshCommandParseDiagnostic: Codable, Equatable, Identifiable {
    var severity: SshCommandParseDiagnosticSeverity
    var summary: String
    var detail: String?
    var forwardSpec: String?

    var id: String {
        [severity.rawValue, summary, detail ?? "", forwardSpec ?? ""].joined(separator: "::")
    }
}

enum SshCommandParseDiagnosticSeverity: String, Codable {
    case warning
    case error
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
    case retry
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
    var address: String
    var port: UInt16?
    var user: String?
    var tags: [String]
    var osDistro: String?
    var providerTargets: [RegistryProviderTarget]
    var presets: [RegistryPreset]
    var rules: [RegistryRule]
}

enum RegistryHostStatus: String, Codable {
    case unknown
    case online
    case offline
}

enum RegistryHostOsHint: String, Codable {
    case macos
    case ubuntu
    case windows
    case linux
    case raspberryPi = "raspberry_pi"
    case unknown
}

struct RegistryProviderTarget: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var kind: RegistryProviderKind
    var targetAddress: String
    var targetPort: UInt16?
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
    var providerTargetId: String
    var remoteHost: String
    var mainLocalPort: UInt16
    var mainRemoteHost: String
    var mainRemotePort: UInt16
    var secondaryPorts: [RegistryPortMapping]
    var kind: String?
    var tags: [String]
    var notes: String?
}

struct RegistryPortMapping: Codable, Equatable, Identifiable {
    var localPort: UInt16
    var remoteHost: String
    var remotePort: UInt16

    var id: String {
        "\(localPort)-\(remoteHost)-\(remotePort)"
    }
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
    case registryValidationFailed = "registry_validation_failed"
    case storageFailed = "storage_failed"
    case unsupportedProviderTarget = "unsupported_provider_target"
    case invalidProviderTarget = "invalid_provider_target"
    case providerProcessFailed = "provider_process_failed"
    case runtimeLifecycleFailed = "runtime_lifecycle_failed"
    case processFailed = "process_failed"
    case responseDecodeFailed = "response_decode_failed"
}
