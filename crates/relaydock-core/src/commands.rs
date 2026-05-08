use crate::domain::{
    Host as DomainHost, HostId, HostStatusHint, LocalAlias, Metadata, OsFamily, PortMapping,
    Preset as DomainPreset, ProviderTarget as DomainProviderTarget, ProviderTargetId,
    ProviderTargetType, Rule as DomainRule, RuleId, RuntimeInstanceId,
};
use crate::ports::{detect_conflict, next_available_port, PortClaim, PortConflict, PortUsage};
use crate::providers::{
    OpenSshProvider, ProviderDiagnostic, ProviderDiagnosticCode, ProviderError,
    ProviderProcessController, ProviderProcessLauncher, ProviderProcessStatus,
    SystemPidProcessController,
};
use crate::runtime::{
    uptime_seconds_since, LocalTunnelHealthChecker, OverrideReason, ProviderProcessKind,
    ProviderProcessRecord, RuntimeErrorCode, RuntimeErrorInfo, RuntimeEvent, RuntimeEventKind,
    RuntimeEventLevel, RuntimeStatus,
};
use crate::ssh_import::{parse_ssh_command, ParseSshCommandCommand, ParseSshCommandResult};
use crate::storage::{
    ConfigurationSnapshot, RecoveryCollection, RelayDockStore, RuntimeSnapshot, StorageError,
    StorageValidationError,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::time::{SystemTime, UNIX_EPOCH};
use std::time::{Duration, Instant};
#[cfg(not(test))]
use std::{env, fs, path::PathBuf};

const DEMO_REFRESHED_AT_EPOCH_SECONDS: u64 = 1_777_777_777;
const DEFAULT_CONNECTIVITY_TIMEOUT_MILLIS: u64 = 3_000;

fn default_connectivity_timeout_millis() -> u64 {
    DEFAULT_CONNECTIVITY_TIMEOUT_MILLIS
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum BridgeCommand {
    CheckPortClaim(CheckPortClaimCommand),
    ParseSshCommand(ParseSshCommandCommand),
    TestProviderTargetConnectivity(TestProviderTargetConnectivityCommand),
    LoadRunRecoverySnapshot,
    LoadRegistrySnapshot,
    SaveRegistryHost(SaveRegistryHostCommand),
    SaveRegistryRule(SaveRegistryRuleCommand),
    StartRule(StartRuleCommand),
    StopRuntimeInstance(StopRuntimeInstanceCommand),
    RetryRuntimeInstance(RetryRuntimeInstanceCommand),
    RecoverItem(RecoverItemCommand),
    ApplyLocalPortOverride(ApplyLocalPortOverrideCommand),
    ClearRecoveryItem(ClearRecoveryItemCommand),
    StartDemoRule(DemoRuleActionCommand),
    RetryDemoRuntime(DemoRuntimeActionCommand),
    StopDemoRuntime(DemoRuntimeActionCommand),
    ClearDemoRecoveryItem(DemoRecoveryActionCommand),
    ApplyDemoLocalPortOverride(DemoLocalPortOverrideCommand),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CheckPortClaimCommand {
    pub claim: PortClaim,
    #[serde(default)]
    pub known_usages: Vec<PortUsage>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TestProviderTargetConnectivityCommand {
    pub target_address: String,
    pub target_port: u16,
    #[serde(default = "default_connectivity_timeout_millis")]
    pub timeout_millis: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BridgeCommandResult {
    PortClaimCheck(PortClaimCheckResult),
    ProviderTargetConnectivity(ProviderTargetConnectivityResult),
    SshCommandParse(ParseSshCommandResult),
    RunRecoverySnapshot(RunRecoverySnapshotResult),
    RegistrySnapshot(RegistrySnapshotResult),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortClaimCheckResult {
    pub claim: PortClaim,
    pub available: bool,
    pub conflict: Option<PortConflict>,
    pub suggested_port: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderTargetConnectivityResult {
    pub target_address: String,
    pub target_port: u16,
    pub reachable: bool,
    pub latency_millis: Option<u64>,
    pub checked_at_epoch_seconds: u64,
    pub diagnostic: Option<ProviderTargetConnectivityDiagnostic>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderTargetConnectivityDiagnostic {
    pub code: ProviderTargetConnectivityDiagnosticCode,
    pub summary: String,
    pub detail: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderTargetConnectivityDiagnosticCode {
    InvalidTarget,
    DnsResolutionFailed,
    ConnectFailed,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DemoRuleActionCommand {
    pub rule_id: String,
    pub snapshot: RunRecoverySnapshotResult,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DemoRuntimeActionCommand {
    pub runtime_id: String,
    pub snapshot: RunRecoverySnapshotResult,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DemoLocalPortOverrideCommand {
    pub rule_id: String,
    pub local_port: u16,
    pub snapshot: RunRecoverySnapshotResult,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DemoRecoveryActionCommand {
    pub recovery_id: String,
    pub snapshot: RunRecoverySnapshotResult,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SaveRegistryHostCommand {
    pub host: RegistryHostDraft,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SaveRegistryRuleCommand {
    pub rule: RegistryRuleDraft,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StartRuleCommand {
    pub rule_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StopRuntimeInstanceCommand {
    pub runtime_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RetryRuntimeInstanceCommand {
    pub runtime_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecoverItemCommand {
    pub rule_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApplyLocalPortOverrideCommand {
    pub rule_id: String,
    pub local_port: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClearRecoveryItemCommand {
    pub recovery_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryHostDraft {
    pub id: Option<String>,
    pub name: String,
    pub address: String,
    pub port: Option<u16>,
    pub user: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub os_hint: RegistryHostOsHint,
    pub os_distro: Option<String>,
    pub status: RegistryHostStatus,
    #[serde(default)]
    pub provider_targets: Vec<RegistryProviderTargetDraft>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryProviderTargetDraft {
    pub id: Option<String>,
    pub label: String,
    pub kind: RegistryProviderKind,
    pub target_address: String,
    pub target_port: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryRuleDraft {
    pub id: Option<String>,
    pub host_id: String,
    pub service_name: String,
    pub alias: Option<String>,
    pub provider_target_id: String,
    pub remote_host: String,
    pub main_local_port: u16,
    pub main_remote_host: String,
    pub main_remote_port: u16,
    #[serde(default)]
    pub secondary_ports: Vec<RegistryPortMapping>,
    pub kind: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub notes: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoverySnapshotResult {
    pub refreshed_at_epoch_seconds: u64,
    pub hosts: Vec<RunRecoveryHost>,
    pub summary: RunRecoverySummary,
    pub last_action: Option<RunRecoveryActionStatus>,
    #[serde(default)]
    pub events: Vec<RunRecoveryEvent>,
}

impl RunRecoverySnapshotResult {
    fn recomputed(mut self, last_action: Option<RunRecoveryActionStatus>) -> Self {
        self.hosts.retain(|host| !host.rows.is_empty());
        self.summary = RunRecoverySummary::from_hosts(&self.hosts);
        self.refreshed_at_epoch_seconds = demo_now_epoch_seconds();
        self.last_action = last_action;
        self
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoveryHost {
    pub id: String,
    pub name: String,
    pub endpoint: String,
    pub provider_summary: String,
    #[serde(default)]
    pub health_summary: Option<String>,
    pub rows: Vec<RunRecoveryRow>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoveryEvent {
    pub id: String,
    pub level: RunRecoveryEventLevel,
    pub kind: String,
    pub occurred_at_epoch_seconds: u64,
    pub component: String,
    pub summary: String,
    pub detail: Option<String>,
    pub host_id: Option<String>,
    pub rule_id: Option<String>,
    pub runtime_id: Option<String>,
    pub provider_target_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunRecoveryEventLevel {
    Info,
    Notice,
    Warning,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoveryRow {
    pub id: String,
    pub rule_id: String,
    pub runtime_id: Option<String>,
    pub recovery_id: Option<String>,
    pub host_id: String,
    pub service_name: String,
    pub alias: String,
    pub entry_url: Option<String>,
    pub provider_label: String,
    pub port_summary: String,
    pub state: RunRecoveryRowState,
    pub status_text: String,
    pub telemetry: Option<String>,
    pub error: Option<RunRecoveryRowError>,
    pub actions: Vec<RunRecoveryAction>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunRecoveryRowState {
    Connected,
    Reconnecting,
    Error,
    Recoverable,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoveryRowError {
    pub code: String,
    pub summary: String,
    pub detail: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoveryAction {
    pub action: RunRecoveryActionKind,
    pub label: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunRecoveryActionKind {
    Recover,
    Retry,
    ChangeLocalPort,
    Stop,
    Clear,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoverySummary {
    pub connected_hosts: usize,
    pub running_forwards: usize,
    pub issue_count: usize,
    pub recoverable_count: usize,
    pub message: String,
}

impl RunRecoverySummary {
    fn from_hosts(hosts: &[RunRecoveryHost]) -> Self {
        let connected_hosts = hosts
            .iter()
            .filter(|host| {
                host.rows
                    .iter()
                    .any(|row| row.state == RunRecoveryRowState::Connected)
            })
            .count();
        let running_forwards = hosts
            .iter()
            .flat_map(|host| host.rows.iter())
            .filter(|row| {
                matches!(
                    row.state,
                    RunRecoveryRowState::Connected
                        | RunRecoveryRowState::Reconnecting
                        | RunRecoveryRowState::Error
                )
            })
            .count();
        let issue_count = hosts
            .iter()
            .flat_map(|host| host.rows.iter())
            .filter(|row| {
                matches!(
                    row.state,
                    RunRecoveryRowState::Error | RunRecoveryRowState::Reconnecting
                )
            })
            .count();
        let recoverable_count = hosts
            .iter()
            .flat_map(|host| host.rows.iter())
            .filter(|row| row.state == RunRecoveryRowState::Recoverable)
            .count();
        let message = if issue_count > 0 {
            "存在需要处理的运行异常".to_string()
        } else if recoverable_count > 0 {
            "存在可恢复的转发".to_string()
        } else if running_forwards > 0 {
            "运行状态正常".to_string()
        } else {
            "没有运行或待恢复项目".to_string()
        };

        Self {
            connected_hosts,
            running_forwards,
            issue_count,
            recoverable_count,
            message,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunRecoveryActionStatus {
    pub ok: bool,
    pub message: String,
    pub affected_rule_id: Option<String>,
    pub affected_runtime_id: Option<String>,
    pub affected_recovery_id: Option<String>,
    pub error: Option<BridgeError>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistrySnapshotResult {
    pub refreshed_at_epoch_seconds: u64,
    pub hosts: Vec<RegistryHost>,
    pub selected_host_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryHost {
    pub id: String,
    pub name: String,
    pub endpoint: String,
    pub status: RegistryHostStatus,
    pub os_hint: RegistryHostOsHint,
    pub address: String,
    pub port: Option<u16>,
    pub user: Option<String>,
    pub tags: Vec<String>,
    pub os_distro: Option<String>,
    pub provider_targets: Vec<RegistryProviderTarget>,
    pub presets: Vec<RegistryPreset>,
    pub rules: Vec<RegistryRule>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RegistryHostStatus {
    Unknown,
    Online,
    Offline,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RegistryHostOsHint {
    Macos,
    Ubuntu,
    Windows,
    Linux,
    RaspberryPi,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryProviderTarget {
    pub id: String,
    pub label: String,
    pub kind: RegistryProviderKind,
    pub target_address: String,
    pub target_port: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RegistryProviderKind {
    Ssh,
    Tailscale,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryPreset {
    pub id: String,
    pub name: String,
    pub derived_from: Option<String>,
    pub rules: Vec<RegistryPresetRule>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryPresetRule {
    pub service_name: String,
    pub target_label: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryRule {
    pub id: String,
    pub service_name: String,
    pub alias: String,
    pub provider_label: String,
    pub port_summary: String,
    pub runtime_state: RegistryRuleRuntimeState,
    pub provider_target_id: String,
    pub remote_host: String,
    pub main_local_port: u16,
    pub main_remote_host: String,
    pub main_remote_port: u16,
    pub secondary_ports: Vec<RegistryPortMapping>,
    pub kind: Option<String>,
    pub tags: Vec<String>,
    pub notes: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryPortMapping {
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RegistryRuleRuntimeState {
    Running,
    Recoverable,
    Stopped,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BridgeResponse {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<BridgeCommandResult>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<BridgeError>,
}

impl BridgeResponse {
    pub fn success(result: BridgeCommandResult) -> Self {
        Self {
            ok: true,
            result: Some(result),
            error: None,
        }
    }

    pub fn failure(error: BridgeError) -> Self {
        Self {
            ok: false,
            result: None,
            error: Some(error),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BridgeError {
    pub code: BridgeErrorCode,
    pub summary: String,
    pub detail: Option<String>,
    pub affected_port: Option<u16>,
    pub affected_rule_id: Option<String>,
    pub affected_runtime_id: Option<String>,
    pub affected_recovery_id: Option<String>,
    pub suggested_recovery: Option<String>,
}

impl BridgeError {
    pub fn invalid_command(summary: impl Into<String>, detail: Option<String>) -> Self {
        Self {
            code: BridgeErrorCode::InvalidCommand,
            summary: summary.into(),
            detail,
            affected_port: None,
            affected_rule_id: None,
            affected_runtime_id: None,
            affected_recovery_id: None,
            suggested_recovery: Some("Send one supported RelayDock bridge command as JSON.".into()),
        }
    }

    pub fn internal(summary: impl Into<String>, detail: Option<String>) -> Self {
        Self {
            code: BridgeErrorCode::InternalError,
            summary: summary.into(),
            detail,
            affected_port: None,
            affected_rule_id: None,
            affected_runtime_id: None,
            affected_recovery_id: None,
            suggested_recovery: None,
        }
    }

    pub fn invalid_demo_action(
        summary: impl Into<String>,
        detail: Option<String>,
        affected_rule_id: Option<String>,
        affected_runtime_id: Option<String>,
        affected_recovery_id: Option<String>,
    ) -> Self {
        Self {
            code: BridgeErrorCode::InvalidDemoAction,
            summary: summary.into(),
            detail,
            affected_port: None,
            affected_rule_id,
            affected_runtime_id,
            affected_recovery_id,
            suggested_recovery: Some(
                "Reload the Run/Recovery snapshot and retry the action.".into(),
            ),
        }
    }

    pub fn registry_validation(summary: impl Into<String>, detail: Option<String>) -> Self {
        Self {
            code: BridgeErrorCode::RegistryValidationFailed,
            summary: summary.into(),
            detail,
            affected_port: None,
            affected_rule_id: None,
            affected_runtime_id: None,
            affected_recovery_id: None,
            suggested_recovery: Some(
                "检查主机、provider target、规则字段是否完整，并确认引用关系没有断开。".to_string(),
            ),
        }
    }

    pub fn storage_failure(summary: impl Into<String>, detail: Option<String>) -> Self {
        Self {
            code: BridgeErrorCode::StorageFailed,
            summary: summary.into(),
            detail,
            affected_port: None,
            affected_rule_id: None,
            affected_runtime_id: None,
            affected_recovery_id: None,
            suggested_recovery: Some("检查 RelayDock 本地存储路径与写入权限。".to_string()),
        }
    }

    pub fn provider_failure(diagnostic: &ProviderDiagnostic) -> Self {
        Self {
            code: bridge_error_code_from_provider(&diagnostic.code),
            summary: diagnostic.summary.clone(),
            detail: diagnostic.detail.clone(),
            affected_port: None,
            affected_rule_id: diagnostic.rule_id.clone(),
            affected_runtime_id: diagnostic.runtime_instance_id.clone(),
            affected_recovery_id: None,
            suggested_recovery: diagnostic.suggested_recovery.clone(),
        }
    }

    pub fn runtime_lifecycle_failed(
        summary: impl Into<String>,
        detail: Option<String>,
        affected_runtime_id: Option<String>,
    ) -> Self {
        Self {
            code: BridgeErrorCode::RuntimeLifecycleFailed,
            summary: summary.into(),
            detail,
            affected_port: None,
            affected_rule_id: None,
            affected_runtime_id,
            affected_recovery_id: None,
            suggested_recovery: Some(
                "重新读取运行状态；如果进程已经退出，可清除待恢复项。".to_string(),
            ),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BridgeErrorCode {
    InvalidCommand,
    InternalError,
    InvalidDemoAction,
    RegistryValidationFailed,
    StorageFailed,
    UnsupportedProviderTarget,
    InvalidProviderTarget,
    ProviderProcessFailed,
    RuntimeLifecycleFailed,
}

pub fn execute_bridge_command(
    command: BridgeCommand,
) -> Result<BridgeCommandResult, Box<BridgeError>> {
    match command {
        BridgeCommand::CheckPortClaim(command) => Ok(BridgeCommandResult::PortClaimCheck(
            check_port_claim(command.claim, command.known_usages),
        )),
        BridgeCommand::ParseSshCommand(command) => Ok(BridgeCommandResult::SshCommandParse(
            parse_ssh_command(&command.command_text),
        )),
        BridgeCommand::TestProviderTargetConnectivity(command) => {
            Ok(BridgeCommandResult::ProviderTargetConnectivity(
                test_provider_target_connectivity(command),
            ))
        }
        BridgeCommand::LoadRunRecoverySnapshot => {
            #[cfg(test)]
            {
                Ok(BridgeCommandResult::RunRecoverySnapshot(
                    load_run_recovery_snapshot(),
                ))
            }

            #[cfg(not(test))]
            {
                Ok(BridgeCommandResult::RunRecoverySnapshot(
                    load_run_recovery_snapshot_result()?,
                ))
            }
        }
        BridgeCommand::LoadRegistrySnapshot => Ok(BridgeCommandResult::RegistrySnapshot(
            load_registry_snapshot()?,
        )),
        BridgeCommand::SaveRegistryHost(command) => Ok(BridgeCommandResult::RegistrySnapshot(
            save_registry_host(command)?,
        )),
        BridgeCommand::SaveRegistryRule(command) => Ok(BridgeCommandResult::RegistrySnapshot(
            save_registry_rule(command)?,
        )),
        BridgeCommand::StartRule(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            start_rule(command)?,
        )),
        BridgeCommand::StopRuntimeInstance(command) => Ok(
            BridgeCommandResult::RunRecoverySnapshot(stop_runtime_instance(command)?),
        ),
        BridgeCommand::RetryRuntimeInstance(command) => Ok(
            BridgeCommandResult::RunRecoverySnapshot(retry_runtime_instance(command)?),
        ),
        BridgeCommand::RecoverItem(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            recover_item(command)?,
        )),
        BridgeCommand::ApplyLocalPortOverride(command) => Ok(
            BridgeCommandResult::RunRecoverySnapshot(apply_local_port_override(command)?),
        ),
        BridgeCommand::ClearRecoveryItem(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            clear_recovery_item(command)?,
        )),
        BridgeCommand::StartDemoRule(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            start_demo_rule(command.snapshot, &command.rule_id),
        )),
        BridgeCommand::RetryDemoRuntime(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            retry_demo_runtime(command.snapshot, &command.runtime_id),
        )),
        BridgeCommand::StopDemoRuntime(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            stop_demo_runtime(command.snapshot, &command.runtime_id),
        )),
        BridgeCommand::ClearDemoRecoveryItem(command) => {
            Ok(BridgeCommandResult::RunRecoverySnapshot(
                clear_demo_recovery_item(command.snapshot, &command.recovery_id),
            ))
        }
        BridgeCommand::ApplyDemoLocalPortOverride(command) => Ok(
            BridgeCommandResult::RunRecoverySnapshot(apply_demo_local_port_override(
                command.snapshot,
                &command.rule_id,
                command.local_port,
            )),
        ),
    }
}

pub fn check_port_claim(claim: PortClaim, known_usages: Vec<PortUsage>) -> PortClaimCheckResult {
    let conflict = detect_conflict(&claim, &known_usages);
    let available = conflict.is_none();
    let suggested_port = conflict
        .as_ref()
        .and_then(|_| next_available_port(claim.port, &known_usages, claim.protocol.clone()));

    PortClaimCheckResult {
        claim,
        available,
        conflict,
        suggested_port,
    }
}

pub fn test_provider_target_connectivity(
    command: TestProviderTargetConnectivityCommand,
) -> ProviderTargetConnectivityResult {
    let target_address = command.target_address.trim().to_string();
    let target_port = command.target_port;
    let checked_at_epoch_seconds = current_epoch_seconds();
    let timeout = Duration::from_millis(command.timeout_millis.clamp(250, 10_000));

    if target_address.is_empty() || target_port == 0 {
        return ProviderTargetConnectivityResult {
            target_address,
            target_port,
            reachable: false,
            latency_millis: None,
            checked_at_epoch_seconds,
            diagnostic: Some(ProviderTargetConnectivityDiagnostic {
                code: ProviderTargetConnectivityDiagnosticCode::InvalidTarget,
                summary: "测试目标不完整".to_string(),
                detail: Some("target_address must not be empty and target_port must be 1-65535.".to_string()),
            }),
        };
    }

    let mut resolved_addrs = match (target_address.as_str(), target_port).to_socket_addrs() {
        Ok(addrs) => addrs.collect::<Vec<SocketAddr>>(),
        Err(error) => {
            return ProviderTargetConnectivityResult {
                target_address,
                target_port,
                reachable: false,
                latency_millis: None,
                checked_at_epoch_seconds,
                diagnostic: Some(ProviderTargetConnectivityDiagnostic {
                    code: ProviderTargetConnectivityDiagnosticCode::DnsResolutionFailed,
                    summary: "无法解析测试目标".to_string(),
                    detail: Some(error.to_string()),
                }),
            };
        }
    };

    if resolved_addrs.is_empty() {
        return ProviderTargetConnectivityResult {
            target_address,
            target_port,
            reachable: false,
            latency_millis: None,
            checked_at_epoch_seconds,
            diagnostic: Some(ProviderTargetConnectivityDiagnostic {
                code: ProviderTargetConnectivityDiagnosticCode::DnsResolutionFailed,
                summary: "无法解析测试目标".to_string(),
                detail: Some("Resolver returned no socket addresses.".to_string()),
            }),
        };
    }

    resolved_addrs.sort_by_key(|addr| if addr.is_ipv4() { 0 } else { 1 });
    let mut last_error = None;

    for addr in resolved_addrs {
        let started_at = Instant::now();
        match TcpStream::connect_timeout(&addr, timeout) {
            Ok(stream) => {
                let _ = stream.set_nodelay(true);
                return ProviderTargetConnectivityResult {
                    target_address,
                    target_port,
                    reachable: true,
                    latency_millis: Some(
                        started_at.elapsed().as_millis().min(u128::from(u64::MAX)) as u64
                    ),
                    checked_at_epoch_seconds,
                    diagnostic: None,
                };
            }
            Err(error) => {
                last_error = Some(format!("{addr}: {error}"));
            }
        }
    }

    ProviderTargetConnectivityResult {
        target_address,
        target_port,
        reachable: false,
        latency_millis: None,
        checked_at_epoch_seconds,
        diagnostic: Some(ProviderTargetConnectivityDiagnostic {
            code: ProviderTargetConnectivityDiagnosticCode::ConnectFailed,
            summary: "无法连接测试目标".to_string(),
            detail: last_error,
        }),
    }
}

pub fn load_run_recovery_snapshot() -> RunRecoverySnapshotResult {
    demo_run_recovery_snapshot().recomputed(None)
}

#[cfg(not(test))]
fn load_run_recovery_snapshot_result() -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    let mut store = open_registry_store()?;
    load_run_recovery_snapshot_from_store(
        &mut store,
        &SystemPidProcessController,
        &crate::runtime::TcpLocalTunnelHealthChecker::default(),
    )
}

pub fn load_registry_snapshot() -> Result<RegistrySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        load_registry_snapshot_from_store(&store)
    }

    #[cfg(not(test))]
    {
        let store = open_registry_store()?;
        load_registry_snapshot_from_store(&store)
    }
}

pub fn save_registry_host(
    command: SaveRegistryHostCommand,
) -> Result<RegistrySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        save_registry_host_to_store(&mut store, command)
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        save_registry_host_to_store(&mut store, command)
    }
}

pub fn save_registry_rule(
    command: SaveRegistryRuleCommand,
) -> Result<RegistrySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        save_registry_rule_to_store(&mut store, command)
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        save_registry_rule_to_store(&mut store, command)
    }
}

pub fn start_rule(
    command: StartRuleCommand,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        start_rule_to_store(&mut store, command, OpenSshProvider::system())
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        start_rule_to_store(&mut store, command, OpenSshProvider::system())
    }
}

pub fn stop_runtime_instance(
    command: StopRuntimeInstanceCommand,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        stop_runtime_instance_in_store(&mut store, command, SystemPidProcessController)
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        stop_runtime_instance_in_store(&mut store, command, SystemPidProcessController)
    }
}

pub fn retry_runtime_instance(
    command: RetryRuntimeInstanceCommand,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        retry_runtime_instance_in_store(&mut store, command, OpenSshProvider::system())
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        retry_runtime_instance_in_store(&mut store, command, OpenSshProvider::system())
    }
}

pub fn recover_item(
    command: RecoverItemCommand,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        recover_item_in_store(&mut store, command, OpenSshProvider::system())
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        recover_item_in_store(&mut store, command, OpenSshProvider::system())
    }
}

pub fn apply_local_port_override(
    command: ApplyLocalPortOverrideCommand,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        apply_local_port_override_in_store(&mut store, command, OpenSshProvider::system())
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        apply_local_port_override_in_store(&mut store, command, OpenSshProvider::system())
    }
}

pub fn clear_recovery_item(
    command: ClearRecoveryItemCommand,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    #[cfg(test)]
    {
        let mut store = RelayDockStore::in_memory().map_err(storage_error_to_bridge)?;
        clear_recovery_item_in_store(&mut store, command)
    }

    #[cfg(not(test))]
    {
        let mut store = open_registry_store()?;
        clear_recovery_item_in_store(&mut store, command)
    }
}

pub fn start_demo_rule(
    snapshot: RunRecoverySnapshotResult,
    rule_id: &str,
) -> RunRecoverySnapshotResult {
    let mut next_snapshot = snapshot;
    let mut recovered_row = None;

    for host in &mut next_snapshot.hosts {
        if let Some(index) = host
            .rows
            .iter()
            .position(|row| row.rule_id == rule_id && row.state == RunRecoveryRowState::Recoverable)
        {
            let row = host.rows.remove(index);
            let runtime_id = format!("runtime-{}", row.rule_id);
            recovered_row = Some(RunRecoveryRow {
                id: runtime_id.clone(),
                runtime_id: Some(runtime_id),
                recovery_id: None,
                state: RunRecoveryRowState::Connected,
                status_text: "运行中".to_string(),
                telemetry: Some("刚刚启动 · 3ms · 0次".to_string()),
                error: None,
                actions: vec![RunRecoveryAction {
                    action: RunRecoveryActionKind::Stop,
                    label: "停止".to_string(),
                }],
                ..row
            });
            break;
        }
    }

    match recovered_row {
        Some(row) => {
            insert_row(&mut next_snapshot.hosts, row);
            next_snapshot.recomputed(Some(RunRecoveryActionStatus {
                ok: true,
                message: "已恢复 demo 转发".to_string(),
                affected_rule_id: Some(rule_id.to_string()),
                affected_runtime_id: Some(format!("runtime-{rule_id}")),
                affected_recovery_id: Some(format!("recovery-{rule_id}")),
                error: None,
            }))
        }
        None => {
            let error = BridgeError::invalid_demo_action(
                "Recoverable demo rule was not found",
                Some(format!(
                    "No recoverable row for rule_id `{rule_id}` exists in the submitted snapshot."
                )),
                Some(rule_id.to_string()),
                None,
                None,
            );
            next_snapshot.recomputed(Some(RunRecoveryActionStatus {
                ok: false,
                message: error.summary.clone(),
                affected_rule_id: Some(rule_id.to_string()),
                affected_runtime_id: None,
                affected_recovery_id: None,
                error: Some(error),
            }))
        }
    }
}

pub fn retry_demo_runtime(
    snapshot: RunRecoverySnapshotResult,
    runtime_id: &str,
) -> RunRecoverySnapshotResult {
    let mut next_snapshot = snapshot;
    let mut retried = false;
    let mut affected_rule_id = None;

    for host in &mut next_snapshot.hosts {
        if let Some(row) = host.rows.iter_mut().find(|row| {
            row.runtime_id.as_deref() == Some(runtime_id)
                && matches!(
                    row.state,
                    RunRecoveryRowState::Reconnecting | RunRecoveryRowState::Error
                )
        }) {
            row.state = RunRecoveryRowState::Connected;
            row.status_text = "运行中".to_string();
            row.telemetry = Some("刚刚重试 · 4ms · 0次".to_string());
            row.error = None;
            row.actions = stop_actions();
            affected_rule_id = Some(row.rule_id.clone());
            retried = true;
            break;
        }
    }

    if retried {
        next_snapshot.recomputed(Some(RunRecoveryActionStatus {
            ok: true,
            message: "已重试 demo 转发".to_string(),
            affected_rule_id,
            affected_runtime_id: Some(runtime_id.to_string()),
            affected_recovery_id: None,
            error: None,
        }))
    } else {
        let error = BridgeError::invalid_demo_action(
            "Retryable demo runtime was not found",
            Some(format!(
                "No reconnecting or error row for runtime_id `{runtime_id}` exists in the submitted snapshot."
            )),
            None,
            Some(runtime_id.to_string()),
            None,
        );
        next_snapshot.recomputed(Some(RunRecoveryActionStatus {
            ok: false,
            message: error.summary.clone(),
            affected_rule_id: None,
            affected_runtime_id: Some(runtime_id.to_string()),
            affected_recovery_id: None,
            error: Some(error),
        }))
    }
}

pub fn stop_demo_runtime(
    snapshot: RunRecoverySnapshotResult,
    runtime_id: &str,
) -> RunRecoverySnapshotResult {
    let mut next_snapshot = snapshot;
    let mut stopped_row = None;

    for host in &mut next_snapshot.hosts {
        if let Some(index) = host.rows.iter().position(|row| {
            row.runtime_id.as_deref() == Some(runtime_id)
                && matches!(
                    row.state,
                    RunRecoveryRowState::Connected
                        | RunRecoveryRowState::Reconnecting
                        | RunRecoveryRowState::Error
                )
        }) {
            let row = host.rows.remove(index);
            stopped_row = Some(RunRecoveryRow {
                id: format!("recovery-{}", row.rule_id),
                runtime_id: None,
                recovery_id: Some(format!("recovery-{}", row.rule_id)),
                state: RunRecoveryRowState::Recoverable,
                status_text: "待恢复".to_string(),
                telemetry: None,
                error: Some(RunRecoveryRowError {
                    code: "user_stopped".to_string(),
                    summary: "用户停止，已保留为待恢复".to_string(),
                    detail: Some("demo runtime stopped through bridge command".to_string()),
                }),
                actions: recoverable_actions(),
                ..row
            });
            break;
        }
    }

    match stopped_row {
        Some(row) => {
            insert_row(&mut next_snapshot.hosts, row);
            next_snapshot.recomputed(Some(RunRecoveryActionStatus {
                ok: true,
                message: "已停止 demo 转发并加入恢复列表".to_string(),
                affected_rule_id: None,
                affected_runtime_id: Some(runtime_id.to_string()),
                affected_recovery_id: None,
                error: None,
            }))
        }
        None => {
            let error = BridgeError::invalid_demo_action(
                "Running demo runtime was not found",
                Some(format!(
                    "No running row for runtime_id `{runtime_id}` exists in the submitted snapshot."
                )),
                None,
                Some(runtime_id.to_string()),
                None,
            );
            next_snapshot.recomputed(Some(RunRecoveryActionStatus {
                ok: false,
                message: error.summary.clone(),
                affected_rule_id: None,
                affected_runtime_id: Some(runtime_id.to_string()),
                affected_recovery_id: None,
                error: Some(error),
            }))
        }
    }
}

pub fn apply_demo_local_port_override(
    snapshot: RunRecoverySnapshotResult,
    rule_id: &str,
    local_port: u16,
) -> RunRecoverySnapshotResult {
    let mut next_snapshot = snapshot;

    if local_port == 0 {
        let error = BridgeError::invalid_demo_action(
            "Local port override is invalid",
            Some("local_port must be between 1 and 65535.".to_string()),
            Some(rule_id.to_string()),
            None,
            None,
        );
        return next_snapshot.recomputed(Some(RunRecoveryActionStatus {
            ok: false,
            message: error.summary.clone(),
            affected_rule_id: Some(rule_id.to_string()),
            affected_runtime_id: None,
            affected_recovery_id: None,
            error: Some(error),
        }));
    }

    let mut recovered_row = None;

    for host in &mut next_snapshot.hosts {
        if let Some(index) = host
            .rows
            .iter()
            .position(|row| row.rule_id == rule_id && row.state == RunRecoveryRowState::Recoverable)
        {
            let row = host.rows.remove(index);
            let runtime_id = format!("runtime-{}", row.rule_id);
            recovered_row = Some(RunRecoveryRow {
                id: runtime_id.clone(),
                runtime_id: Some(runtime_id),
                recovery_id: None,
                state: RunRecoveryRowState::Connected,
                status_text: "运行中".to_string(),
                telemetry: Some(format!("临时端口 {local_port} · 5ms · 0次")),
                port_summary: format!("{local_port} -> {}", row.port_summary),
                error: None,
                actions: stop_actions(),
                ..row
            });
            break;
        }
    }

    match recovered_row {
        Some(row) => {
            insert_row(&mut next_snapshot.hosts, row);
            next_snapshot.recomputed(Some(RunRecoveryActionStatus {
                ok: true,
                message: "已用临时本地端口恢复 demo 转发".to_string(),
                affected_rule_id: Some(rule_id.to_string()),
                affected_runtime_id: Some(format!("runtime-{rule_id}")),
                affected_recovery_id: Some(format!("recovery-{rule_id}")),
                error: None,
            }))
        }
        None => {
            let error = BridgeError::invalid_demo_action(
                "Recoverable demo rule was not found",
                Some(format!(
                    "No recoverable row for rule_id `{rule_id}` exists in the submitted snapshot."
                )),
                Some(rule_id.to_string()),
                None,
                None,
            );
            next_snapshot.recomputed(Some(RunRecoveryActionStatus {
                ok: false,
                message: error.summary.clone(),
                affected_rule_id: Some(rule_id.to_string()),
                affected_runtime_id: None,
                affected_recovery_id: None,
                error: Some(error),
            }))
        }
    }
}

pub fn clear_demo_recovery_item(
    snapshot: RunRecoverySnapshotResult,
    recovery_id: &str,
) -> RunRecoverySnapshotResult {
    let mut next_snapshot = snapshot;
    let mut cleared_rule_id = None;

    for host in &mut next_snapshot.hosts {
        if let Some(index) = host.rows.iter().position(|row| {
            row.recovery_id.as_deref() == Some(recovery_id)
                && row.state == RunRecoveryRowState::Recoverable
        }) {
            let row = host.rows.remove(index);
            cleared_rule_id = Some(row.rule_id);
            break;
        }
    }

    match cleared_rule_id {
        Some(rule_id) => next_snapshot.recomputed(Some(RunRecoveryActionStatus {
            ok: true,
            message: "已清除待恢复 demo 项".to_string(),
            affected_rule_id: Some(rule_id),
            affected_runtime_id: None,
            affected_recovery_id: Some(recovery_id.to_string()),
            error: None,
        })),
        None => {
            let error = BridgeError::invalid_demo_action(
                "Recoverable demo item was not found",
                Some(format!(
                    "No recoverable row for recovery_id `{recovery_id}` exists in the submitted snapshot."
                )),
                None,
                None,
                Some(recovery_id.to_string()),
            );
            next_snapshot.recomputed(Some(RunRecoveryActionStatus {
                ok: false,
                message: error.summary.clone(),
                affected_rule_id: None,
                affected_runtime_id: None,
                affected_recovery_id: Some(recovery_id.to_string()),
                error: Some(error),
            }))
        }
    }
}

fn insert_row(hosts: &mut [RunRecoveryHost], row: RunRecoveryRow) {
    if let Some(host) = hosts.iter_mut().find(|host| host.id == row.host_id) {
        host.rows.push(row);
        host.rows
            .sort_by(|lhs, rhs| lhs.service_name.cmp(&rhs.service_name));
    }
}

fn demo_run_recovery_snapshot() -> RunRecoverySnapshotResult {
    let hosts = vec![
        RunRecoveryHost {
            id: "host-home-mac-mini".to_string(),
            name: "Mac mini (M2) - 家".to_string(),
            endpoint: "admin@192.168.1.5".to_string(),
            provider_summary: "SSH · 家庭宽带 / Tailscale · 家里".to_string(),
            health_summary: Some("SSH · 家庭宽带 · 3 运行 / 1 异常".to_string()),
            rows: vec![
                connected_demo_row(
                    "react-frontend",
                    "React 前端",
                    "react.home.localhost",
                    "3000",
                    "Tailscale · 家里",
                    "6h 12m · 2ms · 0次",
                ),
                connected_demo_row(
                    "fastapi-backend",
                    "FastAPI Backend",
                    "api.home.localhost",
                    "8000",
                    "Tailscale · 家里",
                    "6h 12m · 3ms · 0次",
                ),
                recoverable_demo_row(
                    "postgres-main",
                    "PostgreSQL Main",
                    "pg.home.localhost",
                    "5432",
                    "SSH · 家庭宽带",
                    "上次 OpenSSH 进程退出，等待手动恢复",
                ),
                connected_demo_row(
                    "redis-cache",
                    "Redis Cache",
                    "redis.home.localhost",
                    "6379",
                    "SSH · 家庭宽带",
                    "24h 05m · 1ms · 0次",
                ),
                reconnecting_demo_row(
                    "go-microservice",
                    "Go Microservice",
                    "go.home.localhost",
                    "8081",
                    "SSH · 家庭宽带",
                    "保活超时，正在重连",
                    "0m · - · 5次",
                ),
                connected_demo_row(
                    "nextjs-app",
                    "Next.js App",
                    "next.home.localhost",
                    "3001",
                    "Tailscale · 家里",
                    "2h 00m · 5ms · 2次",
                ),
                error_demo_row(
                    "rabbitmq",
                    "RabbitMQ",
                    "mq.home.localhost",
                    "5672 + 15672",
                    "SSH · 家庭宽带",
                    "本地管理端口被其它进程占用",
                    "0m · - · 12次",
                ),
                recoverable_demo_row(
                    "elasticsearch",
                    "ElasticSearch",
                    "es.home.localhost",
                    "9200",
                    "SSH · 家庭宽带",
                    "上次休眠后未自动恢复",
                ),
                recoverable_demo_row(
                    "kibana",
                    "Kibana",
                    "kibana.home.localhost",
                    "5601",
                    "SSH · 家庭宽带",
                    "等待用户确认恢复上次入口",
                ),
            ],
        },
        RunRecoveryHost {
            id: "host-ubuntu-dev".to_string(),
            name: "Ubuntu Dev Server".to_string(),
            endpoint: "root@10.0.0.12".to_string(),
            provider_summary: "SSH · 内网直连".to_string(),
            health_summary: Some("SSH · 内网 · 1 运行 / 1 异常".to_string()),
            rows: vec![
                connected_demo_row_for_host(
                    "host-ubuntu-dev",
                    "redis-cluster",
                    "Redis Cluster",
                    "redis.dev.localhost",
                    "6379",
                    "SSH · 内网",
                    "34h 10m · 45ms · 0次",
                ),
                reconnecting_demo_row_for_host(DemoRowSpec {
                    host_id: "host-ubuntu-dev",
                    slug: "docker-registry",
                    service_name: "Docker Registry",
                    alias: "docker.dev.localhost",
                    port_summary: "5000 + 5001",
                    provider_label: "SSH · 内网",
                    telemetry: "0m · - · 12次",
                    error_summary: Some("连续 3 次未收到响应"),
                }),
            ],
        },
    ];

    RunRecoverySnapshotResult {
        refreshed_at_epoch_seconds: demo_now_epoch_seconds(),
        summary: RunRecoverySummary::from_hosts(&hosts),
        hosts,
        last_action: None,
        events: Vec::new(),
    }
}

fn connected_demo_row(
    slug: &str,
    service_name: &str,
    alias: &str,
    port_summary: &str,
    provider_label: &str,
    telemetry: &str,
) -> RunRecoveryRow {
    connected_demo_row_for_host(
        "host-home-mac-mini",
        slug,
        service_name,
        alias,
        port_summary,
        provider_label,
        telemetry,
    )
}

fn connected_demo_row_for_host(
    host_id: &str,
    slug: &str,
    service_name: &str,
    alias: &str,
    port_summary: &str,
    provider_label: &str,
    telemetry: &str,
) -> RunRecoveryRow {
    RunRecoveryRow {
        id: format!("runtime-rule-{slug}"),
        rule_id: format!("rule-{slug}"),
        runtime_id: Some(format!("runtime-rule-{slug}")),
        recovery_id: None,
        host_id: host_id.to_string(),
        service_name: service_name.to_string(),
        alias: alias.to_string(),
        entry_url: entry_url_from_alias_and_ports(alias, &[first_port_from_summary(port_summary)]),
        provider_label: provider_label.to_string(),
        port_summary: port_summary.to_string(),
        state: RunRecoveryRowState::Connected,
        status_text: "运行中".to_string(),
        telemetry: Some(telemetry.to_string()),
        error: None,
        actions: stop_actions(),
    }
}

fn reconnecting_demo_row(
    slug: &str,
    service_name: &str,
    alias: &str,
    port_summary: &str,
    provider_label: &str,
    error_summary: &str,
    telemetry: &str,
) -> RunRecoveryRow {
    reconnecting_demo_row_for_host(DemoRowSpec {
        host_id: "host-home-mac-mini",
        slug,
        service_name,
        alias,
        port_summary,
        provider_label,
        telemetry,
        error_summary: Some(error_summary),
    })
}

struct DemoRowSpec<'a> {
    host_id: &'a str,
    slug: &'a str,
    service_name: &'a str,
    alias: &'a str,
    port_summary: &'a str,
    provider_label: &'a str,
    telemetry: &'a str,
    error_summary: Option<&'a str>,
}

fn reconnecting_demo_row_for_host(spec: DemoRowSpec<'_>) -> RunRecoveryRow {
    RunRecoveryRow {
        id: format!("runtime-rule-{}", spec.slug),
        rule_id: format!("rule-{}", spec.slug),
        runtime_id: Some(format!("runtime-rule-{}", spec.slug)),
        recovery_id: None,
        host_id: spec.host_id.to_string(),
        service_name: spec.service_name.to_string(),
        alias: spec.alias.to_string(),
        entry_url: entry_url_from_alias_and_ports(
            spec.alias,
            &[first_port_from_summary(spec.port_summary)],
        ),
        provider_label: spec.provider_label.to_string(),
        port_summary: spec.port_summary.to_string(),
        state: RunRecoveryRowState::Reconnecting,
        status_text: "重连中".to_string(),
        telemetry: Some(spec.telemetry.to_string()),
        error: Some(RunRecoveryRowError {
            code: "keepalive_timeout".to_string(),
            summary: spec.error_summary.unwrap_or("正在重连").to_string(),
            detail: Some("deterministic demo reconnecting runtime".to_string()),
        }),
        actions: vec![
            RunRecoveryAction {
                action: RunRecoveryActionKind::Retry,
                label: "重试".to_string(),
            },
            RunRecoveryAction {
                action: RunRecoveryActionKind::Stop,
                label: "停止".to_string(),
            },
        ],
    }
}

fn error_demo_row(
    slug: &str,
    service_name: &str,
    alias: &str,
    port_summary: &str,
    provider_label: &str,
    error_summary: &str,
    telemetry: &str,
) -> RunRecoveryRow {
    RunRecoveryRow {
        id: format!("runtime-rule-{slug}"),
        rule_id: format!("rule-{slug}"),
        runtime_id: Some(format!("runtime-rule-{slug}")),
        recovery_id: None,
        host_id: "host-home-mac-mini".to_string(),
        service_name: service_name.to_string(),
        alias: alias.to_string(),
        entry_url: entry_url_from_alias_and_ports(alias, &[first_port_from_summary(port_summary)]),
        provider_label: provider_label.to_string(),
        port_summary: port_summary.to_string(),
        state: RunRecoveryRowState::Error,
        status_text: "异常".to_string(),
        telemetry: Some(telemetry.to_string()),
        error: Some(RunRecoveryRowError {
            code: "local_port_conflict".to_string(),
            summary: error_summary.to_string(),
            detail: Some("deterministic demo error runtime".to_string()),
        }),
        actions: vec![
            RunRecoveryAction {
                action: RunRecoveryActionKind::Retry,
                label: "重试".to_string(),
            },
            RunRecoveryAction {
                action: RunRecoveryActionKind::Stop,
                label: "停止".to_string(),
            },
        ],
    }
}

fn recoverable_demo_row(
    slug: &str,
    service_name: &str,
    alias: &str,
    port_summary: &str,
    provider_label: &str,
    error_summary: &str,
) -> RunRecoveryRow {
    RunRecoveryRow {
        id: format!("recovery-rule-{slug}"),
        rule_id: format!("rule-{slug}"),
        runtime_id: None,
        recovery_id: Some(format!("recovery-rule-{slug}")),
        host_id: "host-home-mac-mini".to_string(),
        service_name: service_name.to_string(),
        alias: alias.to_string(),
        entry_url: entry_url_from_alias_and_ports(alias, &[first_port_from_summary(port_summary)]),
        provider_label: provider_label.to_string(),
        port_summary: port_summary.to_string(),
        state: RunRecoveryRowState::Recoverable,
        status_text: "待恢复".to_string(),
        telemetry: None,
        error: Some(RunRecoveryRowError {
            code: "provider_exited".to_string(),
            summary: error_summary.to_string(),
            detail: Some("deterministic demo recovery item".to_string()),
        }),
        actions: recoverable_actions(),
    }
}

fn recoverable_actions() -> Vec<RunRecoveryAction> {
    vec![
        RunRecoveryAction {
            action: RunRecoveryActionKind::Recover,
            label: "恢复".to_string(),
        },
        RunRecoveryAction {
            action: RunRecoveryActionKind::ChangeLocalPort,
            label: "改本地端口".to_string(),
        },
        RunRecoveryAction {
            action: RunRecoveryActionKind::Clear,
            label: "清除".to_string(),
        },
    ]
}

fn stop_actions() -> Vec<RunRecoveryAction> {
    vec![RunRecoveryAction {
        action: RunRecoveryActionKind::Stop,
        label: "停止".to_string(),
    }]
}

#[cfg(not(test))]
fn open_registry_store() -> Result<RelayDockStore, Box<BridgeError>> {
    let path = registry_store_path()?;

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| {
            Box::new(BridgeError::storage_failure(
                "无法创建 RelayDock 本地存储目录",
                Some(error.to_string()),
            ))
        })?;
    }

    RelayDockStore::open(path).map_err(storage_error_to_bridge)
}

#[cfg(not(test))]
fn registry_store_path() -> Result<PathBuf, Box<BridgeError>> {
    if let Some(configured) = env::var_os("RELAYDOCK_STORE_PATH") {
        return Ok(PathBuf::from(configured));
    }

    let home = env::var_os("HOME").ok_or_else(|| {
        Box::new(BridgeError::storage_failure(
            "无法确定 RelayDock 本地存储路径",
            Some("HOME environment variable is missing.".to_string()),
        ))
    })?;

    Ok(PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("RelayDock")
        .join("relaydock.sqlite3"))
}

fn load_registry_snapshot_from_store(
    store: &RelayDockStore,
) -> Result<RegistrySnapshotResult, Box<BridgeError>> {
    let snapshot = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();

    Ok(registry_snapshot_from_configuration(&snapshot, None))
}

fn load_run_recovery_snapshot_from_store(
    store: &mut RelayDockStore,
    process_controller: &impl ProviderProcessController,
    health_checker: &impl LocalTunnelHealthChecker,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    let configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let mut runtime_snapshot = store
        .load_runtime_snapshot()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let mut recovery_collection = store
        .load_recovery_collection()
        .map_err(storage_error_to_bridge)?;
    let reconciled = reconcile_runtime_processes(
        &mut runtime_snapshot,
        &mut recovery_collection,
        process_controller,
        health_checker,
        SystemTime::now(),
    )?;

    if reconciled {
        store
            .save_runtime_snapshot(&runtime_snapshot)
            .map_err(storage_error_to_bridge)?;
        store
            .save_recovery_collection(&recovery_collection)
            .map_err(storage_error_to_bridge)?;
    }

    Ok(run_recovery_snapshot_from_store_snapshots(
        &configuration,
        &runtime_snapshot,
        &recovery_collection,
        None,
    ))
}

fn save_registry_host_to_store(
    store: &mut RelayDockStore,
    command: SaveRegistryHostCommand,
) -> Result<RegistrySnapshotResult, Box<BridgeError>> {
    validate_registry_host_draft(&command.host)?;

    let mut configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let host = domain_host_from_draft(command.host)?;
    let selected_host_id = host.id.to_string();

    if let Some(index) = configuration
        .hosts
        .iter()
        .position(|existing| existing.id == host.id)
    {
        configuration.hosts[index] = host;
    } else {
        configuration.hosts.push(host);
    }

    store
        .save_configuration(&configuration)
        .map_err(storage_error_to_bridge)?;

    Ok(registry_snapshot_from_configuration(
        &configuration,
        Some(selected_host_id.as_str()),
    ))
}

fn save_registry_rule_to_store(
    store: &mut RelayDockStore,
    command: SaveRegistryRuleCommand,
) -> Result<RegistrySnapshotResult, Box<BridgeError>> {
    let rule_draft = command.rule;
    validate_registry_rule_draft(&rule_draft)?;

    let mut configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    validate_registry_rule_references(&configuration, &rule_draft)?;
    let rule = domain_rule_from_draft(rule_draft)?;
    let selected_host_id = rule.host_id.to_string();

    if let Some(index) = configuration
        .rules
        .iter()
        .position(|existing| existing.id == rule.id)
    {
        configuration.rules[index] = rule;
    } else {
        configuration.rules.push(rule);
    }

    store
        .save_configuration(&configuration)
        .map_err(storage_error_to_bridge)?;

    Ok(registry_snapshot_from_configuration(
        &configuration,
        Some(selected_host_id.as_str()),
    ))
}

fn start_rule_to_store<L>(
    store: &mut RelayDockStore,
    command: StartRuleCommand,
    provider: OpenSshProvider<L>,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>>
where
    L: ProviderProcessLauncher,
{
    let configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let rule_id = RuleId::from(command.rule_id.trim().to_string());
    let (host, rule, provider_target) = find_start_rule_context(&configuration, &rule_id)?;
    let runtime_instance_id = RuntimeInstanceId::from(format!("runtime-{rule_id}"));
    let launch_plan = provider
        .build_launch_plan(host, rule, provider_target, runtime_instance_id.clone())
        .map_err(provider_error_to_bridge)?;
    let requested_event = RuntimeEvent::new(
        RuntimeEventKind::SshStartRequested,
        RuntimeEventLevel::Info,
        "准备启动 OpenSSH 隧道",
        SystemTime::now(),
    )
    .with_detail(format!(
        "{} | bindings={}",
        launch_plan.command.display_command(),
        launch_plan
            .runtime_instance
            .local_bindings
            .iter()
            .map(|binding| format!(
                "{}:{}:{}",
                binding.local_port, binding.remote_host, binding.remote_port
            ))
            .collect::<Vec<_>>()
            .join(",")
    ))
    .with_rule_context(
        rule.host_id.clone(),
        rule.id.clone(),
        provider_target.id.clone(),
        runtime_instance_id.clone(),
    );
    let mut handle = provider
        .start_rule(host, rule, provider_target, runtime_instance_id.clone())
        .map_err(provider_error_to_bridge)?;
    let observation = handle
        .observe_status(SystemTime::now())
        .map_err(provider_error_to_bridge)?;
    let mut runtime_snapshot = store
        .load_runtime_snapshot()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    push_runtime_event(&mut runtime_snapshot, requested_event);

    let process_record = match &observation.status {
        ProviderProcessStatus::Running { pid: Some(pid) } => Some(ProviderProcessRecord {
            runtime_instance_id: runtime_instance_id.clone(),
            provider_kind: ProviderProcessKind::OpenSsh,
            pid: *pid,
            command_summary: handle.command().display_command(),
            target_label: handle.target_label().to_string(),
            started_at: observation.runtime_instance.started_at,
            last_observed_at: SystemTime::now(),
        }),
        _ => None,
    };

    upsert_runtime_instance(&mut runtime_snapshot, observation.runtime_instance);
    if let Some(process_record) = process_record {
        push_runtime_event(
            &mut runtime_snapshot,
            RuntimeEvent::new(
                RuntimeEventKind::SshStartSucceeded,
                RuntimeEventLevel::Notice,
                "OpenSSH 隧道已启动",
                SystemTime::now(),
            )
            .with_detail(format!(
                "{} | pid={}",
                process_record.command_summary, process_record.pid
            ))
            .with_rule_context(
                rule.host_id.clone(),
                rule.id.clone(),
                provider_target.id.clone(),
                runtime_instance_id.clone(),
            ),
        );
        upsert_provider_process_record(&mut runtime_snapshot, process_record);
    } else {
        let diagnostic_detail = observation
            .diagnostic
            .as_ref()
            .and_then(|diagnostic| diagnostic.detail.clone())
            .unwrap_or_else(|| "provider did not expose running pid metadata".to_string());
        push_runtime_event(
            &mut runtime_snapshot,
            RuntimeEvent::new(
                RuntimeEventKind::SshStartFailed,
                RuntimeEventLevel::Error,
                "OpenSSH 隧道启动未进入可观测运行态",
                SystemTime::now(),
            )
            .with_detail(diagnostic_detail)
            .with_rule_context(
                rule.host_id.clone(),
                rule.id.clone(),
                provider_target.id.clone(),
                runtime_instance_id.clone(),
            ),
        );
        remove_provider_process_record(&mut runtime_snapshot, &runtime_instance_id);
    }
    store
        .save_runtime_snapshot(&runtime_snapshot)
        .map_err(storage_error_to_bridge)?;

    let recovery_collection = store
        .load_recovery_collection()
        .map_err(storage_error_to_bridge)?;

    let last_action = observation.diagnostic.map_or_else(
        || {
            Some(RunRecoveryActionStatus {
                ok: true,
                message: "已启动规则".to_string(),
                affected_rule_id: Some(rule_id.to_string()),
                affected_runtime_id: Some(runtime_instance_id.to_string()),
                affected_recovery_id: Some(format!("recovery-{rule_id}")),
                error: None,
            })
        },
        |diagnostic| {
            let error = BridgeError::provider_failure(&diagnostic);
            Some(RunRecoveryActionStatus {
                ok: false,
                message: error.summary.clone(),
                affected_rule_id: Some(rule_id.to_string()),
                affected_runtime_id: Some(runtime_instance_id.to_string()),
                affected_recovery_id: Some(format!("recovery-{rule_id}")),
                error: Some(error),
            })
        },
    );

    Ok(run_recovery_snapshot_from_store_snapshots(
        &configuration,
        &runtime_snapshot,
        &recovery_collection,
        last_action,
    ))
}

fn stop_runtime_instance_in_store(
    store: &mut RelayDockStore,
    command: StopRuntimeInstanceCommand,
    process_controller: impl ProviderProcessController,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    let configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let runtime_instance_id = RuntimeInstanceId::from(command.runtime_id.trim().to_string());

    if runtime_instance_id.as_str().is_empty() {
        return Err(Box::new(BridgeError::runtime_lifecycle_failed(
            "缺少要停止的运行实例",
            Some("runtime_id must not be empty.".to_string()),
            None,
        )));
    }

    let mut runtime_snapshot = store
        .load_runtime_snapshot()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let mut recovery_collection = store
        .load_recovery_collection()
        .map_err(storage_error_to_bridge)?;
    let instance_index = runtime_snapshot
        .instances
        .iter()
        .position(|instance| instance.id == runtime_instance_id)
        .ok_or_else(|| {
            Box::new(BridgeError::runtime_lifecycle_failed(
                "未找到要停止的运行实例",
                Some(format!("runtime_id={runtime_instance_id}")),
                Some(runtime_instance_id.to_string()),
            ))
        })?;
    let process_record = runtime_snapshot
        .provider_processes
        .iter()
        .find(|process| process.runtime_instance_id == runtime_instance_id)
        .cloned()
        .ok_or_else(|| {
            Box::new(BridgeError::runtime_lifecycle_failed(
                "运行实例缺少 provider 进程信息",
                Some(format!(
                    "runtime_id={runtime_instance_id}; this sidecar cannot stop a runtime without persisted pid metadata."
                )),
                Some(runtime_instance_id.to_string()),
            ))
        })?;

    process_controller
        .terminate_pid(process_record.pid)
        .map_err(provider_error_to_bridge)?;

    let stopped_at = SystemTime::now();
    let instance = runtime_snapshot.instances.remove(instance_index);
    runtime_snapshot
        .local_port_overrides
        .retain(|override_record| override_record.runtime_instance_id != runtime_instance_id);
    remove_provider_process_record(&mut runtime_snapshot, &runtime_instance_id);
    upsert_recovery_item(&mut recovery_collection, instance.stop(stopped_at));

    store
        .save_runtime_snapshot(&runtime_snapshot)
        .map_err(storage_error_to_bridge)?;
    store
        .save_recovery_collection(&recovery_collection)
        .map_err(storage_error_to_bridge)?;

    Ok(run_recovery_snapshot_from_store_snapshots(
        &configuration,
        &runtime_snapshot,
        &recovery_collection,
        Some(RunRecoveryActionStatus {
            ok: true,
            message: "已停止运行实例并加入恢复列表".to_string(),
            affected_rule_id: None,
            affected_runtime_id: Some(runtime_instance_id.to_string()),
            affected_recovery_id: None,
            error: None,
        }),
    ))
}

fn retry_runtime_instance_in_store<L>(
    store: &mut RelayDockStore,
    command: RetryRuntimeInstanceCommand,
    provider: OpenSshProvider<L>,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>>
where
    L: ProviderProcessLauncher,
{
    let configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let runtime_instance_id = RuntimeInstanceId::from(command.runtime_id.trim().to_string());

    if runtime_instance_id.as_str().is_empty() {
        return Err(Box::new(recovery_action_error(
            "缺少要重试的运行实例",
            Some("runtime_id must not be empty.".to_string()),
            None,
            None,
            None,
        )));
    }

    let mut runtime_snapshot = store
        .load_runtime_snapshot()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let recovery_collection = store
        .load_recovery_collection()
        .map_err(storage_error_to_bridge)?;
    let instance = runtime_snapshot
        .instances
        .iter()
        .find(|instance| instance.id == runtime_instance_id)
        .cloned()
        .ok_or_else(|| {
            Box::new(recovery_action_error(
                "未找到要重试的运行实例",
                Some(format!("runtime_id={runtime_instance_id}")),
                None,
                Some(runtime_instance_id.to_string()),
                None,
            ))
        })?;

    if !matches!(
        instance.status,
        RuntimeStatus::Reconnecting | RuntimeStatus::Error
    ) {
        return Err(Box::new(recovery_action_error(
            "运行实例当前状态不可重试",
            Some(format!(
                "runtime_id={runtime_instance_id}; status={:?}; only reconnecting or error runtimes can be retried.",
                instance.status
            )),
            Some(instance.rule_id.to_string()),
            Some(runtime_instance_id.to_string()),
            None,
        )));
    }

    let (host, rule, provider_target) = find_start_rule_context(&configuration, &instance.rule_id)?;

    if rule.provider_target_id != instance.provider_target_id
        || rule.host_id != instance.host_id
        || provider_target.id != instance.provider_target_id
    {
        return Err(Box::new(recovery_action_error(
            "运行实例引用的规则或 provider 已变化",
            Some(format!(
                "runtime_id={runtime_instance_id}; rule_id={}; runtime_host_id={}; runtime_provider_target_id={}; rule_host_id={}; rule_provider_target_id={}",
                instance.rule_id,
                instance.host_id,
                instance.provider_target_id,
                rule.host_id,
                rule.provider_target_id
            )),
            Some(instance.rule_id.to_string()),
            Some(runtime_instance_id.to_string()),
            None,
        )));
    }

    let mut handle = match provider.start_rule_with_bindings(
        host,
        rule,
        provider_target,
        runtime_instance_id.clone(),
        instance.local_bindings,
    ) {
        Ok(handle) => handle,
        Err(error) => {
            remove_provider_process_record(&mut runtime_snapshot, &runtime_instance_id);
            store
                .save_runtime_snapshot(&runtime_snapshot)
                .map_err(storage_error_to_bridge)?;
            return Err(provider_error_to_bridge(error));
        }
    };
    let observation = match handle.observe_status(SystemTime::now()) {
        Ok(observation) => observation,
        Err(error) => {
            remove_provider_process_record(&mut runtime_snapshot, &runtime_instance_id);
            store
                .save_runtime_snapshot(&runtime_snapshot)
                .map_err(storage_error_to_bridge)?;
            return Err(provider_error_to_bridge(error));
        }
    };

    let mut runtime_instance = observation.runtime_instance;
    if let Some(diagnostic) = observation.diagnostic {
        let error = BridgeError::provider_failure(&diagnostic);
        upsert_runtime_instance(&mut runtime_snapshot, runtime_instance);
        remove_provider_process_record(&mut runtime_snapshot, &runtime_instance_id);
        store
            .save_runtime_snapshot(&runtime_snapshot)
            .map_err(storage_error_to_bridge)?;

        return Ok(run_recovery_snapshot_from_store_snapshots(
            &configuration,
            &runtime_snapshot,
            &recovery_collection,
            Some(RunRecoveryActionStatus {
                ok: false,
                message: error.summary.clone(),
                affected_rule_id: Some(rule.id.to_string()),
                affected_runtime_id: Some(runtime_instance_id.to_string()),
                affected_recovery_id: None,
                error: Some(error),
            }),
        ));
    }

    let pid = match observation.status {
        ProviderProcessStatus::Running { pid: Some(pid) } => pid,
        ProviderProcessStatus::Running { pid: None } => {
            remove_provider_process_record(&mut runtime_snapshot, &runtime_instance_id);
            store
                .save_runtime_snapshot(&runtime_snapshot)
                .map_err(storage_error_to_bridge)?;

            return Err(Box::new(recovery_action_error(
                "运行实例缺少 provider 进程信息",
                Some(format!(
                    "rule_id={}, runtime_id={runtime_instance_id}; this sidecar cannot persist a retried runtime without provider pid metadata.",
                    rule.id
                )),
                Some(rule.id.to_string()),
                Some(runtime_instance_id.to_string()),
                None,
            )));
        }
        ProviderProcessStatus::Exited { .. } => {
            return Err(Box::new(recovery_action_error(
                "OpenSSH 进程在重试完成前退出",
                Some(format!(
                    "rule_id={}, runtime_id={runtime_instance_id}",
                    rule.id
                )),
                Some(rule.id.to_string()),
                Some(runtime_instance_id.to_string()),
                None,
            )));
        }
    };

    for binding in &mut runtime_instance.local_bindings {
        if runtime_snapshot
            .local_port_overrides
            .iter()
            .any(|override_record| {
                override_record.runtime_instance_id == runtime_instance_id
                    && override_record.effective_port == binding.local_port
            })
        {
            binding.temporary_override = true;
        }
    }

    let process_record = ProviderProcessRecord {
        runtime_instance_id: runtime_instance_id.clone(),
        provider_kind: ProviderProcessKind::OpenSsh,
        pid,
        command_summary: handle.command().display_command(),
        target_label: handle.target_label().to_string(),
        started_at: runtime_instance.started_at,
        last_observed_at: SystemTime::now(),
    };
    let last_action = Some(RunRecoveryActionStatus {
        ok: true,
        message: "已重试运行实例".to_string(),
        affected_rule_id: Some(rule.id.to_string()),
        affected_runtime_id: Some(runtime_instance_id.to_string()),
        affected_recovery_id: None,
        error: None,
    });

    upsert_runtime_instance(&mut runtime_snapshot, runtime_instance);
    upsert_provider_process_record(&mut runtime_snapshot, process_record);

    store
        .save_runtime_snapshot(&runtime_snapshot)
        .map_err(storage_error_to_bridge)?;

    Ok(run_recovery_snapshot_from_store_snapshots(
        &configuration,
        &runtime_snapshot,
        &recovery_collection,
        last_action,
    ))
}

fn recover_item_in_store<L>(
    store: &mut RelayDockStore,
    command: RecoverItemCommand,
    provider: OpenSshProvider<L>,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>>
where
    L: ProviderProcessLauncher,
{
    recover_item_in_store_with_override(store, command.rule_id, None, provider)
}

fn apply_local_port_override_in_store<L>(
    store: &mut RelayDockStore,
    command: ApplyLocalPortOverrideCommand,
    provider: OpenSshProvider<L>,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>>
where
    L: ProviderProcessLauncher,
{
    let local_port = command.local_port;
    if local_port == 0 {
        return Err(Box::new(recovery_action_error(
            "本地端口无效",
            Some("local_port must be between 1 and 65535.".to_string()),
            Some(command.rule_id.trim().to_string()),
            None,
            Some(recovery_id_for_rule(command.rule_id.trim())),
        )));
    }

    recover_item_in_store_with_override(store, command.rule_id, Some(local_port), provider)
}

fn recover_item_in_store_with_override<L>(
    store: &mut RelayDockStore,
    rule_id: String,
    local_port_override: Option<u16>,
    provider: OpenSshProvider<L>,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>>
where
    L: ProviderProcessLauncher,
{
    let configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let rule_id = RuleId::from(rule_id.trim().to_string());

    if rule_id.as_str().is_empty() {
        return Err(Box::new(recovery_action_error(
            "缺少要恢复的规则",
            Some("rule_id must not be empty.".to_string()),
            None,
            None,
            None,
        )));
    }

    let (host, rule, provider_target) = find_start_rule_context(&configuration, &rule_id)?;
    let mut runtime_snapshot = store
        .load_runtime_snapshot()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let mut recovery_collection = store
        .load_recovery_collection()
        .map_err(storage_error_to_bridge)?;
    let recovery_index = recovery_collection.items.iter().position(|item| {
        item.rule_id == rule_id && item.provider_target_id == rule.provider_target_id
    });
    let runtime_instance_id = RuntimeInstanceId::from(format!("runtime-{rule_id}"));
    let recovery_id = recovery_id_for_rule(rule_id.as_str());

    if runtime_snapshot
        .instances
        .iter()
        .any(|instance| instance.id == runtime_instance_id || instance.rule_id == rule_id)
    {
        return Err(Box::new(recovery_action_error(
            "规则已经在运行中",
            Some(format!("rule_id={rule_id}")),
            Some(rule_id.to_string()),
            Some(runtime_instance_id.to_string()),
            Some(recovery_id),
        )));
    }

    let mut local_bindings = recovery_index
        .and_then(|index| {
            recovery_collection.items.get(index).map(|item| {
                item.clone()
                    .recover(runtime_instance_id.clone())
                    .local_bindings
            })
        })
        .unwrap_or_else(|| local_bindings_from_rule(rule));
    let original_port = local_bindings.first().map(|binding| binding.local_port);

    if let Some(local_port) = local_port_override {
        let Some(binding) = local_bindings.first_mut() else {
            return Err(Box::new(recovery_action_error(
                "规则没有可覆盖的本地端口",
                Some(format!("rule_id={rule_id}")),
                Some(rule_id.to_string()),
                None,
                Some(recovery_id),
            )));
        };

        binding.local_port = local_port;
        binding.temporary_override = true;
    }

    let mut handle = provider
        .start_rule_with_bindings(
            host,
            rule,
            provider_target,
            runtime_instance_id.clone(),
            local_bindings,
        )
        .map_err(provider_error_to_bridge)?;
    let observation = handle
        .observe_status(SystemTime::now())
        .map_err(provider_error_to_bridge)?;

    let mut runtime_instance = observation.runtime_instance;
    if let Some(diagnostic) = observation.diagnostic {
        let error = BridgeError::provider_failure(&diagnostic);
        return Ok(run_recovery_snapshot_from_store_snapshots(
            &configuration,
            &runtime_snapshot,
            &recovery_collection,
            Some(RunRecoveryActionStatus {
                ok: false,
                message: error.summary.clone(),
                affected_rule_id: Some(rule_id.to_string()),
                affected_runtime_id: Some(runtime_instance_id.to_string()),
                affected_recovery_id: Some(recovery_id),
                error: Some(error),
            }),
        ));
    }

    let pid = match observation.status {
        ProviderProcessStatus::Running { pid: Some(pid) } => pid,
        ProviderProcessStatus::Running { pid: None } => {
            return Err(Box::new(recovery_action_error(
                "运行实例缺少 provider 进程信息",
                Some(format!(
                    "rule_id={rule_id}, runtime_id={runtime_instance_id}; this sidecar cannot persist a recovered runtime without provider pid metadata."
                )),
                Some(rule_id.to_string()),
                Some(runtime_instance_id.to_string()),
                Some(recovery_id),
            )));
        }
        ProviderProcessStatus::Exited { .. } => {
            return Err(Box::new(recovery_action_error(
                "OpenSSH 进程在恢复完成前退出",
                Some(format!(
                    "rule_id={rule_id}, runtime_id={runtime_instance_id}"
                )),
                Some(rule_id.to_string()),
                Some(runtime_instance_id.to_string()),
                Some(recovery_id),
            )));
        }
    };

    if recovery_index.is_some() {
        recovery_collection.items.retain(|item| {
            !(item.rule_id == rule_id && item.provider_target_id == rule.provider_target_id)
        });
    }

    if let (Some(original_port), Some(local_port)) = (original_port, local_port_override) {
        let override_record = crate::runtime::LocalPortOverride {
            runtime_instance_id: runtime_instance_id.clone(),
            original_port,
            effective_port: local_port,
            reason: OverrideReason::Manual,
            persisted: false,
        };
        upsert_local_port_override(&mut runtime_snapshot, override_record);

        if let Some(binding) = runtime_instance
            .local_bindings
            .iter_mut()
            .find(|binding| binding.local_port == local_port)
        {
            binding.temporary_override = true;
        }
    }

    let process_record = ProviderProcessRecord {
        runtime_instance_id: runtime_instance_id.clone(),
        provider_kind: ProviderProcessKind::OpenSsh,
        pid,
        command_summary: handle.command().display_command(),
        target_label: handle.target_label().to_string(),
        started_at: runtime_instance.started_at,
        last_observed_at: SystemTime::now(),
    };
    let last_action = Some(RunRecoveryActionStatus {
        ok: true,
        message: if local_port_override.is_some() {
            "已用临时本地端口恢复规则".to_string()
        } else {
            "已恢复规则".to_string()
        },
        affected_rule_id: Some(rule_id.to_string()),
        affected_runtime_id: Some(runtime_instance_id.to_string()),
        affected_recovery_id: Some(recovery_id_for_rule(rule_id.as_str())),
        error: None,
    });

    upsert_runtime_instance(&mut runtime_snapshot, runtime_instance);
    upsert_provider_process_record(&mut runtime_snapshot, process_record);

    store
        .save_runtime_snapshot(&runtime_snapshot)
        .map_err(storage_error_to_bridge)?;
    store
        .save_recovery_collection(&recovery_collection)
        .map_err(storage_error_to_bridge)?;

    Ok(run_recovery_snapshot_from_store_snapshots(
        &configuration,
        &runtime_snapshot,
        &recovery_collection,
        last_action,
    ))
}

fn clear_recovery_item_in_store(
    store: &mut RelayDockStore,
    command: ClearRecoveryItemCommand,
) -> Result<RunRecoverySnapshotResult, Box<BridgeError>> {
    let configuration = store
        .load_configuration()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();
    let rule_id = rule_id_from_recovery_id(&command.recovery_id)?;
    let (_, rule, _) = find_start_rule_context(&configuration, &rule_id)?;
    let mut recovery_collection = store
        .load_recovery_collection()
        .map_err(storage_error_to_bridge)?;
    let persisted = recovery_collection
        .items
        .iter()
        .any(|item| item.rule_id == rule_id && item.provider_target_id == rule.provider_target_id);

    if persisted {
        recovery_collection.items.retain(|item| {
            !(item.rule_id == rule_id && item.provider_target_id == rule.provider_target_id)
        });
        store
            .save_recovery_collection(&recovery_collection)
            .map_err(storage_error_to_bridge)?;
    }

    let runtime_snapshot = store
        .load_runtime_snapshot()
        .map_err(storage_error_to_bridge)?
        .unwrap_or_default();

    Ok(run_recovery_snapshot_from_store_snapshots(
        &configuration,
        &runtime_snapshot,
        &recovery_collection,
        Some(RunRecoveryActionStatus {
            ok: true,
            message: if persisted {
                "已清除待恢复项".to_string()
            } else {
                "已保留资源登记规则".to_string()
            },
            affected_rule_id: Some(rule_id.to_string()),
            affected_runtime_id: None,
            affected_recovery_id: Some(command.recovery_id),
            error: None,
        }),
    ))
}

fn find_start_rule_context<'a>(
    configuration: &'a ConfigurationSnapshot,
    rule_id: &RuleId,
) -> Result<(&'a DomainHost, &'a DomainRule, &'a DomainProviderTarget), Box<BridgeError>> {
    let rule = configuration
        .rules
        .iter()
        .find(|rule| rule.id == *rule_id)
        .ok_or_else(|| {
            Box::new(BridgeError::registry_validation(
                "未找到要启动的规则",
                Some(format!("rule_id={rule_id}")),
            ))
        })?;
    let host = configuration
        .hosts
        .iter()
        .find(|host| host.id == rule.host_id)
        .ok_or_else(|| {
            Box::new(BridgeError::registry_validation(
                "规则引用的主机不存在",
                Some(format!("rule_id={rule_id}, host_id={}", rule.host_id)),
            ))
        })?;
    let provider_target = host
        .provider_targets
        .iter()
        .find(|target| target.id == rule.provider_target_id)
        .ok_or_else(|| {
            Box::new(BridgeError::registry_validation(
                "规则引用的 provider target 不存在",
                Some(format!(
                    "rule_id={rule_id}, provider_target_id={}",
                    rule.provider_target_id
                )),
            ))
        })?;

    Ok((host, rule, provider_target))
}

fn upsert_runtime_instance(
    runtime_snapshot: &mut RuntimeSnapshot,
    instance: crate::runtime::RuntimeInstance,
) {
    if let Some(index) = runtime_snapshot
        .instances
        .iter()
        .position(|existing| existing.id == instance.id)
    {
        runtime_snapshot.instances[index] = instance;
    } else {
        runtime_snapshot.instances.push(instance);
    }
}

fn upsert_provider_process_record(
    runtime_snapshot: &mut RuntimeSnapshot,
    process_record: ProviderProcessRecord,
) {
    if let Some(index) = runtime_snapshot
        .provider_processes
        .iter()
        .position(|existing| existing.runtime_instance_id == process_record.runtime_instance_id)
    {
        runtime_snapshot.provider_processes[index] = process_record;
    } else {
        runtime_snapshot.provider_processes.push(process_record);
    }
}

fn remove_provider_process_record(
    runtime_snapshot: &mut RuntimeSnapshot,
    runtime_instance_id: &RuntimeInstanceId,
) {
    runtime_snapshot
        .provider_processes
        .retain(|process| process.runtime_instance_id != *runtime_instance_id);
}

fn upsert_local_port_override(
    runtime_snapshot: &mut RuntimeSnapshot,
    override_record: crate::runtime::LocalPortOverride,
) {
    if let Some(index) = runtime_snapshot
        .local_port_overrides
        .iter()
        .position(|existing| {
            existing.runtime_instance_id == override_record.runtime_instance_id
                && existing.original_port == override_record.original_port
        })
    {
        runtime_snapshot.local_port_overrides[index] = override_record;
    } else {
        runtime_snapshot.local_port_overrides.push(override_record);
    }
}

fn upsert_recovery_item(
    recovery_collection: &mut RecoveryCollection,
    recovery_item: crate::runtime::RecoveryItem,
) {
    if let Some(index) = recovery_collection.items.iter().position(|existing| {
        existing.rule_id == recovery_item.rule_id
            && existing.provider_target_id == recovery_item.provider_target_id
    }) {
        recovery_collection.items[index] = recovery_item;
    } else {
        recovery_collection.items.push(recovery_item);
    }
}

fn local_bindings_from_rule(rule: &DomainRule) -> Vec<crate::runtime::LocalPortBinding> {
    std::iter::once(&rule.main_port)
        .chain(rule.secondary_ports.iter())
        .map(|mapping| {
            crate::runtime::LocalPortBinding::new(
                mapping.local_port,
                mapping.remote_host.clone(),
                mapping.remote_port,
            )
        })
        .collect()
}

fn recovery_id_for_rule(rule_id: &str) -> String {
    format!("recovery-{rule_id}")
}

fn rule_id_from_recovery_id(recovery_id: &str) -> Result<RuleId, Box<BridgeError>> {
    let trimmed = recovery_id.trim();

    if trimmed.is_empty() {
        return Err(Box::new(recovery_action_error(
            "缺少要清除的恢复项",
            Some("recovery_id must not be empty.".to_string()),
            None,
            None,
            None,
        )));
    }

    let Some(rule_id) = trimmed.strip_prefix("recovery-") else {
        return Err(Box::new(recovery_action_error(
            "恢复项标识无效",
            Some(format!("recovery_id={trimmed}")),
            None,
            None,
            Some(trimmed.to_string()),
        )));
    };

    if rule_id.trim().is_empty() {
        return Err(Box::new(recovery_action_error(
            "恢复项缺少规则标识",
            Some(format!("recovery_id={trimmed}")),
            None,
            None,
            Some(trimmed.to_string()),
        )));
    }

    Ok(RuleId::from(rule_id.to_string()))
}

fn recovery_action_error(
    summary: impl Into<String>,
    detail: Option<String>,
    affected_rule_id: Option<String>,
    affected_runtime_id: Option<String>,
    affected_recovery_id: Option<String>,
) -> BridgeError {
    BridgeError {
        code: BridgeErrorCode::RuntimeLifecycleFailed,
        summary: summary.into(),
        detail,
        affected_port: None,
        affected_rule_id,
        affected_runtime_id,
        affected_recovery_id,
        suggested_recovery: Some("重新读取运行状态后再试。".to_string()),
    }
}

fn reconcile_runtime_processes(
    runtime_snapshot: &mut RuntimeSnapshot,
    recovery_collection: &mut RecoveryCollection,
    process_controller: &impl ProviderProcessController,
    health_checker: &impl LocalTunnelHealthChecker,
    observed_at: SystemTime,
) -> Result<bool, Box<BridgeError>> {
    let mut changed = false;
    let process_records = runtime_snapshot.provider_processes.clone();

    for process_record in process_records {
        let runtime_instance_id = process_record.runtime_instance_id.clone();
        let Some(instance_index) = runtime_snapshot
            .instances
            .iter()
            .position(|instance| instance.id == runtime_instance_id)
        else {
            remove_provider_process_record(runtime_snapshot, &runtime_instance_id);
            changed = true;
            continue;
        };

        let is_running = process_controller
            .is_running(process_record.pid)
            .map_err(provider_error_to_bridge)?;

        if is_running {
            let instance = &mut runtime_snapshot.instances[instance_index];
            let health = health_checker.check(instance);
            let mut event: Option<RuntimeEvent> = None;

            if health.healthy {
                let was_connected = instance.status == RuntimeStatus::Connected;
                if !was_connected {
                    event = Some(runtime_event(
                        RuntimeEventKind::RuntimeHealthOk,
                        RuntimeEventLevel::Notice,
                        "本地隧道监听恢复可用",
                        Some(
                            "pid still exists and all loopback listener checks passed".to_string(),
                        ),
                        observed_at,
                        instance,
                    ));
                }
                instance.mark_connected(process_record.started_at.unwrap_or(observed_at));
                if !was_connected {
                    changed = true;
                }

                if let Some(started_at) = instance.started_at {
                    let uptime_seconds = uptime_seconds_since(started_at, observed_at);
                    if instance.uptime_seconds != uptime_seconds {
                        instance.uptime_seconds = uptime_seconds;
                        changed = true;
                    }
                }
            } else {
                let was_health_failure = instance.status == RuntimeStatus::Reconnecting
                    && instance.last_error.as_ref().is_some_and(|error| {
                        error.code == RuntimeErrorCode::TunnelHealthCheckFailed
                    });
                let detail = health
                    .checked_bindings
                    .iter()
                    .map(|binding| {
                        format!(
                            "local_port={} healthy={} detail={}",
                            binding.local_port,
                            binding.healthy,
                            binding.detail.as_deref().unwrap_or("-")
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("; ");
                let error = RuntimeErrorInfo::new(
                    RuntimeErrorCode::TunnelHealthCheckFailed,
                    "本地隧道监听不可达",
                )
                .with_detail(detail.clone());
                if was_health_failure {
                    instance.status = RuntimeStatus::Reconnecting;
                    instance.last_error = Some(error);
                } else {
                    instance.mark_reconnecting("本地隧道监听不可达");
                    instance.last_error = Some(error);
                    event = Some(runtime_event(
                        RuntimeEventKind::RuntimeHealthWarning,
                        RuntimeEventLevel::Warning,
                        "OpenSSH 进程仍在，但本地隧道监听不可达",
                        Some(detail),
                        observed_at,
                        instance,
                    ));
                    changed = true;
                }
                if let Some(started_at) = instance.started_at {
                    let uptime_seconds = uptime_seconds_since(started_at, observed_at);
                    if instance.uptime_seconds != uptime_seconds {
                        instance.uptime_seconds = uptime_seconds;
                        changed = true;
                    }
                }
            }

            if let Some(event) = event {
                push_runtime_event(runtime_snapshot, event);
            }
        } else {
            let instance = runtime_snapshot.instances.remove(instance_index);
            runtime_snapshot
                .local_port_overrides
                .retain(|override_record| {
                    override_record.runtime_instance_id != runtime_instance_id
                });
            remove_provider_process_record(runtime_snapshot, &runtime_instance_id);
            push_runtime_event(
                runtime_snapshot,
                runtime_event(
                    RuntimeEventKind::RuntimeRecovered,
                    RuntimeEventLevel::Notice,
                    "OpenSSH 进程已退出，运行项进入待恢复",
                    Some(format!("pid={} no longer exists", process_record.pid)),
                    observed_at,
                    &instance,
                ),
            );
            upsert_recovery_item(recovery_collection, instance.stop(observed_at));
            changed = true;
        }
    }

    let runtime_ids_with_process = runtime_snapshot
        .provider_processes
        .iter()
        .map(|process| process.runtime_instance_id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    let runtime_ids_without_process = runtime_snapshot
        .instances
        .iter()
        .filter(|instance| !runtime_ids_with_process.contains(&instance.id))
        .map(|instance| instance.id.clone())
        .collect::<Vec<_>>();

    for runtime_instance_id in runtime_ids_without_process {
        if let Some(instance_index) = runtime_snapshot
            .instances
            .iter()
            .position(|instance| instance.id == runtime_instance_id)
        {
            let instance = runtime_snapshot.instances.remove(instance_index);
            runtime_snapshot
                .local_port_overrides
                .retain(|override_record| {
                    override_record.runtime_instance_id != runtime_instance_id
                });
            upsert_recovery_item(recovery_collection, instance.stop(observed_at));
            changed = true;
        }
    }

    Ok(changed)
}

fn registry_snapshot_from_configuration(
    snapshot: &ConfigurationSnapshot,
    selected_host_id: Option<&str>,
) -> RegistrySnapshotResult {
    let selected_host_id = selected_host_id
        .filter(|candidate| {
            snapshot
                .hosts
                .iter()
                .any(|host| host.id.as_str() == *candidate)
        })
        .map(str::to_string)
        .or_else(|| snapshot.hosts.first().map(|host| host.id.to_string()))
        .unwrap_or_default();

    RegistrySnapshotResult {
        refreshed_at_epoch_seconds: current_epoch_seconds(),
        selected_host_id,
        hosts: snapshot
            .hosts
            .iter()
            .map(|host| registry_host_from_domain(snapshot, host))
            .collect(),
    }
}

fn run_recovery_snapshot_from_store_snapshots(
    configuration: &ConfigurationSnapshot,
    runtime_snapshot: &RuntimeSnapshot,
    recovery_collection: &RecoveryCollection,
    last_action: Option<RunRecoveryActionStatus>,
) -> RunRecoverySnapshotResult {
    let hosts = configuration
        .hosts
        .iter()
        .filter_map(|host| {
            run_recovery_host_from_domain(
                configuration,
                runtime_snapshot,
                recovery_collection,
                host,
            )
        })
        .collect::<Vec<_>>();

    RunRecoverySnapshotResult {
        refreshed_at_epoch_seconds: current_epoch_seconds(),
        summary: RunRecoverySummary::from_hosts(&hosts),
        hosts,
        last_action,
        events: runtime_events_from_snapshot(runtime_snapshot),
    }
}

fn run_recovery_host_from_domain(
    configuration: &ConfigurationSnapshot,
    runtime_snapshot: &RuntimeSnapshot,
    recovery_collection: &RecoveryCollection,
    host: &DomainHost,
) -> Option<RunRecoveryHost> {
    let rows = configuration
        .rules
        .iter()
        .filter(|rule| rule.host_id == host.id)
        .map(|rule| {
            run_recovery_row_from_domain(configuration, runtime_snapshot, recovery_collection, rule)
        })
        .collect::<Vec<_>>();

    if rows.is_empty() {
        return None;
    }

    Some(RunRecoveryHost {
        id: host.id.to_string(),
        name: host.name.clone(),
        endpoint: host_endpoint(host),
        provider_summary: provider_summary_for_host(host),
        health_summary: host_health_summary(configuration, runtime_snapshot, host),
        rows,
    })
}

fn run_recovery_row_from_domain(
    configuration: &ConfigurationSnapshot,
    runtime_snapshot: &RuntimeSnapshot,
    recovery_collection: &RecoveryCollection,
    rule: &DomainRule,
) -> RunRecoveryRow {
    if let Some(instance) = runtime_snapshot
        .instances
        .iter()
        .find(|instance| instance.rule_id == rule.id)
    {
        return run_recovery_row_from_runtime(configuration, rule, instance);
    }

    if let Some(recovery_item) = recovery_collection
        .items
        .iter()
        .find(|item| item.rule_id == rule.id && item.provider_target_id == rule.provider_target_id)
    {
        return run_recovery_row_from_recovery_item(configuration, rule, recovery_item);
    }

    RunRecoveryRow {
        id: format!("recovery-{}", rule.id),
        rule_id: rule.id.to_string(),
        runtime_id: None,
        recovery_id: Some(format!("recovery-{}", rule.id)),
        host_id: rule.host_id.to_string(),
        service_name: rule.name.clone(),
        alias: rule
            .alias
            .as_ref()
            .map(|alias| alias.hostname.clone())
            .unwrap_or_default(),
        entry_url: entry_url_for_rule(rule),
        provider_label: provider_label(configuration, &rule.provider_target_id),
        port_summary: port_summary(rule),
        state: RunRecoveryRowState::Recoverable,
        status_text: "待恢复".to_string(),
        telemetry: None,
        error: Some(RunRecoveryRowError {
            code: "configured_not_running".to_string(),
            summary: "已登记，等待手动恢复".to_string(),
            detail: Some("projected from saved registry configuration".to_string()),
        }),
        actions: recoverable_actions(),
    }
}

fn run_recovery_row_from_recovery_item(
    configuration: &ConfigurationSnapshot,
    rule: &DomainRule,
    recovery_item: &crate::runtime::RecoveryItem,
) -> RunRecoveryRow {
    RunRecoveryRow {
        id: format!("recovery-{}", rule.id),
        rule_id: rule.id.to_string(),
        runtime_id: None,
        recovery_id: Some(format!("recovery-{}", rule.id)),
        host_id: rule.host_id.to_string(),
        service_name: rule.name.clone(),
        alias: rule
            .alias
            .as_ref()
            .map(|alias| alias.hostname.clone())
            .unwrap_or_default(),
        entry_url: entry_url_for_recovery_item(rule, recovery_item),
        provider_label: provider_label(configuration, &recovery_item.provider_target_id),
        port_summary: recovery_port_summary(recovery_item),
        state: RunRecoveryRowState::Recoverable,
        status_text: "待恢复".to_string(),
        telemetry: None,
        error: Some(RunRecoveryRowError {
            code: recovery_status_code(&recovery_item.last_seen_status),
            summary: "上次运行已断开，等待手动恢复".to_string(),
            detail: Some("projected from persisted recovery collection".to_string()),
        }),
        actions: recoverable_actions(),
    }
}

fn run_recovery_row_from_runtime(
    configuration: &ConfigurationSnapshot,
    rule: &DomainRule,
    instance: &crate::runtime::RuntimeInstance,
) -> RunRecoveryRow {
    let state = run_recovery_state_from_runtime_status(&instance.status);
    let (status_text, actions) = match state {
        RunRecoveryRowState::Connected => ("运行中".to_string(), stop_actions()),
        RunRecoveryRowState::Reconnecting => (
            "重连中".to_string(),
            vec![
                RunRecoveryAction {
                    action: RunRecoveryActionKind::Retry,
                    label: "重试".to_string(),
                },
                RunRecoveryAction {
                    action: RunRecoveryActionKind::Stop,
                    label: "停止".to_string(),
                },
            ],
        ),
        RunRecoveryRowState::Error => (
            "异常".to_string(),
            vec![
                RunRecoveryAction {
                    action: RunRecoveryActionKind::Retry,
                    label: "重试".to_string(),
                },
                RunRecoveryAction {
                    action: RunRecoveryActionKind::Stop,
                    label: "停止".to_string(),
                },
            ],
        ),
        RunRecoveryRowState::Recoverable => ("待恢复".to_string(), recoverable_actions()),
    };

    RunRecoveryRow {
        id: instance.id.to_string(),
        rule_id: rule.id.to_string(),
        runtime_id: Some(instance.id.to_string()),
        recovery_id: None,
        host_id: rule.host_id.to_string(),
        service_name: rule.name.clone(),
        alias: rule
            .alias
            .as_ref()
            .map(|alias| alias.hostname.clone())
            .unwrap_or_default(),
        entry_url: entry_url_for_runtime(rule, instance),
        provider_label: provider_label(configuration, &instance.provider_target_id),
        port_summary: runtime_port_summary(instance),
        state,
        status_text,
        telemetry: runtime_telemetry(instance),
        error: instance
            .last_error
            .as_ref()
            .map(|error| RunRecoveryRowError {
                code: runtime_error_code(error),
                summary: error.summary.clone(),
                detail: error.detail.clone(),
            }),
        actions,
    }
}

fn runtime_event(
    kind: RuntimeEventKind,
    level: RuntimeEventLevel,
    summary: impl Into<String>,
    detail: Option<String>,
    occurred_at: SystemTime,
    runtime: &crate::runtime::RuntimeInstance,
) -> RuntimeEvent {
    let mut event =
        RuntimeEvent::new(kind, level, summary, occurred_at).with_runtime_context(runtime);
    if let Some(detail) = detail {
        event = event.with_detail(detail);
    }
    event
}

fn push_runtime_event(snapshot: &mut RuntimeSnapshot, event: RuntimeEvent) {
    snapshot.events.push(event);
    snapshot
        .events
        .sort_by_key(|event| std::cmp::Reverse(epoch_seconds(event.occurred_at)));
    snapshot.events.truncate(200);
}

fn runtime_events_from_snapshot(snapshot: &RuntimeSnapshot) -> Vec<RunRecoveryEvent> {
    let mut events = snapshot
        .events
        .iter()
        .map(run_recovery_event_from_runtime_event)
        .collect::<Vec<_>>();
    events.sort_by_key(|event| std::cmp::Reverse(event.occurred_at_epoch_seconds));
    events.truncate(80);
    events
}

fn run_recovery_event_from_runtime_event(event: &RuntimeEvent) -> RunRecoveryEvent {
    RunRecoveryEvent {
        id: run_recovery_event_id(event),
        level: run_recovery_event_level(&event.level),
        kind: runtime_event_kind_name(&event.kind).to_string(),
        occurred_at_epoch_seconds: epoch_seconds(event.occurred_at),
        component: runtime_event_component(&event.kind).to_string(),
        summary: event.summary.clone(),
        detail: event.detail.clone(),
        host_id: event.host_id.as_ref().map(ToString::to_string),
        rule_id: event.rule_id.as_ref().map(ToString::to_string),
        runtime_id: event.runtime_instance_id.as_ref().map(ToString::to_string),
        provider_target_id: event.provider_target_id.as_ref().map(ToString::to_string),
    }
}

fn run_recovery_event_id(event: &RuntimeEvent) -> String {
    [
        event.id.as_str(),
        event.host_id.as_ref().map(|id| id.as_str()).unwrap_or("-"),
        event.rule_id.as_ref().map(|id| id.as_str()).unwrap_or("-"),
        event
            .runtime_instance_id
            .as_ref()
            .map(|id| id.as_str())
            .unwrap_or("-"),
    ]
    .join("::")
}

fn run_recovery_event_level(level: &RuntimeEventLevel) -> RunRecoveryEventLevel {
    match level {
        RuntimeEventLevel::Info => RunRecoveryEventLevel::Info,
        RuntimeEventLevel::Notice => RunRecoveryEventLevel::Notice,
        RuntimeEventLevel::Warning => RunRecoveryEventLevel::Warning,
        RuntimeEventLevel::Error => RunRecoveryEventLevel::Error,
    }
}

fn runtime_event_kind_name(kind: &RuntimeEventKind) -> &'static str {
    match kind {
        RuntimeEventKind::SshStartRequested => "ssh_start_requested",
        RuntimeEventKind::SshStartSucceeded => "ssh_start_succeeded",
        RuntimeEventKind::SshStartFailed => "ssh_start_failed",
        RuntimeEventKind::RuntimeHealthOk => "runtime_health_ok",
        RuntimeEventKind::RuntimeObserved => "runtime_observed",
        RuntimeEventKind::RuntimeHealthWarning => "runtime_health_warning",
        RuntimeEventKind::RuntimeRecovered => "runtime_recovered",
    }
}

fn runtime_event_component(kind: &RuntimeEventKind) -> &'static str {
    match kind {
        RuntimeEventKind::SshStartRequested
        | RuntimeEventKind::SshStartSucceeded
        | RuntimeEventKind::SshStartFailed => "provider.openssh",
        RuntimeEventKind::RuntimeHealthOk | RuntimeEventKind::RuntimeHealthWarning => {
            "runtime.health"
        }
        RuntimeEventKind::RuntimeObserved => "runtime.health",
        RuntimeEventKind::RuntimeRecovered => "runtime.recovery",
    }
}

fn host_health_summary(
    configuration: &ConfigurationSnapshot,
    runtime_snapshot: &RuntimeSnapshot,
    host: &DomainHost,
) -> Option<String> {
    let mut target_health: BTreeMap<String, (usize, usize)> = BTreeMap::new();

    for instance in runtime_snapshot
        .instances
        .iter()
        .filter(|instance| instance.host_id == host.id)
    {
        let label = provider_label(configuration, &instance.provider_target_id);
        let entry = target_health.entry(label).or_insert((0, 0));
        match instance.status {
            RuntimeStatus::Connected => entry.0 += 1,
            RuntimeStatus::Starting | RuntimeStatus::Reconnecting | RuntimeStatus::Error => {
                entry.1 += 1
            }
            RuntimeStatus::Configured => {}
        }
    }

    if target_health.is_empty() {
        return None;
    }

    Some(
        target_health
            .into_iter()
            .map(|(label, (connected, issues))| {
                if issues > 0 {
                    format!("{label} · {connected} 运行 / {issues} 异常")
                } else {
                    format!("{label} · {connected} 运行")
                }
            })
            .collect::<Vec<_>>()
            .join(" / "),
    )
}

fn run_recovery_state_from_runtime_status(status: &RuntimeStatus) -> RunRecoveryRowState {
    match status {
        RuntimeStatus::Connected => RunRecoveryRowState::Connected,
        RuntimeStatus::Starting | RuntimeStatus::Reconnecting => RunRecoveryRowState::Reconnecting,
        RuntimeStatus::Error => RunRecoveryRowState::Error,
        RuntimeStatus::Configured => RunRecoveryRowState::Recoverable,
    }
}

fn runtime_port_summary(instance: &crate::runtime::RuntimeInstance) -> String {
    let mut ports = instance
        .local_bindings
        .iter()
        .map(|binding| binding.local_port.to_string())
        .collect::<Vec<_>>();

    if ports.is_empty() {
        ports.push("-".to_string());
    }

    ports.join(" + ")
}

fn recovery_port_summary(recovery_item: &crate::runtime::RecoveryItem) -> String {
    let ports = recovery_item
        .last_local_bindings
        .iter()
        .map(|binding| binding.local_port.to_string())
        .collect::<Vec<_>>();

    if ports.is_empty() {
        "-".to_string()
    } else {
        ports.join(" + ")
    }
}

fn runtime_telemetry(instance: &crate::runtime::RuntimeInstance) -> Option<String> {
    match (&instance.uptime_seconds, &instance.latency_ms) {
        (None, None) if instance.failure_count_today == 0 => None,
        (uptime, latency) => Some(format!(
            "{} · {} · {}次",
            uptime
                .map(format_duration)
                .unwrap_or_else(|| "0m".to_string()),
            latency
                .map(|latency| format!("{latency}ms"))
                .unwrap_or_else(|| "-".to_string()),
            instance.failure_count_today
        )),
    }
}

fn format_duration(seconds: u64) -> String {
    let hours = seconds / 3600;
    let minutes = (seconds % 3600) / 60;

    if hours > 0 {
        format!("{hours}h {minutes:02}m")
    } else {
        format!("{minutes}m")
    }
}

fn runtime_error_code(error: &crate::runtime::RuntimeErrorInfo) -> String {
    match error.code {
        crate::runtime::RuntimeErrorCode::KeepAliveTimeout => "keepalive_timeout",
        crate::runtime::RuntimeErrorCode::ProviderExited => "provider_exited",
        crate::runtime::RuntimeErrorCode::PortConflict => "local_port_conflict",
        crate::runtime::RuntimeErrorCode::TunnelHealthCheckFailed => "tunnel_health_check_failed",
        crate::runtime::RuntimeErrorCode::InvalidConfiguration => "invalid_configuration",
        crate::runtime::RuntimeErrorCode::Unknown => "unknown",
    }
    .to_string()
}

fn recovery_status_code(status: &RuntimeStatus) -> String {
    match status {
        RuntimeStatus::Connected => "stopped_from_connected",
        RuntimeStatus::Starting => "stopped_from_starting",
        RuntimeStatus::Reconnecting => "stopped_from_reconnecting",
        RuntimeStatus::Error => "stopped_from_error",
        RuntimeStatus::Configured => "configured_not_running",
    }
    .to_string()
}

fn provider_summary_for_host(host: &DomainHost) -> String {
    let labels = host
        .provider_targets
        .iter()
        .map(|target| target.label.trim())
        .filter(|label| !label.is_empty())
        .map(str::to_string)
        .collect::<Vec<_>>();

    if labels.is_empty() {
        "未配置 provider".to_string()
    } else {
        labels.join(" / ")
    }
}

fn registry_host_from_domain(snapshot: &ConfigurationSnapshot, host: &DomainHost) -> RegistryHost {
    RegistryHost {
        id: host.id.to_string(),
        name: host.name.clone(),
        endpoint: host_endpoint(host),
        status: registry_host_status_from_hint(&host.status_hint),
        os_hint: registry_host_os_hint_from_domain(host),
        address: host.address.clone(),
        port: host.port,
        user: host.user.clone(),
        tags: host.tags.clone(),
        os_distro: host.os_distro.clone(),
        provider_targets: host
            .provider_targets
            .iter()
            .map(registry_target_from_domain)
            .collect(),
        presets: snapshot
            .presets
            .iter()
            .filter(|preset| preset.host_id == host.id)
            .map(|preset| registry_preset_from_domain(snapshot, preset))
            .collect(),
        rules: snapshot
            .rules
            .iter()
            .filter(|rule| rule.host_id == host.id)
            .map(|rule| registry_rule_from_domain(snapshot, rule))
            .collect(),
    }
}

fn registry_target_from_domain(target: &DomainProviderTarget) -> RegistryProviderTarget {
    RegistryProviderTarget {
        id: target.id.to_string(),
        label: target.label.clone(),
        kind: registry_provider_kind_from_domain(&target.target_type),
        target_address: target.target_address.clone(),
        target_port: target.target_port,
    }
}

fn registry_preset_from_domain(
    snapshot: &ConfigurationSnapshot,
    preset: &DomainPreset,
) -> RegistryPreset {
    RegistryPreset {
        id: preset.id.to_string(),
        name: preset.name.clone(),
        derived_from: preset.base_preset_id.as_ref().and_then(|base_id| {
            snapshot
                .presets
                .iter()
                .find(|candidate| candidate.id == *base_id)
                .map(|candidate| candidate.name.clone())
        }),
        rules: preset
            .items
            .iter()
            .filter_map(|item| {
                snapshot
                    .rules
                    .iter()
                    .find(|rule| rule.id == item.rule_id)
                    .map(|rule| {
                        let target_id = item
                            .provider_target_override
                            .as_ref()
                            .unwrap_or(&rule.provider_target_id);
                        RegistryPresetRule {
                            service_name: rule.name.clone(),
                            target_label: provider_label(snapshot, target_id),
                        }
                    })
            })
            .collect(),
    }
}

fn registry_rule_from_domain(snapshot: &ConfigurationSnapshot, rule: &DomainRule) -> RegistryRule {
    RegistryRule {
        id: rule.id.to_string(),
        service_name: rule.name.clone(),
        alias: rule
            .alias
            .as_ref()
            .map(|alias| alias.hostname.clone())
            .unwrap_or_default(),
        provider_label: provider_label(snapshot, &rule.provider_target_id),
        port_summary: port_summary(rule),
        runtime_state: RegistryRuleRuntimeState::Stopped,
        provider_target_id: rule.provider_target_id.to_string(),
        remote_host: rule.remote_host.clone(),
        main_local_port: rule.main_port.local_port,
        main_remote_host: rule.main_port.remote_host.clone(),
        main_remote_port: rule.main_port.remote_port,
        secondary_ports: rule
            .secondary_ports
            .iter()
            .map(|mapping| RegistryPortMapping {
                local_port: mapping.local_port,
                remote_host: mapping.remote_host.clone(),
                remote_port: mapping.remote_port,
            })
            .collect(),
        kind: rule.kind.clone(),
        tags: rule.tags.clone(),
        notes: rule.notes.clone(),
    }
}

fn host_endpoint(host: &DomainHost) -> String {
    let mut endpoint = String::new();

    if let Some(user) = &host.user {
        if !user.trim().is_empty() {
            endpoint.push_str(user.trim());
            endpoint.push('@');
        }
    }

    endpoint.push_str(host.address.trim());

    if let Some(port) = host.port.filter(|port| *port != 22) {
        endpoint.push(':');
        endpoint.push_str(&port.to_string());
    }

    endpoint
}

fn provider_label(snapshot: &ConfigurationSnapshot, target_id: &ProviderTargetId) -> String {
    snapshot
        .hosts
        .iter()
        .flat_map(|host| host.provider_targets.iter())
        .find(|target| target.id == *target_id)
        .map(|target| target.label.clone())
        .unwrap_or_else(|| "未命名链路".to_string())
}

fn port_summary(rule: &DomainRule) -> String {
    let mut ports = vec![rule.main_port.local_port.to_string()];
    ports.extend(
        rule.secondary_ports
            .iter()
            .map(|mapping| mapping.local_port.to_string()),
    );
    ports.join(" + ")
}

fn entry_url_for_rule(rule: &DomainRule) -> Option<String> {
    let alias = rule.alias.as_ref()?.hostname.as_str();
    let mut ports = vec![rule.main_port.local_port];
    ports.extend(
        rule.secondary_ports
            .iter()
            .map(|mapping| mapping.local_port),
    );
    entry_url_from_alias_and_ports(alias, &ports)
}

fn entry_url_for_runtime(
    rule: &DomainRule,
    instance: &crate::runtime::RuntimeInstance,
) -> Option<String> {
    let alias = rule.alias.as_ref()?.hostname.as_str();
    let ports = instance
        .local_bindings
        .iter()
        .map(|binding| binding.local_port)
        .collect::<Vec<_>>();
    entry_url_from_alias_and_ports(alias, &ports)
}

fn entry_url_for_recovery_item(
    rule: &DomainRule,
    recovery_item: &crate::runtime::RecoveryItem,
) -> Option<String> {
    let alias = rule.alias.as_ref()?.hostname.as_str();
    let ports = recovery_item
        .last_local_bindings
        .iter()
        .map(|binding| binding.local_port)
        .collect::<Vec<_>>();
    entry_url_from_alias_and_ports(alias, &ports)
}

fn entry_url_from_alias_and_ports(alias: &str, local_ports: &[u16]) -> Option<String> {
    let alias = alias.trim();
    if alias.is_empty() {
        return None;
    }

    let port = local_ports.iter().copied().find(|port| *port > 0)?;
    let scheme = if matches!(port, 80 | 443) {
        default_scheme_for_port(port)
    } else {
        "http"
    };
    let port_suffix = if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
        String::new()
    } else {
        format!(":{port}")
    };

    Some(format!("{scheme}://{alias}{port_suffix}/"))
}

fn default_scheme_for_port(port: u16) -> &'static str {
    if port == 443 {
        "https"
    } else {
        "http"
    }
}

fn first_port_from_summary(port_summary: &str) -> u16 {
    port_summary
        .split(|character: char| !character.is_ascii_digit())
        .find(|part| !part.is_empty())
        .and_then(|part| part.parse::<u16>().ok())
        .unwrap_or(0)
}

fn validate_registry_host_draft(draft: &RegistryHostDraft) -> Result<(), Box<BridgeError>> {
    if draft.name.trim().is_empty() {
        return Err(BridgeError::registry_validation(
            "资源分组名称不能为空",
            Some("host.name must not be empty.".to_string()),
        )
        .into());
    }

    if draft.address.trim().is_empty() {
        return Err(BridgeError::registry_validation(
            "主机地址不能为空",
            Some("host.address must not be empty.".to_string()),
        )
        .into());
    }

    if draft.provider_targets.is_empty() {
        return Err(BridgeError::registry_validation(
            "至少需要一个 provider target",
            Some("host.provider_targets must include at least one target.".to_string()),
        )
        .into());
    }

    for target in &draft.provider_targets {
        if target.label.trim().is_empty() {
            return Err(BridgeError::registry_validation(
                "provider target 标签不能为空",
                Some("provider_target.label must not be empty.".to_string()),
            )
            .into());
        }

        if target.target_address.trim().is_empty() {
            return Err(BridgeError::registry_validation(
                "provider target 地址不能为空",
                Some("provider_target.target_address must not be empty.".to_string()),
            )
            .into());
        }

        if target.target_port == Some(0) {
            return Err(BridgeError::registry_validation(
                "provider target 端口无效",
                Some("provider_target.target_port must be between 1 and 65535.".to_string()),
            )
            .into());
        }
    }

    Ok(())
}

fn validate_registry_rule_draft(draft: &RegistryRuleDraft) -> Result<(), Box<BridgeError>> {
    if draft.host_id.trim().is_empty() {
        return Err(BridgeError::registry_validation(
            "规则缺少所属主机",
            Some("rule.host_id must not be empty.".to_string()),
        )
        .into());
    }

    if draft.service_name.trim().is_empty() {
        return Err(BridgeError::registry_validation(
            "规则名称不能为空",
            Some("rule.service_name must not be empty.".to_string()),
        )
        .into());
    }

    if draft.provider_target_id.trim().is_empty() {
        return Err(BridgeError::registry_validation(
            "规则缺少 provider target",
            Some("rule.provider_target_id must not be empty.".to_string()),
        )
        .into());
    }

    if draft.remote_host.trim().is_empty() || draft.main_remote_host.trim().is_empty() {
        return Err(BridgeError::registry_validation(
            "远端地址不能为空",
            Some("rule.remote_host and rule.main_remote_host must not be empty.".to_string()),
        )
        .into());
    }

    if draft.main_local_port == 0 || draft.main_remote_port == 0 {
        return Err(BridgeError::registry_validation(
            "主端口映射无效",
            Some("main port mapping must use ports between 1 and 65535.".to_string()),
        )
        .into());
    }

    for mapping in &draft.secondary_ports {
        if mapping.local_port == 0
            || mapping.remote_port == 0
            || mapping.remote_host.trim().is_empty()
        {
            return Err(BridgeError::registry_validation(
                "附属端口映射无效",
                Some("secondary port mappings must include valid local port, remote host, and remote port.".to_string()),
            )
            .into());
        }
    }

    Ok(())
}

fn validate_registry_rule_references(
    configuration: &ConfigurationSnapshot,
    draft: &RegistryRuleDraft,
) -> Result<(), Box<BridgeError>> {
    let host_id = draft.host_id.trim();
    let provider_target_id = draft.provider_target_id.trim();

    let host = configuration
        .hosts
        .iter()
        .find(|host| host.id.as_str() == host_id)
        .ok_or_else(|| {
            Box::new(BridgeError::registry_validation(
                "规则引用的主机不存在",
                Some(format!("rule.host_id={host_id}")),
            ))
        })?;

    if host
        .provider_targets
        .iter()
        .any(|target| target.id.as_str() == provider_target_id)
    {
        return Ok(());
    }

    Err(BridgeError::registry_validation(
        "规则引用的 provider target 不属于该主机",
        Some(format!(
            "rule.host_id={host_id}, rule.provider_target_id={provider_target_id}"
        )),
    )
    .into())
}

fn domain_host_from_draft(draft: RegistryHostDraft) -> Result<DomainHost, Box<BridgeError>> {
    let host_id = draft
        .id
        .filter(|id| !id.trim().is_empty())
        .unwrap_or_else(|| generated_id("host", &draft.name));
    let host_id = HostId::from(host_id);
    let provider_targets = draft
        .provider_targets
        .into_iter()
        .map(|target| domain_provider_target_from_draft(&host_id, target))
        .collect::<Result<Vec<_>, _>>()?;

    Ok(DomainHost {
        id: host_id,
        name: draft.name.trim().to_string(),
        address: draft.address.trim().to_string(),
        port: draft.port.filter(|port| *port != 0),
        user: trimmed_option(draft.user),
        tags: trimmed_vec(draft.tags),
        os_family: domain_os_family_from_registry(draft.os_hint),
        os_distro: trimmed_option(draft.os_distro),
        status_hint: domain_host_status_from_registry(draft.status),
        provider_targets,
    })
}

fn domain_provider_target_from_draft(
    host_id: &HostId,
    draft: RegistryProviderTargetDraft,
) -> Result<DomainProviderTarget, Box<BridgeError>> {
    let target_id = draft
        .id
        .filter(|id| !id.trim().is_empty())
        .unwrap_or_else(|| generated_id("target", &draft.label));

    Ok(DomainProviderTarget {
        id: ProviderTargetId::from(target_id),
        host_id: host_id.clone(),
        target_type: domain_provider_kind_from_registry(draft.kind),
        label: draft.label.trim().to_string(),
        target_address: draft.target_address.trim().to_string(),
        target_port: draft.target_port.filter(|port| *port != 0),
        auth_ref: None,
        meta: Metadata::new(),
    })
}

fn domain_rule_from_draft(draft: RegistryRuleDraft) -> Result<DomainRule, Box<BridgeError>> {
    let rule_id = draft
        .id
        .filter(|id| !id.trim().is_empty())
        .unwrap_or_else(|| generated_id("rule", &draft.service_name));
    let rule_id = RuleId::from(rule_id);

    Ok(DomainRule {
        id: rule_id.clone(),
        host_id: HostId::from(draft.host_id.trim().to_string()),
        name: draft.service_name.trim().to_string(),
        alias: trimmed_option(draft.alias).map(|alias| LocalAlias {
            hostname: alias,
            rule_id: rule_id.clone(),
            generated: false,
            editable: true,
        }),
        provider_target_id: ProviderTargetId::from(draft.provider_target_id.trim().to_string()),
        remote_host: draft.remote_host.trim().to_string(),
        main_port: PortMapping::new(
            draft.main_local_port,
            draft.main_remote_host.trim(),
            draft.main_remote_port,
        ),
        secondary_ports: draft
            .secondary_ports
            .into_iter()
            .map(|mapping| {
                PortMapping::new(
                    mapping.local_port,
                    mapping.remote_host.trim(),
                    mapping.remote_port,
                )
            })
            .collect(),
        kind: trimmed_option(draft.kind),
        icon_hint: None,
        tags: trimmed_vec(draft.tags),
        notes: trimmed_option(draft.notes),
    })
}

fn trimmed_option(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim();
        (!trimmed.is_empty()).then(|| trimmed.to_string())
    })
}

fn trimmed_vec(values: Vec<String>) -> Vec<String> {
    values
        .into_iter()
        .filter_map(|value| {
            let trimmed = value.trim();
            (!trimmed.is_empty()).then(|| trimmed.to_string())
        })
        .collect()
}

fn generated_id(prefix: &str, seed: &str) -> String {
    let slug = seed
        .chars()
        .flat_map(|character| character.to_lowercase())
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string();
    let slug = if slug.is_empty() {
        prefix.to_string()
    } else {
        slug
    };

    format!("{prefix}-{slug}-{}", current_epoch_millis())
}

fn registry_host_status_from_hint(hint: &HostStatusHint) -> RegistryHostStatus {
    match hint {
        HostStatusHint::Unknown => RegistryHostStatus::Unknown,
        HostStatusHint::Online => RegistryHostStatus::Online,
        HostStatusHint::Offline => RegistryHostStatus::Offline,
    }
}

fn domain_host_status_from_registry(status: RegistryHostStatus) -> HostStatusHint {
    match status {
        RegistryHostStatus::Unknown => HostStatusHint::Unknown,
        RegistryHostStatus::Online => HostStatusHint::Online,
        RegistryHostStatus::Offline => HostStatusHint::Offline,
    }
}

fn registry_host_os_hint_from_domain(host: &DomainHost) -> RegistryHostOsHint {
    match host.os_family {
        OsFamily::MacOS => RegistryHostOsHint::Macos,
        OsFamily::Windows => RegistryHostOsHint::Windows,
        OsFamily::Linux => {
            let distro = host
                .os_distro
                .as_deref()
                .map(str::to_ascii_lowercase)
                .unwrap_or_default();
            if distro.contains("ubuntu") {
                RegistryHostOsHint::Ubuntu
            } else if distro.contains("raspbian") || distro.contains("raspberry") {
                RegistryHostOsHint::RaspberryPi
            } else {
                RegistryHostOsHint::Linux
            }
        }
        OsFamily::Unknown => RegistryHostOsHint::Unknown,
    }
}

fn domain_os_family_from_registry(os_hint: RegistryHostOsHint) -> OsFamily {
    match os_hint {
        RegistryHostOsHint::Macos => OsFamily::MacOS,
        RegistryHostOsHint::Ubuntu
        | RegistryHostOsHint::Linux
        | RegistryHostOsHint::RaspberryPi => OsFamily::Linux,
        RegistryHostOsHint::Windows => OsFamily::Windows,
        RegistryHostOsHint::Unknown => OsFamily::Unknown,
    }
}

fn registry_provider_kind_from_domain(kind: &ProviderTargetType) -> RegistryProviderKind {
    match kind {
        ProviderTargetType::Ssh => RegistryProviderKind::Ssh,
        ProviderTargetType::Tailscale => RegistryProviderKind::Tailscale,
        ProviderTargetType::Other(_) => RegistryProviderKind::Ssh,
    }
}

fn domain_provider_kind_from_registry(kind: RegistryProviderKind) -> ProviderTargetType {
    match kind {
        RegistryProviderKind::Ssh => ProviderTargetType::Ssh,
        RegistryProviderKind::Tailscale => ProviderTargetType::Tailscale,
    }
}

fn storage_error_to_bridge(error: StorageError) -> Box<BridgeError> {
    match error {
        StorageError::Validation(validation) => Box::new(validation_error_to_bridge(validation)),
        StorageError::Sqlite(error) => Box::new(BridgeError::storage_failure(
            "RelayDock 本地存储写入失败",
            Some(error.to_string()),
        )),
        StorageError::Json(error) => Box::new(BridgeError::internal(
            "RelayDock 存储数据无法序列化",
            Some(error.to_string()),
        )),
    }
}

fn provider_error_to_bridge(error: ProviderError) -> Box<BridgeError> {
    Box::new(BridgeError::provider_failure(error.diagnostic()))
}

fn validation_error_to_bridge(error: StorageValidationError) -> BridgeError {
    BridgeError::registry_validation("资源登记配置校验失败", Some(error.to_string()))
}

fn bridge_error_code_from_provider(code: &ProviderDiagnosticCode) -> BridgeErrorCode {
    match code {
        ProviderDiagnosticCode::UnsupportedProviderTarget => {
            BridgeErrorCode::UnsupportedProviderTarget
        }
        ProviderDiagnosticCode::InvalidProviderTarget => BridgeErrorCode::InvalidProviderTarget,
        ProviderDiagnosticCode::ProcessStartFailed
        | ProviderDiagnosticCode::ProcessStatusFailed
        | ProviderDiagnosticCode::ProcessTerminationFailed
        | ProviderDiagnosticCode::ProcessExited => BridgeErrorCode::ProviderProcessFailed,
    }
}

fn current_epoch_seconds() -> u64 {
    epoch_seconds(SystemTime::now())
}

fn current_epoch_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(u128::from(DEMO_REFRESHED_AT_EPOCH_SECONDS) * 1000)
}

fn demo_now_epoch_seconds() -> u64 {
    DEMO_REFRESHED_AT_EPOCH_SECONDS
}

fn epoch_seconds(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(DEMO_REFRESHED_AT_EPOCH_SECONDS)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::{PortOwnerType, PortProtocol};
    use crate::providers::{OpenSshCommand, ProviderProcess, ProviderProcessExit};
    use serde_json::json;
    use std::cell::RefCell;
    use std::rc::Rc;

    #[derive(Clone, Debug)]
    struct MockLauncher {
        launched: Rc<RefCell<Vec<OpenSshCommand>>>,
        next_process: MockProcess,
    }

    impl ProviderProcessLauncher for MockLauncher {
        type Process = MockProcess;

        fn launch(&self, command: &OpenSshCommand) -> Result<Self::Process, ProviderError> {
            self.launched.borrow_mut().push(command.clone());
            Ok(self.next_process.clone())
        }
    }

    #[derive(Clone, Debug)]
    struct FailingLauncher {
        launched: Rc<RefCell<Vec<OpenSshCommand>>>,
    }

    impl ProviderProcessLauncher for FailingLauncher {
        type Process = MockProcess;

        fn launch(&self, command: &OpenSshCommand) -> Result<Self::Process, ProviderError> {
            self.launched.borrow_mut().push(command.clone());
            Err(ProviderError {
                diagnostic: Box::new(ProviderDiagnostic {
                    code: ProviderDiagnosticCode::ProcessStartFailed,
                    summary: "OpenSSH process could not be started".to_string(),
                    detail: Some("mock spawn failure".to_string()),
                    rule_id: None,
                    provider_target_id: None,
                    runtime_instance_id: None,
                    suggested_recovery: Some(
                        "Check that system ssh is installed and the provider target is reachable."
                            .to_string(),
                    ),
                }),
            })
        }
    }

    #[derive(Clone, Debug)]
    struct MockProcess {
        pid: Option<u32>,
        exit: Option<ProviderProcessExit>,
    }

    impl ProviderProcess for MockProcess {
        fn process_id(&self) -> Option<u32> {
            self.pid
        }

        fn try_wait(&mut self) -> Result<Option<ProviderProcessExit>, ProviderError> {
            Ok(self.exit.clone())
        }

        fn terminate(&mut self) -> Result<(), ProviderError> {
            Ok(())
        }
    }

    #[derive(Clone, Debug)]
    struct MockPidController {
        running: bool,
        terminated: Rc<RefCell<Vec<u32>>>,
    }

    impl MockPidController {
        fn running() -> Self {
            Self {
                running: true,
                terminated: Rc::new(RefCell::new(Vec::new())),
            }
        }

        fn missing() -> Self {
            Self {
                running: false,
                terminated: Rc::new(RefCell::new(Vec::new())),
            }
        }

        fn with_terminated(terminated: Rc<RefCell<Vec<u32>>>) -> Self {
            Self {
                running: true,
                terminated,
            }
        }
    }

    impl ProviderProcessController for MockPidController {
        fn is_running(&self, _pid: u32) -> Result<bool, ProviderError> {
            Ok(self.running)
        }

        fn terminate_pid(&self, pid: u32) -> Result<(), ProviderError> {
            self.terminated.borrow_mut().push(pid);
            Ok(())
        }
    }

    #[derive(Clone, Copy, Debug)]
    struct MockTunnelHealthChecker {
        healthy: bool,
    }

    impl MockTunnelHealthChecker {
        fn healthy() -> Self {
            Self { healthy: true }
        }

        fn unhealthy() -> Self {
            Self { healthy: false }
        }
    }

    impl crate::runtime::LocalTunnelHealthChecker for MockTunnelHealthChecker {
        fn check(
            &self,
            runtime: &crate::runtime::RuntimeInstance,
        ) -> crate::runtime::LocalTunnelHealth {
            let checked_bindings = runtime
                .local_bindings
                .iter()
                .map(|binding| crate::runtime::LocalTunnelBindingHealth {
                    local_port: binding.local_port,
                    healthy: self.healthy,
                    detail: (!self.healthy)
                        .then(|| format!("mock listener failed for port {}", binding.local_port)),
                })
                .collect::<Vec<_>>();

            crate::runtime::LocalTunnelHealth {
                healthy: self.healthy && !checked_bindings.is_empty(),
                checked_bindings,
            }
        }
    }

    fn tcp_claim(port: u16) -> PortClaim {
        PortClaim {
            port,
            protocol: PortProtocol::Tcp,
            owner_type: PortOwnerType::RelayDockRuntime,
            owner_ref: Some("runtime-1".to_string()),
        }
    }

    fn tcp_usage(port: u16) -> PortUsage {
        PortUsage {
            port,
            protocol: PortProtocol::Tcp,
            pid: Some(2233),
            process_name: Some("node".to_string()),
            command: Some("npm run dev".to_string()),
            owner_type: PortOwnerType::LocalProcess,
            owner_ref: None,
            killable: true,
        }
    }

    fn sample_configuration() -> ConfigurationSnapshot {
        let host_id = HostId::from("host-home");
        let ssh_target = DomainProviderTarget {
            id: ProviderTargetId::from("target-home-ssh"),
            host_id: host_id.clone(),
            target_type: ProviderTargetType::Ssh,
            label: "SSH · 家".to_string(),
            target_address: "192.168.1.5".to_string(),
            target_port: Some(22),
            auth_ref: None,
            meta: Metadata::new(),
        };
        let tailscale_target = DomainProviderTarget {
            id: ProviderTargetId::from("target-home-ts"),
            host_id: host_id.clone(),
            target_type: ProviderTargetType::Tailscale,
            label: "Tailscale · 家里".to_string(),
            target_address: "100.64.0.5".to_string(),
            target_port: None,
            auth_ref: None,
            meta: Metadata::new(),
        };
        let rule_id = RuleId::from("rule-react");

        ConfigurationSnapshot {
            hosts: vec![DomainHost {
                id: host_id.clone(),
                name: "Mac mini (M2) - 家".to_string(),
                address: "192.168.1.5".to_string(),
                port: Some(22),
                user: Some("admin".to_string()),
                tags: vec!["home".to_string()],
                os_family: OsFamily::MacOS,
                os_distro: None,
                status_hint: HostStatusHint::Online,
                provider_targets: vec![ssh_target.clone(), tailscale_target.clone()],
            }],
            rules: vec![DomainRule {
                id: rule_id.clone(),
                host_id: host_id.clone(),
                name: "React 前端".to_string(),
                alias: Some(LocalAlias {
                    hostname: "react.home.localhost".to_string(),
                    rule_id,
                    generated: true,
                    editable: true,
                }),
                provider_target_id: tailscale_target.id.clone(),
                remote_host: "127.0.0.1".to_string(),
                main_port: PortMapping::new(3000, "127.0.0.1", 3000),
                secondary_ports: vec![PortMapping::new(3001, "127.0.0.1", 3001)],
                kind: Some("web".to_string()),
                icon_hint: None,
                tags: vec!["frontend".to_string()],
                notes: Some("sample".to_string()),
            }],
            presets: vec![DomainPreset {
                id: "preset-home".into(),
                name: "日常开发".to_string(),
                host_id,
                base_preset_id: None,
                items: vec![crate::domain::PresetItem {
                    rule_id: "rule-react".into(),
                    provider_target_override: Some("target-home-ssh".into()),
                    local_port_overrides: Vec::new(),
                }],
                description: None,
            }],
        }
    }

    fn sample_configuration_with_ssh_rule() -> ConfigurationSnapshot {
        let mut configuration = sample_configuration();
        configuration.rules[0].provider_target_id = ProviderTargetId::from("target-home-ssh");
        configuration
    }

    #[test]
    fn check_port_claim_returns_structured_conflict_and_suggestion() {
        let result = check_port_claim(tcp_claim(8088), vec![tcp_usage(8088), tcp_usage(8089)]);

        assert!(!result.available);
        assert_eq!(
            result.conflict.as_ref().map(|conflict| conflict.usage.port),
            Some(8088)
        );
        assert_eq!(result.suggested_port, Some(8090));
    }

    #[test]
    fn check_port_claim_omits_suggestion_when_requested_port_is_available() {
        let result = check_port_claim(tcp_claim(8088), vec![tcp_usage(8089)]);

        assert!(result.available);
        assert!(result.conflict.is_none());
        assert_eq!(result.suggested_port, None);
    }

    #[test]
    fn bridge_command_json_round_trips_to_structured_success_response() {
        let command: BridgeCommand = serde_json::from_value(json!({
            "command": "check_port_claim",
            "claim": {
                "port": 8088,
                "protocol": "Tcp",
                "owner_type": "RelayDockRuntime",
                "owner_ref": "runtime-1"
            },
            "known_usages": [
                {
                    "port": 8088,
                    "protocol": "Tcp",
                    "pid": 2233,
                    "process_name": "node",
                    "command": "npm run dev",
                    "owner_type": "LocalProcess",
                    "owner_ref": null,
                    "killable": true
                }
            ]
        }))
        .expect("command JSON decodes");

        let response =
            BridgeResponse::success(execute_bridge_command(command).expect("command executes"));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], true);
        assert_eq!(json["result"]["type"], "port_claim_check");
        assert_eq!(json["result"]["available"], false);
        assert_eq!(json["result"]["suggested_port"], 8089);
    }

    #[test]
    fn parse_ssh_command_bridge_command_returns_structured_parse_result() {
        let command: BridgeCommand = serde_json::from_value(json!({
            "command": "parse_ssh_command",
            "command_text": "ssh -L 3000:127.0.0.1:3000 admin@sanjose"
        }))
        .expect("command JSON decodes");

        let response =
            BridgeResponse::success(execute_bridge_command(command).expect("command executes"));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], true);
        assert_eq!(json["result"]["type"], "ssh_command_parse");
        assert_eq!(json["result"]["rule_drafts"][0]["local_port"], 3000);
        assert_eq!(json["result"]["destination_hint"]["host"], "sanjose");
    }

    #[test]
    fn test_provider_target_connectivity_rejects_empty_target() {
        let result = test_provider_target_connectivity(TestProviderTargetConnectivityCommand {
            target_address: "  ".to_string(),
            target_port: 22,
            timeout_millis: 250,
        });

        assert!(!result.reachable);
        assert_eq!(
            result.diagnostic.as_ref().map(|diagnostic| &diagnostic.code),
            Some(&ProviderTargetConnectivityDiagnosticCode::InvalidTarget)
        );
    }

    #[test]
    fn test_provider_target_connectivity_reports_dns_resolution_failure() {
        let result = test_provider_target_connectivity(TestProviderTargetConnectivityCommand {
            target_address: "invalid.invalid.".to_string(),
            target_port: 22,
            timeout_millis: 250,
        });

        assert!(!result.reachable);
        assert_eq!(
            result.diagnostic.as_ref().map(|diagnostic| &diagnostic.code),
            Some(&ProviderTargetConnectivityDiagnosticCode::DnsResolutionFailed)
        );
    }

    #[test]
    fn test_provider_target_connectivity_bridge_command_returns_structured_result() {
        let command: BridgeCommand = serde_json::from_value(json!({
            "command": "test_provider_target_connectivity",
            "target_address": "",
            "target_port": 22,
            "timeout_millis": 250
        }))
        .expect("command JSON decodes");

        let response =
            BridgeResponse::success(execute_bridge_command(command).expect("command executes"));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], true);
        assert_eq!(json["result"]["type"], "provider_target_connectivity");
        assert_eq!(json["result"]["reachable"], false);
        assert_eq!(json["result"]["diagnostic"]["code"], "invalid_target");
    }

    #[test]
    fn load_run_recovery_snapshot_returns_demo_runtime_and_recovery_rows() {
        let result = load_run_recovery_snapshot();

        assert_eq!(result.hosts.len(), 2);
        assert_eq!(result.hosts[0].rows.len(), 9);
        assert_eq!(result.summary.connected_hosts, 2);
        assert_eq!(result.summary.running_forwards, 8);
        assert_eq!(result.summary.recoverable_count, 3);
        assert!(result.hosts[0]
            .rows
            .iter()
            .any(|row| row.state == RunRecoveryRowState::Connected));
        assert!(result.hosts[0]
            .rows
            .iter()
            .any(|row| row.state == RunRecoveryRowState::Reconnecting));
        assert!(result.hosts[0]
            .rows
            .iter()
            .any(|row| row.state == RunRecoveryRowState::Error));
        assert!(result.hosts[0]
            .rows
            .iter()
            .any(|row| row.state == RunRecoveryRowState::Recoverable));
    }

    #[test]
    fn demo_start_stop_and_clear_transition_through_structured_snapshots() {
        let loaded = load_run_recovery_snapshot();

        let started = start_demo_rule(loaded, "rule-postgres-main");
        assert_eq!(started.summary.running_forwards, 9);
        assert_eq!(started.summary.recoverable_count, 2);
        assert!(started.last_action.as_ref().is_some_and(|status| status.ok));
        assert!(started.hosts[0].rows.iter().any(|row| {
            row.rule_id == "rule-postgres-main" && row.state == RunRecoveryRowState::Connected
        }));

        let stopped = stop_demo_runtime(started, "runtime-rule-postgres-main");
        assert_eq!(stopped.summary.running_forwards, 8);
        assert_eq!(stopped.summary.recoverable_count, 3);
        assert!(stopped.hosts[0].rows.iter().any(|row| {
            row.rule_id == "rule-postgres-main" && row.state == RunRecoveryRowState::Recoverable
        }));

        let cleared = clear_demo_recovery_item(stopped, "recovery-rule-postgres-main");
        assert_eq!(cleared.summary.running_forwards, 8);
        assert_eq!(cleared.summary.recoverable_count, 2);
        assert!(!cleared.hosts[0]
            .rows
            .iter()
            .any(|row| row.rule_id == "rule-postgres-main"));
    }

    #[test]
    fn retry_demo_runtime_turns_error_row_connected() {
        let retried = retry_demo_runtime(load_run_recovery_snapshot(), "runtime-rule-rabbitmq");

        assert!(retried.last_action.as_ref().is_some_and(|status| status.ok));
        assert!(retried.hosts[0].rows.iter().any(|row| {
            row.rule_id == "rule-rabbitmq"
                && row.state == RunRecoveryRowState::Connected
                && row
                    .actions
                    .iter()
                    .any(|action| action.action == RunRecoveryActionKind::Stop)
        }));
        assert_eq!(retried.summary.issue_count, 2);
    }

    #[test]
    fn local_port_override_recovers_rule_without_mutating_registry_config() {
        let recovered = apply_demo_local_port_override(
            load_run_recovery_snapshot(),
            "rule-postgres-main",
            15432,
        );

        assert!(recovered
            .last_action
            .as_ref()
            .is_some_and(|status| status.ok));
        assert!(recovered.hosts[0].rows.iter().any(|row| {
            row.rule_id == "rule-postgres-main"
                && row.state == RunRecoveryRowState::Connected
                && row.port_summary == "15432 -> 5432"
        }));
        assert_eq!(
            registry_snapshot_from_configuration(&sample_configuration(), None).hosts[0]
                .rules
                .iter()
                .find(|rule| rule.id == "rule-react")
                .map(|rule| rule.port_summary.as_str()),
            Some("3000 + 3001")
        );
    }

    #[test]
    fn invalid_demo_action_returns_visible_structured_status() {
        let result = start_demo_rule(load_run_recovery_snapshot(), "missing-rule");
        let status = result.last_action.expect("status is included");
        let error = status.error.expect("structured error is included");

        assert!(!status.ok);
        assert_eq!(error.code, BridgeErrorCode::InvalidDemoAction);
        assert_eq!(error.affected_rule_id.as_deref(), Some("missing-rule"));
        assert_eq!(
            error.suggested_recovery.as_deref(),
            Some("Reload the Run/Recovery snapshot and retry the action.")
        );
    }

    #[test]
    fn run_recovery_bridge_command_json_round_trips_to_structured_success_response() {
        let command: BridgeCommand = serde_json::from_value(json!({
            "command": "load_run_recovery_snapshot"
        }))
        .expect("command JSON decodes");

        let response =
            BridgeResponse::success(execute_bridge_command(command).expect("command executes"));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], true);
        assert_eq!(json["result"]["type"], "run_recovery_snapshot");
        assert_eq!(json["result"]["summary"]["running_forwards"], 8);
        assert!(json["result"]["hosts"][0]["rows"]
            .as_array()
            .is_some_and(|rows| rows
                .iter()
                .any(|row| row["actions"][0]["action"] == "recover")));
    }

    #[test]
    fn storage_backed_run_recovery_snapshot_returns_empty_state_for_empty_storage() {
        let mut store = RelayDockStore::in_memory().expect("store opens");

        let snapshot = load_run_recovery_snapshot_from_store(
            &mut store,
            &MockPidController::running(),
            &MockTunnelHealthChecker::healthy(),
        )
        .expect("run/recovery snapshot loads");

        assert!(snapshot.hosts.is_empty());
        assert_eq!(snapshot.summary.connected_hosts, 0);
        assert_eq!(snapshot.summary.running_forwards, 0);
        assert_eq!(snapshot.summary.recoverable_count, 0);
        assert_eq!(snapshot.summary.message, "没有运行或待恢复项目");
        assert!(snapshot.last_action.is_none());
    }

    #[test]
    fn storage_backed_run_recovery_snapshot_projects_saved_rules_as_recoverable_rows() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration())
            .expect("configuration saves");

        let snapshot = load_run_recovery_snapshot_from_store(
            &mut store,
            &MockPidController::running(),
            &MockTunnelHealthChecker::healthy(),
        )
        .expect("run/recovery snapshot loads");

        assert_eq!(snapshot.hosts.len(), 1);
        assert_eq!(snapshot.hosts[0].id, "host-home");
        assert_eq!(snapshot.hosts[0].endpoint, "admin@192.168.1.5");
        assert_eq!(
            snapshot.hosts[0].provider_summary,
            "SSH · 家 / Tailscale · 家里"
        );
        assert_eq!(snapshot.hosts[0].rows.len(), 1);

        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.rule_id, "rule-react");
        assert_eq!(row.runtime_id, None);
        assert_eq!(row.recovery_id.as_deref(), Some("recovery-rule-react"));
        assert_eq!(row.service_name, "React 前端");
        assert_eq!(row.alias, "react.home.localhost");
        assert_eq!(row.provider_label, "Tailscale · 家里");
        assert_eq!(row.port_summary, "3000 + 3001");
        assert_eq!(
            row.entry_url.as_deref(),
            Some("http://react.home.localhost:3000/")
        );
        assert_eq!(row.state, RunRecoveryRowState::Recoverable);
        assert_eq!(row.status_text, "待恢复");
        assert_eq!(
            row.error.as_ref().map(|error| error.code.as_str()),
            Some("configured_not_running")
        );
        assert_eq!(
            row.actions
                .iter()
                .map(|action| action.action.clone())
                .collect::<Vec<_>>(),
            vec![
                RunRecoveryActionKind::Recover,
                RunRecoveryActionKind::ChangeLocalPort,
                RunRecoveryActionKind::Clear,
            ]
        );
        assert_eq!(snapshot.summary.connected_hosts, 0);
        assert_eq!(snapshot.summary.running_forwards, 0);
        assert_eq!(snapshot.summary.recoverable_count, 1);
        assert_eq!(snapshot.summary.message, "存在可恢复的转发");
    }

    #[test]
    fn start_rule_to_store_launches_ssh_and_persists_connected_runtime_snapshot() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration_with_ssh_rule())
            .expect("configuration saves");
        let launched = Rc::new(RefCell::new(Vec::new()));
        let provider = OpenSshProvider::new(MockLauncher {
            launched: launched.clone(),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
            },
        });

        let snapshot = start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "rule-react".to_string(),
            },
            provider,
        )
        .expect("rule starts");

        assert_eq!(launched.borrow().len(), 1);
        assert_eq!(
            launched.borrow()[0].args,
            vec![
                "-N",
                "-T",
                "-o",
                "ExitOnForwardFailure=yes",
                "-o",
                "ServerAliveInterval=15",
                "-o",
                "ServerAliveCountMax=2",
                "-p",
                "22",
                "-L",
                "3000:127.0.0.1:3000",
                "-L",
                "3001:127.0.0.1:3001",
                "admin@192.168.1.5",
            ]
        );
        assert!(snapshot
            .last_action
            .as_ref()
            .is_some_and(|status| status.ok));
        assert_eq!(snapshot.summary.connected_hosts, 1);
        assert_eq!(snapshot.summary.running_forwards, 1);
        assert_eq!(snapshot.summary.recoverable_count, 0);

        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.rule_id, "rule-react");
        assert_eq!(row.runtime_id.as_deref(), Some("runtime-rule-react"));
        assert_eq!(row.recovery_id, None);
        assert_eq!(row.state, RunRecoveryRowState::Connected);
        assert_eq!(row.status_text, "运行中");
        assert_eq!(row.provider_label, "SSH · 家");
        assert_eq!(row.port_summary, "3000 + 3001");
        assert_eq!(
            row.entry_url.as_deref(),
            Some("http://react.home.localhost:3000/")
        );
        assert!(row
            .actions
            .iter()
            .any(|action| action.action == RunRecoveryActionKind::Stop));

        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(runtime_snapshot.instances.len(), 1);
        assert_eq!(
            runtime_snapshot.instances[0].status,
            RuntimeStatus::Connected
        );
        assert_eq!(runtime_snapshot.provider_processes.len(), 1);
        assert_eq!(runtime_snapshot.provider_processes[0].pid, 4242);
        assert_eq!(
            runtime_snapshot.provider_processes[0].provider_kind,
            ProviderProcessKind::OpenSsh
        );
        assert!(runtime_snapshot.provider_processes[0]
            .command_summary
            .contains("ssh -N -T"));
        assert!(runtime_snapshot.events.iter().any(|event| {
            event.kind == RuntimeEventKind::SshStartRequested
                && event.rule_id.as_ref().map(|rule_id| rule_id.as_str()) == Some("rule-react")
                && event
                    .detail
                    .as_deref()
                    .is_some_and(|detail| detail.contains("3000:127.0.0.1:3000"))
        }));
        assert!(runtime_snapshot.events.iter().any(|event| {
            event.kind == RuntimeEventKind::SshStartSucceeded
                && event.rule_id.as_ref().map(|rule_id| rule_id.as_str()) == Some("rule-react")
                && event
                    .detail
                    .as_deref()
                    .is_some_and(|detail| detail.contains("pid=4242"))
        }));
    }

    #[test]
    fn start_rule_to_store_returns_structured_error_for_missing_rule() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration_with_ssh_rule())
            .expect("configuration saves");
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: None,
                exit: None,
            },
        });

        let error = start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "missing-rule".to_string(),
            },
            provider,
        )
        .expect_err("missing rule must fail");

        assert_eq!(error.code, BridgeErrorCode::RegistryValidationFailed);
        assert_eq!(error.summary, "未找到要启动的规则");
        assert!(error
            .detail
            .as_deref()
            .is_some_and(|detail| detail.contains("missing-rule")));
    }

    #[test]
    fn start_rule_to_store_maps_non_ssh_provider_target_error() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration())
            .expect("configuration saves");
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: None,
                exit: None,
            },
        });

        let error = start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "rule-react".to_string(),
            },
            provider,
        )
        .expect_err("non-ssh target must fail");

        assert_eq!(error.code, BridgeErrorCode::UnsupportedProviderTarget);
        assert_eq!(error.affected_rule_id.as_deref(), Some("rule-react"));
    }

    #[test]
    fn load_run_recovery_snapshot_projects_saved_runtime_instances() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
            },
        });
        start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "rule-react".to_string(),
            },
            provider,
        )
        .expect("rule starts");

        let snapshot = load_run_recovery_snapshot_from_store(
            &mut store,
            &MockPidController::running(),
            &MockTunnelHealthChecker::healthy(),
        )
        .expect("run/recovery snapshot loads");

        assert_eq!(
            snapshot.hosts[0].rows[0].state,
            RunRecoveryRowState::Connected
        );
        assert_eq!(
            snapshot.hosts[0].rows[0].runtime_id.as_deref(),
            Some("runtime-rule-react")
        );
        assert_eq!(snapshot.summary.recoverable_count, 0);
    }

    #[test]
    fn load_run_recovery_snapshot_marks_running_pid_unhealthy_tunnel_reconnecting() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration_with_ssh_rule())
            .expect("configuration saves");
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
            },
        });
        start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "rule-react".to_string(),
            },
            provider,
        )
        .expect("rule starts");

        let snapshot = load_run_recovery_snapshot_from_store(
            &mut store,
            &MockPidController::running(),
            &MockTunnelHealthChecker::unhealthy(),
        )
        .expect("run/recovery snapshot loads");

        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.state, RunRecoveryRowState::Reconnecting);
        assert_eq!(row.status_text, "重连中");
        assert_eq!(snapshot.summary.issue_count, 1);
        assert_eq!(
            row.error.as_ref().map(|error| error.code.as_str()),
            Some("tunnel_health_check_failed")
        );
        assert!(row
            .error
            .as_ref()
            .and_then(|error| error.detail.as_deref())
            .is_some_and(|detail| detail.contains("local_port=3000")));
        assert!(snapshot.hosts[0]
            .health_summary
            .as_deref()
            .is_some_and(|summary| summary.contains("0 运行 / 1 异常")));
        assert!(snapshot.events.iter().any(|event| {
            event.kind == "runtime_health_warning"
                && event.level == RunRecoveryEventLevel::Warning
                && event.rule_id.as_deref() == Some("rule-react")
        }));

        let persisted = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(persisted.instances[0].status, RuntimeStatus::Reconnecting);
        assert_eq!(
            persisted.instances[0]
                .last_error
                .as_ref()
                .map(|error| &error.code),
            Some(&RuntimeErrorCode::TunnelHealthCheckFailed)
        );
    }

    #[test]
    fn load_run_recovery_snapshot_reconciles_missing_pid_into_recovery() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration_with_ssh_rule())
            .expect("configuration saves");
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
            },
        });
        start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "rule-react".to_string(),
            },
            provider,
        )
        .expect("rule starts");

        let snapshot = load_run_recovery_snapshot_from_store(
            &mut store,
            &MockPidController::missing(),
            &MockTunnelHealthChecker::healthy(),
        )
        .expect("run/recovery snapshot loads");

        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.state, RunRecoveryRowState::Recoverable);
        assert_eq!(row.runtime_id, None);
        assert_eq!(row.recovery_id.as_deref(), Some("recovery-rule-react"));
        assert_eq!(
            row.error.as_ref().map(|error| error.code.as_str()),
            Some("stopped_from_connected")
        );
        assert_eq!(snapshot.summary.running_forwards, 0);
        assert_eq!(snapshot.summary.recoverable_count, 1);

        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert!(runtime_snapshot.instances.is_empty());
        assert!(runtime_snapshot.provider_processes.is_empty());
        assert_eq!(
            store
                .load_recovery_collection()
                .expect("recovery loads")
                .items
                .len(),
            1
        );
    }

    #[test]
    fn stop_runtime_instance_terminates_pid_removes_runtime_and_adds_recovery() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration_with_ssh_rule())
            .expect("configuration saves");
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
            },
        });
        start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "rule-react".to_string(),
            },
            provider,
        )
        .expect("rule starts");
        let terminated = Rc::new(RefCell::new(Vec::new()));

        let snapshot = stop_runtime_instance_in_store(
            &mut store,
            StopRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            MockPidController::with_terminated(terminated.clone()),
        )
        .expect("runtime stops");

        assert_eq!(*terminated.borrow(), vec![4242]);
        assert!(snapshot
            .last_action
            .as_ref()
            .is_some_and(|status| status.ok));
        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.state, RunRecoveryRowState::Recoverable);
        assert_eq!(row.runtime_id, None);
        assert_eq!(row.recovery_id.as_deref(), Some("recovery-rule-react"));
        assert_eq!(snapshot.summary.running_forwards, 0);
        assert_eq!(snapshot.summary.recoverable_count, 1);

        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert!(runtime_snapshot.instances.is_empty());
        assert!(runtime_snapshot.provider_processes.is_empty());
        assert_eq!(
            store
                .load_recovery_collection()
                .expect("recovery loads")
                .items
                .len(),
            1
        );
    }

    #[test]
    fn stop_runtime_instance_requires_persisted_pid_metadata() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration_with_ssh_rule())
            .expect("configuration saves");
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: None,
                exit: None,
            },
        });
        start_rule_to_store(
            &mut store,
            StartRuleCommand {
                rule_id: "rule-react".to_string(),
            },
            provider,
        )
        .expect("rule starts without pid");

        let error = stop_runtime_instance_in_store(
            &mut store,
            StopRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            MockPidController::running(),
        )
        .expect_err("missing pid metadata must fail");

        assert_eq!(error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(
            error.affected_runtime_id.as_deref(),
            Some("runtime-rule-react")
        );
    }

    #[test]
    fn retry_runtime_instance_relaunches_error_runtime_with_current_bindings() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let mut runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![
                crate::runtime::LocalPortBinding::new(3000, "127.0.0.1", 3000),
                crate::runtime::LocalPortBinding::new(3001, "127.0.0.1", 3001),
            ],
        );
        let override_record = runtime
            .apply_local_port_override(3000, 4300, OverrideReason::Manual)
            .expect("override applies");
        runtime.mark_error(crate::runtime::RuntimeErrorInfo::new(
            crate::runtime::RuntimeErrorCode::ProviderExited,
            "OpenSSH process exited",
        ));
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: vec![ProviderProcessRecord {
                    runtime_instance_id: RuntimeInstanceId::from("runtime-rule-react"),
                    provider_kind: ProviderProcessKind::OpenSsh,
                    pid: 4242,
                    command_summary: "old ssh".to_string(),
                    target_label: "SSH · 家".to_string(),
                    started_at: Some(UNIX_EPOCH),
                    last_observed_at: UNIX_EPOCH,
                }],
                local_port_overrides: vec![override_record],
                events: Vec::new(),
            })
            .expect("runtime saves");
        let launched = Rc::new(RefCell::new(Vec::new()));

        let snapshot = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: launched.clone(),
                next_process: MockProcess {
                    pid: Some(6262),
                    exit: None,
                },
            }),
        )
        .expect("runtime retries");

        assert!(launched.borrow()[0]
            .args
            .contains(&"4300:127.0.0.1:3000".to_string()));
        assert!(launched.borrow()[0]
            .args
            .contains(&"3001:127.0.0.1:3001".to_string()));
        assert!(snapshot
            .last_action
            .as_ref()
            .is_some_and(|status| status.ok));
        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.state, RunRecoveryRowState::Connected);
        assert_eq!(row.runtime_id.as_deref(), Some("runtime-rule-react"));
        assert_eq!(row.error, None);
        assert_eq!(row.port_summary, "4300 + 3001");

        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(
            runtime_snapshot.instances[0].status,
            RuntimeStatus::Connected
        );
        assert_eq!(runtime_snapshot.instances[0].last_error, None);
        assert!(runtime_snapshot.instances[0].local_bindings[0].temporary_override);
        assert_eq!(runtime_snapshot.provider_processes.len(), 1);
        assert_eq!(runtime_snapshot.provider_processes[0].pid, 6262);
        assert!(runtime_snapshot.provider_processes[0]
            .command_summary
            .contains("4300:127.0.0.1:3000"));
    }

    #[test]
    fn retry_runtime_instance_allows_reconnecting_runtime() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let mut runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![crate::runtime::LocalPortBinding::new(
                3000,
                "127.0.0.1",
                3000,
            )],
        );
        runtime.mark_reconnecting("keepalive timeout");
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: Vec::new(),
                local_port_overrides: Vec::new(),
                events: Vec::new(),
            })
            .expect("runtime saves");

        let snapshot = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: Some(6263),
                    exit: None,
                },
            }),
        )
        .expect("runtime retries");

        assert_eq!(
            snapshot.hosts[0].rows[0].state,
            RunRecoveryRowState::Connected
        );
        assert_eq!(
            store
                .load_runtime_snapshot()
                .expect("runtime loads")
                .expect("runtime exists")
                .provider_processes[0]
                .pid,
            6263
        );
    }

    #[test]
    fn retry_runtime_instance_returns_structured_errors_for_invalid_inputs() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        store
            .save_configuration(&configuration)
            .expect("configuration saves");

        let empty_error = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "  ".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: Some(1),
                    exit: None,
                },
            }),
        )
        .expect_err("empty runtime id is invalid");
        assert_eq!(empty_error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(empty_error.affected_runtime_id, None);

        let missing_error = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "missing-runtime".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: Some(1),
                    exit: None,
                },
            }),
        )
        .expect_err("missing runtime is invalid");
        assert_eq!(missing_error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(
            missing_error.affected_runtime_id.as_deref(),
            Some("missing-runtime")
        );

        let mut connected_runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![crate::runtime::LocalPortBinding::new(
                3000,
                "127.0.0.1",
                3000,
            )],
        );
        connected_runtime.mark_connected(UNIX_EPOCH);
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![connected_runtime],
                provider_processes: Vec::new(),
                local_port_overrides: Vec::new(),
                events: Vec::new(),
            })
            .expect("runtime saves");

        let state_error = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: Some(1),
                    exit: None,
                },
            }),
        )
        .expect_err("connected runtime is not retryable");
        assert_eq!(state_error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(state_error.affected_rule_id.as_deref(), Some("rule-react"));
        assert_eq!(
            state_error.affected_runtime_id.as_deref(),
            Some("runtime-rule-react")
        );
    }

    #[test]
    fn retry_runtime_instance_requires_provider_pid_before_persisting_retry() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let mut runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![crate::runtime::LocalPortBinding::new(
                3000,
                "127.0.0.1",
                3000,
            )],
        );
        runtime.mark_error(crate::runtime::RuntimeErrorInfo::new(
            crate::runtime::RuntimeErrorCode::ProviderExited,
            "OpenSSH process exited",
        ));
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: Vec::new(),
                local_port_overrides: Vec::new(),
                events: Vec::new(),
            })
            .expect("runtime saves");

        let error = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: None,
                    exit: None,
                },
            }),
        )
        .expect_err("retried runtime without pid metadata must fail");

        assert_eq!(error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(error.affected_rule_id.as_deref(), Some("rule-react"));
        assert_eq!(
            error.affected_runtime_id.as_deref(),
            Some("runtime-rule-react")
        );
        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(runtime_snapshot.instances[0].status, RuntimeStatus::Error);
        assert!(runtime_snapshot.provider_processes.is_empty());
    }

    #[test]
    fn retry_runtime_instance_clears_stale_pid_when_launch_fails() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let mut runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![crate::runtime::LocalPortBinding::new(
                3000,
                "127.0.0.1",
                3000,
            )],
        );
        runtime.mark_error(crate::runtime::RuntimeErrorInfo::new(
            crate::runtime::RuntimeErrorCode::ProviderExited,
            "previous OpenSSH process exited",
        ));
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: vec![ProviderProcessRecord {
                    runtime_instance_id: RuntimeInstanceId::from("runtime-rule-react"),
                    provider_kind: ProviderProcessKind::OpenSsh,
                    pid: 4242,
                    command_summary: "old ssh".to_string(),
                    target_label: "SSH · 家".to_string(),
                    started_at: Some(UNIX_EPOCH),
                    last_observed_at: UNIX_EPOCH,
                }],
                local_port_overrides: Vec::new(),
                events: Vec::new(),
            })
            .expect("runtime saves");
        let launched = Rc::new(RefCell::new(Vec::new()));

        let error = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            OpenSshProvider::new(FailingLauncher {
                launched: launched.clone(),
            }),
        )
        .expect_err("spawn failure must be surfaced");

        assert_eq!(error.code, BridgeErrorCode::ProviderProcessFailed);
        assert_eq!(
            error.affected_runtime_id.as_deref(),
            Some("runtime-rule-react")
        );
        assert_eq!(launched.borrow().len(), 1);
        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(runtime_snapshot.instances[0].status, RuntimeStatus::Error);
        assert!(runtime_snapshot.provider_processes.is_empty());
    }

    #[test]
    fn retry_runtime_instance_preserves_diagnostic_failure_without_faking_connected() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let mut runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![crate::runtime::LocalPortBinding::new(
                3000,
                "127.0.0.1",
                3000,
            )],
        );
        runtime.mark_error(crate::runtime::RuntimeErrorInfo::new(
            crate::runtime::RuntimeErrorCode::ProviderExited,
            "previous OpenSSH process exited",
        ));
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: vec![ProviderProcessRecord {
                    runtime_instance_id: RuntimeInstanceId::from("runtime-rule-react"),
                    provider_kind: ProviderProcessKind::OpenSsh,
                    pid: 4242,
                    command_summary: "old ssh".to_string(),
                    target_label: "SSH · 家".to_string(),
                    started_at: Some(UNIX_EPOCH),
                    last_observed_at: UNIX_EPOCH,
                }],
                local_port_overrides: Vec::new(),
                events: Vec::new(),
            })
            .expect("runtime saves");

        let snapshot = retry_runtime_instance_in_store(
            &mut store,
            RetryRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: Some(6264),
                    exit: Some(ProviderProcessExit {
                        code: Some(255),
                        success: false,
                    }),
                },
            }),
        )
        .expect("diagnostic failure returns snapshot status");

        let status = snapshot.last_action.expect("last action exists");
        assert!(!status.ok);
        assert_eq!(
            status.error.as_ref().map(|error| &error.code),
            Some(&BridgeErrorCode::ProviderProcessFailed)
        );
        assert_eq!(snapshot.hosts[0].rows[0].state, RunRecoveryRowState::Error);
        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(runtime_snapshot.instances[0].status, RuntimeStatus::Error);
        assert_eq!(
            runtime_snapshot.instances[0]
                .last_error
                .as_ref()
                .map(|error| &error.summary),
            Some(&"OpenSSH process exited".to_string())
        );
        assert!(runtime_snapshot.provider_processes.is_empty());
    }

    #[test]
    fn retry_runtime_instance_command_accepts_only_runtime_id_input() {
        let command: BridgeCommand = serde_json::from_value(json!({
            "command": "retry_runtime_instance",
            "runtime_id": "runtime-rule-react"
        }))
        .expect("retry command decodes");

        assert_eq!(
            command,
            BridgeCommand::RetryRuntimeInstance(RetryRuntimeInstanceCommand {
                runtime_id: "runtime-rule-react".to_string(),
            })
        );

        let error = serde_json::from_value::<BridgeCommand>(json!({
            "command": "retry_runtime_instance",
            "runtime_id": "runtime-rule-react",
            "snapshot": load_run_recovery_snapshot()
        }))
        .expect_err("retry command must reject Swift-submitted snapshots");

        assert!(error.to_string().contains("unknown field `snapshot`"));
    }

    #[test]
    fn load_run_recovery_snapshot_reconciles_runtime_without_pid_metadata_into_recovery() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let mut runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![crate::runtime::LocalPortBinding::new(
                3000,
                "127.0.0.1",
                3000,
            )],
        );
        runtime.mark_connected(UNIX_EPOCH);

        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: Vec::new(),
                local_port_overrides: Vec::new(),
                events: Vec::new(),
            })
            .expect("runtime saves");

        let snapshot = load_run_recovery_snapshot_from_store(
            &mut store,
            &MockPidController::running(),
            &MockTunnelHealthChecker::healthy(),
        )
        .expect("run/recovery snapshot loads");

        assert_eq!(
            snapshot.hosts[0].rows[0].state,
            RunRecoveryRowState::Recoverable
        );
        assert_eq!(snapshot.hosts[0].rows[0].runtime_id, None);
        assert!(store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists")
            .instances
            .is_empty());
    }

    #[test]
    fn recover_item_restarts_persisted_recovery_item_into_runtime_snapshot() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let recovery = crate::runtime::RecoveryItem {
            rule_id: rule.id.clone(),
            host_id: rule.host_id.clone(),
            provider_target_id: rule.provider_target_id.clone(),
            last_local_bindings: vec![crate::runtime::LocalPortBinding::new(
                4300,
                "127.0.0.1",
                3000,
            )],
            last_seen_status: RuntimeStatus::Connected,
            recoverable_since: UNIX_EPOCH,
        };
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_recovery_collection(&RecoveryCollection {
                items: vec![recovery],
            })
            .expect("recovery saves");
        let launched = Rc::new(RefCell::new(Vec::new()));

        let snapshot = recover_item_in_store(
            &mut store,
            RecoverItemCommand {
                rule_id: "rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: launched.clone(),
                next_process: MockProcess {
                    pid: Some(5252),
                    exit: None,
                },
            }),
        )
        .expect("item recovers");

        assert_eq!(launched.borrow().len(), 1);
        assert!(launched.borrow()[0]
            .args
            .contains(&"4300:127.0.0.1:3000".to_string()));
        assert!(snapshot
            .last_action
            .as_ref()
            .is_some_and(|status| status.ok));

        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.state, RunRecoveryRowState::Connected);
        assert_eq!(row.runtime_id.as_deref(), Some("runtime-rule-react"));
        assert_eq!(row.port_summary, "4300");
        assert!(store
            .load_recovery_collection()
            .expect("recovery loads")
            .items
            .is_empty());

        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(runtime_snapshot.instances.len(), 1);
        assert_eq!(runtime_snapshot.provider_processes[0].pid, 5252);
    }

    #[test]
    fn apply_local_port_override_recovers_without_mutating_saved_rule_configuration() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let recovery = crate::runtime::RecoveryItem {
            rule_id: rule.id.clone(),
            host_id: rule.host_id.clone(),
            provider_target_id: rule.provider_target_id.clone(),
            last_local_bindings: vec![
                crate::runtime::LocalPortBinding::new(4300, "127.0.0.1", 3000),
                crate::runtime::LocalPortBinding::new(4301, "127.0.0.1", 3001),
            ],
            last_seen_status: RuntimeStatus::Connected,
            recoverable_since: UNIX_EPOCH,
        };
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_recovery_collection(&RecoveryCollection {
                items: vec![recovery],
            })
            .expect("recovery saves");
        let launched = Rc::new(RefCell::new(Vec::new()));

        let snapshot = apply_local_port_override_in_store(
            &mut store,
            ApplyLocalPortOverrideCommand {
                rule_id: "rule-react".to_string(),
                local_port: 5300,
            },
            OpenSshProvider::new(MockLauncher {
                launched: launched.clone(),
                next_process: MockProcess {
                    pid: Some(5253),
                    exit: None,
                },
            }),
        )
        .expect("item recovers with override");

        assert!(launched.borrow()[0]
            .args
            .contains(&"5300:127.0.0.1:3000".to_string()));
        assert!(launched.borrow()[0]
            .args
            .contains(&"4301:127.0.0.1:3001".to_string()));
        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.state, RunRecoveryRowState::Connected);
        assert_eq!(row.port_summary, "5300 + 4301");

        let configuration = store
            .load_configuration()
            .expect("configuration loads")
            .expect("configuration exists");
        assert_eq!(configuration.rules[0].main_port.local_port, 3000);
        assert_eq!(configuration.rules[0].secondary_ports[0].local_port, 3001);

        let runtime_snapshot = store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .expect("runtime exists");
        assert_eq!(runtime_snapshot.local_port_overrides.len(), 1);
        assert_eq!(runtime_snapshot.local_port_overrides[0].original_port, 4300);
        assert_eq!(
            runtime_snapshot.local_port_overrides[0].effective_port,
            5300
        );
        assert!(!runtime_snapshot.local_port_overrides[0].persisted);
        assert!(runtime_snapshot.instances[0].local_bindings[0].temporary_override);
        assert_eq!(
            runtime_snapshot.instances[0].local_bindings[1].local_port,
            4301
        );
    }

    #[test]
    fn recover_item_requires_provider_pid_before_persisting_recovered_runtime() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let recovery = crate::runtime::RecoveryItem {
            rule_id: rule.id.clone(),
            host_id: rule.host_id.clone(),
            provider_target_id: rule.provider_target_id.clone(),
            last_local_bindings: vec![crate::runtime::LocalPortBinding::new(
                4300,
                "127.0.0.1",
                3000,
            )],
            last_seen_status: RuntimeStatus::Connected,
            recoverable_since: UNIX_EPOCH,
        };
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_recovery_collection(&RecoveryCollection {
                items: vec![recovery],
            })
            .expect("recovery saves");

        let error = recover_item_in_store(
            &mut store,
            RecoverItemCommand {
                rule_id: "rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: None,
                    exit: None,
                },
            }),
        )
        .expect_err("recovered runtime without pid metadata must fail");

        assert_eq!(error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(error.affected_rule_id.as_deref(), Some("rule-react"));
        assert_eq!(
            error.affected_runtime_id.as_deref(),
            Some("runtime-rule-react")
        );
        assert!(store
            .load_runtime_snapshot()
            .expect("runtime loads")
            .is_none());
        assert_eq!(
            store
                .load_recovery_collection()
                .expect("recovery loads")
                .items
                .len(),
            1
        );
    }

    #[test]
    fn clear_recovery_item_removes_persisted_recovery_without_deleting_saved_rule() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration_with_ssh_rule();
        let rule = &configuration.rules[0];
        let recovery = crate::runtime::RecoveryItem {
            rule_id: rule.id.clone(),
            host_id: rule.host_id.clone(),
            provider_target_id: rule.provider_target_id.clone(),
            last_local_bindings: vec![crate::runtime::LocalPortBinding::new(
                4300,
                "127.0.0.1",
                3000,
            )],
            last_seen_status: RuntimeStatus::Error,
            recoverable_since: UNIX_EPOCH,
        };
        store
            .save_configuration(&configuration)
            .expect("configuration saves");
        store
            .save_recovery_collection(&RecoveryCollection {
                items: vec![recovery],
            })
            .expect("recovery saves");

        let snapshot = clear_recovery_item_in_store(
            &mut store,
            ClearRecoveryItemCommand {
                recovery_id: "recovery-rule-react".to_string(),
            },
        )
        .expect("recovery clears");

        assert!(store
            .load_recovery_collection()
            .expect("recovery loads")
            .items
            .is_empty());
        assert_eq!(
            store
                .load_configuration()
                .expect("configuration loads")
                .expect("configuration exists")
                .rules
                .len(),
            1
        );
        let row = &snapshot.hosts[0].rows[0];
        assert_eq!(row.state, RunRecoveryRowState::Recoverable);
        assert_eq!(row.port_summary, "3000 + 3001");
        assert_eq!(
            row.error.as_ref().map(|error| error.code.as_str()),
            Some("configured_not_running")
        );
    }

    #[test]
    fn real_recovery_actions_return_structured_errors_for_invalid_inputs() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration_with_ssh_rule())
            .expect("configuration saves");

        let port_error = apply_local_port_override_in_store(
            &mut store,
            ApplyLocalPortOverrideCommand {
                rule_id: "rule-react".to_string(),
                local_port: 0,
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: None,
                    exit: None,
                },
            }),
        )
        .expect_err("zero port is invalid");
        assert_eq!(port_error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(port_error.affected_rule_id.as_deref(), Some("rule-react"));

        let recovery_error = clear_recovery_item_in_store(
            &mut store,
            ClearRecoveryItemCommand {
                recovery_id: "not-a-recovery-id".to_string(),
            },
        )
        .expect_err("recovery id is invalid");
        assert_eq!(recovery_error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(
            recovery_error.affected_recovery_id.as_deref(),
            Some("not-a-recovery-id")
        );

        let missing_rule_error = recover_item_in_store(
            &mut store,
            RecoverItemCommand {
                rule_id: "missing-rule".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: None,
                    exit: None,
                },
            }),
        )
        .expect_err("missing rule is invalid");
        assert_eq!(
            missing_rule_error.code,
            BridgeErrorCode::RegistryValidationFailed
        );

        let rule = &sample_configuration_with_ssh_rule().rules[0];
        let runtime = crate::runtime::RuntimeInstance::new(
            RuntimeInstanceId::from("runtime-rule-react"),
            rule.id.clone(),
            rule.host_id.clone(),
            rule.provider_target_id.clone(),
            vec![crate::runtime::LocalPortBinding::new(
                3000,
                "127.0.0.1",
                3000,
            )],
        );
        store
            .save_runtime_snapshot(&RuntimeSnapshot {
                instances: vec![runtime],
                provider_processes: Vec::new(),
                local_port_overrides: Vec::new(),
                events: Vec::new(),
            })
            .expect("runtime saves");

        let running_error = recover_item_in_store(
            &mut store,
            RecoverItemCommand {
                rule_id: "rule-react".to_string(),
            },
            OpenSshProvider::new(MockLauncher {
                launched: Rc::new(RefCell::new(Vec::new())),
                next_process: MockProcess {
                    pid: None,
                    exit: None,
                },
            }),
        )
        .expect_err("running runtime blocks recovery");
        assert_eq!(running_error.code, BridgeErrorCode::RuntimeLifecycleFailed);
        assert_eq!(
            running_error.affected_runtime_id.as_deref(),
            Some("runtime-rule-react")
        );
    }

    #[test]
    fn registry_bridge_command_json_round_trips_to_structured_success_response() {
        let command: BridgeCommand = serde_json::from_value(json!({
            "command": "load_registry_snapshot"
        }))
        .expect("command JSON decodes");

        let response =
            BridgeResponse::success(execute_bridge_command(command).expect("command executes"));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], true);
        assert_eq!(json["result"]["type"], "registry_snapshot");
        assert_eq!(json["result"]["hosts"].as_array().map(Vec::len), Some(0));
        assert_eq!(json["result"]["selected_host_id"], "");
    }

    #[test]
    fn storage_backed_registry_snapshot_projects_saved_configuration() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration();
        store
            .save_configuration(&configuration)
            .expect("configuration saves");

        let snapshot = load_registry_snapshot_from_store(&store).expect("snapshot loads");

        assert_eq!(snapshot.hosts.len(), 1);
        assert_eq!(snapshot.selected_host_id, "host-home");
        assert_eq!(snapshot.hosts[0].provider_targets.len(), 2);
        assert_eq!(snapshot.hosts[0].rules[0].port_summary, "3000 + 3001");
        assert_eq!(
            snapshot.hosts[0].rules[0].runtime_state,
            RegistryRuleRuntimeState::Stopped
        );
        assert_eq!(
            snapshot.hosts[0].presets[0].rules[0].target_label,
            "SSH · 家"
        );
    }

    #[test]
    fn save_registry_host_to_store_bootstraps_and_persists_first_host() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let snapshot = save_registry_host_to_store(
            &mut store,
            SaveRegistryHostCommand {
                host: RegistryHostDraft {
                    id: None,
                    name: "Mac Studio".to_string(),
                    address: "10.0.4.5".to_string(),
                    port: Some(22),
                    user: Some("admin".to_string()),
                    tags: vec!["office".to_string()],
                    os_hint: RegistryHostOsHint::Macos,
                    os_distro: None,
                    status: RegistryHostStatus::Online,
                    provider_targets: vec![RegistryProviderTargetDraft {
                        id: None,
                        label: "SSH · 办公室".to_string(),
                        kind: RegistryProviderKind::Ssh,
                        target_address: "10.0.4.5".to_string(),
                        target_port: Some(22),
                    }],
                },
            },
        )
        .expect("host saves");

        assert_eq!(snapshot.hosts.len(), 1);
        assert_eq!(snapshot.hosts[0].name, "Mac Studio");
        assert_eq!(snapshot.hosts[0].provider_targets[0].label, "SSH · 办公室");
        assert_eq!(
            store
                .load_configuration()
                .expect("configuration loads")
                .expect("configuration exists")
                .hosts[0]
                .name,
            "Mac Studio"
        );
    }

    #[test]
    fn save_registry_rule_to_store_updates_rule_and_projects_new_summary() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let configuration = sample_configuration();
        store
            .save_configuration(&configuration)
            .expect("configuration saves");

        let snapshot = save_registry_rule_to_store(
            &mut store,
            SaveRegistryRuleCommand {
                rule: RegistryRuleDraft {
                    id: Some("rule-react".to_string()),
                    host_id: "host-home".to_string(),
                    service_name: "React 前端".to_string(),
                    alias: Some("react.office.localhost".to_string()),
                    provider_target_id: "target-home-ssh".to_string(),
                    remote_host: "127.0.0.1".to_string(),
                    main_local_port: 4300,
                    main_remote_host: "127.0.0.1".to_string(),
                    main_remote_port: 3000,
                    secondary_ports: vec![RegistryPortMapping {
                        local_port: 4301,
                        remote_host: "127.0.0.1".to_string(),
                        remote_port: 3001,
                    }],
                    kind: Some("web".to_string()),
                    tags: vec!["frontend".to_string(), "office".to_string()],
                    notes: Some("updated".to_string()),
                },
            },
        )
        .expect("rule saves");

        let rule = &snapshot.hosts[0].rules[0];
        assert_eq!(rule.alias, "react.office.localhost");
        assert_eq!(rule.provider_label, "SSH · 家");
        assert_eq!(rule.port_summary, "4300 + 4301");
        assert_eq!(rule.main_local_port, 4300);
        assert_eq!(rule.secondary_ports.len(), 1);
    }

    #[test]
    fn save_registry_rule_to_store_rejects_missing_host_reference() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        store
            .save_configuration(&sample_configuration())
            .expect("configuration saves");

        let error = save_registry_rule_to_store(
            &mut store,
            SaveRegistryRuleCommand {
                rule: RegistryRuleDraft {
                    id: None,
                    host_id: "missing-host".to_string(),
                    service_name: "导入规则".to_string(),
                    alias: None,
                    provider_target_id: "target-home-ssh".to_string(),
                    remote_host: "127.0.0.1".to_string(),
                    main_local_port: 18317,
                    main_remote_host: "127.0.0.1".to_string(),
                    main_remote_port: 18317,
                    secondary_ports: Vec::new(),
                    kind: Some("web".to_string()),
                    tags: Vec::new(),
                    notes: None,
                },
            },
        )
        .expect_err("missing host reference must fail");

        assert_eq!(error.code, BridgeErrorCode::RegistryValidationFailed);
        assert_eq!(error.summary, "规则引用的主机不存在");
    }

    #[test]
    fn save_registry_rule_to_store_rejects_provider_target_from_another_host() {
        let mut store = RelayDockStore::in_memory().expect("store opens");
        let mut configuration = sample_configuration();
        let other_host_id = HostId::from("host-other");
        configuration.hosts.push(DomainHost {
            id: other_host_id.clone(),
            name: "Other Host".to_string(),
            address: "10.0.0.8".to_string(),
            port: Some(22),
            user: Some("admin".to_string()),
            tags: Vec::new(),
            os_family: OsFamily::Linux,
            os_distro: None,
            status_hint: HostStatusHint::Unknown,
            provider_targets: vec![DomainProviderTarget {
                id: ProviderTargetId::from("target-other-ssh"),
                host_id: other_host_id,
                target_type: ProviderTargetType::Ssh,
                label: "SSH · 其他".to_string(),
                target_address: "10.0.0.8".to_string(),
                target_port: Some(22),
                auth_ref: None,
                meta: Metadata::new(),
            }],
        });
        store
            .save_configuration(&configuration)
            .expect("configuration saves");

        let error = save_registry_rule_to_store(
            &mut store,
            SaveRegistryRuleCommand {
                rule: RegistryRuleDraft {
                    id: None,
                    host_id: "host-home".to_string(),
                    service_name: "导入规则".to_string(),
                    alias: None,
                    provider_target_id: "target-other-ssh".to_string(),
                    remote_host: "127.0.0.1".to_string(),
                    main_local_port: 18317,
                    main_remote_host: "127.0.0.1".to_string(),
                    main_remote_port: 18317,
                    secondary_ports: Vec::new(),
                    kind: Some("web".to_string()),
                    tags: Vec::new(),
                    notes: None,
                },
            },
        )
        .expect_err("provider target from another host must fail");

        assert_eq!(error.code, BridgeErrorCode::RegistryValidationFailed);
        assert_eq!(error.summary, "规则引用的 provider target 不属于该主机");
    }

    #[test]
    fn invalid_registry_host_draft_returns_structured_validation_error() {
        let error = save_registry_host_to_store(
            &mut RelayDockStore::in_memory().expect("store opens"),
            SaveRegistryHostCommand {
                host: RegistryHostDraft {
                    id: None,
                    name: "".to_string(),
                    address: "".to_string(),
                    port: Some(22),
                    user: None,
                    tags: Vec::new(),
                    os_hint: RegistryHostOsHint::Macos,
                    os_distro: None,
                    status: RegistryHostStatus::Online,
                    provider_targets: Vec::new(),
                },
            },
        )
        .expect_err("invalid host draft must fail");

        assert_eq!(error.code, BridgeErrorCode::RegistryValidationFailed);
    }

    #[test]
    fn bridge_error_response_preserves_code_and_diagnostic_detail() {
        let response = BridgeResponse::failure(BridgeError::invalid_command(
            "Command JSON could not be parsed",
            Some("missing field `command`".to_string()),
        ));
        let json = serde_json::to_value(response).expect("response serializes");

        assert_eq!(json["ok"], false);
        assert_eq!(json["error"]["code"], "invalid_command");
        assert_eq!(json["error"]["detail"], "missing field `command`");
        assert_eq!(
            json["error"]["suggested_recovery"],
            "Send one supported RelayDock bridge command as JSON."
        );
    }
}
