import Foundation

enum RelayDockBridgeCommand: Encodable {
    case checkPortClaim(CheckPortClaimCommand)
    case parseSshCommand(ParseSshCommandCommand)
    case testProviderTargetConnectivity(TestProviderTargetConnectivityCommand)
    case loadRunRecoverySnapshot
    case loadRegistrySnapshot
    case saveRegistryHost(SaveRegistryHostCommand)
    case saveRegistryRule(SaveRegistryRuleCommand)
    case startRule(StartRuleCommand)
    case stopRuntimeInstance(StopRuntimeInstanceCommand)
    case retryRuntimeInstance(RetryRuntimeInstanceCommand)
    case recoverItem(RecoverItemCommand)
    case applyLocalPortOverride(ApplyLocalPortOverrideCommand)
    case clearRecoveryItem(ClearRecoveryItemCommand)

    private enum CodingKeys: String, CodingKey {
        case command
        case claim
        case commandText = "command_text"
        case knownUsages = "known_usages"
        case targetAddress = "target_address"
        case targetPort = "target_port"
        case timeoutMillis = "timeout_millis"
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
        case let .testProviderTargetConnectivity(command):
            try container.encode("test_provider_target_connectivity", forKey: .command)
            try container.encode(command.targetAddress, forKey: .targetAddress)
            try container.encode(command.targetPort, forKey: .targetPort)
            try container.encode(command.timeoutMillis, forKey: .timeoutMillis)
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
        case let .retryRuntimeInstance(command):
            try container.encode("retry_runtime_instance", forKey: .command)
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

struct TestProviderTargetConnectivityCommand: Codable, Equatable {
    var targetAddress: String
    var targetPort: UInt16
    var timeoutMillis: UInt64
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

struct RetryRuntimeInstanceCommand: Codable, Equatable {
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
    var accessMode: RegistryRuleAccessMode
    var providerTargetId: String?
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
    case providerTargetConnectivity(ProviderTargetConnectivityResult)
    case sshCommandParse(ParseSshCommandResult)
    case runRecoverySnapshot(RunRecoverySnapshotResult)
    case registrySnapshot(RegistrySnapshotResult)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ResultType: String, Decodable {
        case portClaimCheck = "port_claim_check"
        case providerTargetConnectivity = "provider_target_connectivity"
        case sshCommandParse = "ssh_command_parse"
        case runRecoverySnapshot = "run_recovery_snapshot"
        case registrySnapshot = "registry_snapshot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(ResultType.self, forKey: .type) {
        case .portClaimCheck:
            self = .portClaimCheck(try PortClaimCheckResult(from: decoder))
        case .providerTargetConnectivity:
            self = .providerTargetConnectivity(try ProviderTargetConnectivityResult(from: decoder))
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

struct ProviderTargetConnectivityResult: Codable, Equatable {
    var targetAddress: String
    var targetPort: UInt16
    var reachable: Bool
    var latencyMillis: UInt64?
    var checkedAtEpochSeconds: UInt64
    var diagnostic: ProviderTargetConnectivityDiagnostic?
}

struct ProviderTargetConnectivityDiagnostic: Codable, Equatable {
    var code: ProviderTargetConnectivityDiagnosticCode
    var summary: String
    var detail: String?
}

enum ProviderTargetConnectivityDiagnosticCode: String, Codable {
    case invalidTarget = "invalid_target"
    case dnsResolutionFailed = "dns_resolution_failed"
    case connectFailed = "connect_failed"
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
    var events: [RunRecoveryEvent]

    init(
        refreshedAtEpochSeconds: UInt64,
        hosts: [RunRecoveryHost],
        summary: RunRecoverySummary,
        lastAction: RunRecoveryActionStatus?,
        events: [RunRecoveryEvent] = []
    ) {
        self.refreshedAtEpochSeconds = refreshedAtEpochSeconds
        self.hosts = hosts
        self.summary = summary
        self.lastAction = lastAction
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case refreshedAtEpochSeconds
        case hosts
        case summary
        case lastAction
        case events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshedAtEpochSeconds = try container.decode(UInt64.self, forKey: .refreshedAtEpochSeconds)
        hosts = try container.decode([RunRecoveryHost].self, forKey: .hosts)
        summary = try container.decode(RunRecoverySummary.self, forKey: .summary)
        lastAction = try container.decodeIfPresent(RunRecoveryActionStatus.self, forKey: .lastAction)
        events = try container.decodeIfPresent([RunRecoveryEvent].self, forKey: .events) ?? []
    }
}

struct RunRecoveryHost: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var endpoint: String
    var providerSummary: String
    var healthSummary: String?
    var rows: [RunRecoveryRow]

    init(
        id: String,
        name: String,
        endpoint: String,
        providerSummary: String,
        healthSummary: String? = nil,
        rows: [RunRecoveryRow]
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.providerSummary = providerSummary
        self.healthSummary = healthSummary
        self.rows = rows
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case endpoint
        case providerSummary
        case healthSummary
        case rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        providerSummary = try container.decode(String.self, forKey: .providerSummary)
        healthSummary = try container.decodeIfPresent(String.self, forKey: .healthSummary)
        rows = try container.decode([RunRecoveryRow].self, forKey: .rows)
    }
}

struct RunRecoveryEvent: Codable, Equatable, Identifiable {
    var id: String
    var level: RunRecoveryEventLevel
    var kind: String
    var occurredAtEpochSeconds: UInt64
    var component: String
    var summary: String
    var detail: String?
    var hostId: String?
    var ruleId: String?
    var runtimeId: String?
    var providerTargetId: String?
}

enum RunRecoveryEventLevel: String, Codable {
    case info
    case notice
    case warning
    case error
}

struct RunRecoveryRow: Codable, Equatable, Identifiable {
    var id: String
    var ruleId: String
    var runtimeId: String?
    var recoveryId: String?
    var hostId: String
    var serviceName: String
    var alias: String
    var entryUrl: String?
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

enum RegistryRuleAccessMode: String, Codable {
    case forwarded
    case direct
    case local
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
    var accessMode: RegistryRuleAccessMode
    var providerLabel: String
    var portSummary: String
    var runtimeState: RegistryRuleRuntimeState
    var providerTargetId: String?
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
