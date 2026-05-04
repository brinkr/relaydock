use crate::ports::{detect_conflict, next_available_port, PortClaim, PortConflict, PortUsage};
use serde::{Deserialize, Serialize};

const DEMO_REFRESHED_AT_EPOCH_SECONDS: u64 = 1_777_777_777;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum BridgeCommand {
    CheckPortClaim(CheckPortClaimCommand),
    LoadRunRecoverySnapshot,
    LoadRegistrySnapshot,
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
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BridgeCommandResult {
    PortClaimCheck(PortClaimCheckResult),
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
pub struct RunRecoverySnapshotResult {
    pub refreshed_at_epoch_seconds: u64,
    pub hosts: Vec<RunRecoveryHost>,
    pub summary: RunRecoverySummary,
    pub last_action: Option<RunRecoveryActionStatus>,
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
    pub rows: Vec<RunRecoveryRow>,
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
            .filter(|row| row.state == RunRecoveryRowState::Error)
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
    pub provider_targets: Vec<RegistryProviderTarget>,
    pub presets: Vec<RegistryPreset>,
    pub rules: Vec<RegistryRule>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RegistryHostStatus {
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
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryProviderTarget {
    pub id: String,
    pub label: String,
    pub kind: RegistryProviderKind,
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
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BridgeErrorCode {
    InvalidCommand,
    InternalError,
    InvalidDemoAction,
}

pub fn execute_bridge_command(
    command: BridgeCommand,
) -> Result<BridgeCommandResult, Box<BridgeError>> {
    match command {
        BridgeCommand::CheckPortClaim(command) => Ok(BridgeCommandResult::PortClaimCheck(
            check_port_claim(command.claim, command.known_usages),
        )),
        BridgeCommand::LoadRunRecoverySnapshot => Ok(BridgeCommandResult::RunRecoverySnapshot(
            load_run_recovery_snapshot(),
        )),
        BridgeCommand::LoadRegistrySnapshot => Ok(BridgeCommandResult::RegistrySnapshot(
            load_registry_snapshot(),
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

pub fn load_run_recovery_snapshot() -> RunRecoverySnapshotResult {
    demo_run_recovery_snapshot().recomputed(None)
}

pub fn load_registry_snapshot() -> RegistrySnapshotResult {
    demo_registry_snapshot()
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

fn demo_registry_snapshot() -> RegistrySnapshotResult {
    RegistrySnapshotResult {
        refreshed_at_epoch_seconds: demo_now_epoch_seconds(),
        selected_host_id: "host-home-mac-mini".to_string(),
        hosts: vec![
            RegistryHost {
                id: "host-home-mac-mini".to_string(),
                name: "Mac mini (M2) - 家".to_string(),
                endpoint: "admin@192.168.1.5".to_string(),
                status: RegistryHostStatus::Online,
                os_hint: RegistryHostOsHint::Macos,
                provider_targets: vec![
                    registry_target(
                        "target-home-ssh",
                        "家庭宽带 (SSH)",
                        RegistryProviderKind::Ssh,
                    ),
                    registry_target(
                        "target-home-ts",
                        "Tailscale 组网",
                        RegistryProviderKind::Tailscale,
                    ),
                ],
                presets: home_presets(),
                rules: home_registry_rules(),
            },
            registry_host_summary(
                "host-ubuntu-dev",
                "Ubuntu Dev Server",
                "root@10.0.0.12",
                RegistryHostStatus::Online,
                RegistryHostOsHint::Ubuntu,
            ),
            registry_host_summary(
                "host-windows-web",
                "Windows Web 测试",
                "test@10.0.0.105",
                RegistryHostStatus::Online,
                RegistryHostOsHint::Windows,
            ),
            registry_host_summary(
                "host-san-jose",
                "San Jose 节点",
                "ubuntu@sj.example.com",
                RegistryHostStatus::Online,
                RegistryHostOsHint::Ubuntu,
            ),
            registry_host_summary(
                "host-aws-tokyo",
                "AWS Tokyo GPU",
                "ec2-user@tk.example.com",
                RegistryHostStatus::Offline,
                RegistryHostOsHint::Linux,
            ),
            registry_host_summary(
                "host-raspberry-pi",
                "Raspberry Pi",
                "pi@192.168.1.100",
                RegistryHostStatus::Online,
                RegistryHostOsHint::RaspberryPi,
            ),
            registry_host_summary(
                "host-oracle-frankfurt",
                "Oracle Frankfurt",
                "opc@130.60.0.1",
                RegistryHostStatus::Online,
                RegistryHostOsHint::Linux,
            ),
            registry_host_summary(
                "host-homelab-02",
                "Homelab Node 02",
                "admin@192.168.1.20",
                RegistryHostStatus::Offline,
                RegistryHostOsHint::Ubuntu,
            ),
            registry_host_summary(
                "host-mac-studio-office",
                "Mac Studio - Office",
                "admin@10.0.4.5",
                RegistryHostStatus::Online,
                RegistryHostOsHint::Macos,
            ),
            registry_host_summary(
                "host-centos-build",
                "CentOS Build Node",
                "build@10.0.0.45",
                RegistryHostStatus::Online,
                RegistryHostOsHint::Linux,
            ),
            registry_host_summary(
                "host-windows-gaming",
                "Windows Gaming PC",
                "gamer@192.168.1.150",
                RegistryHostStatus::Offline,
                RegistryHostOsHint::Windows,
            ),
            registry_host_summary(
                "host-hetzner-dedicated",
                "Hetzner Dedicated",
                "root@116.20.0.10",
                RegistryHostStatus::Online,
                RegistryHostOsHint::Ubuntu,
            ),
        ],
    }
}

fn registry_host_summary(
    id: &str,
    name: &str,
    endpoint: &str,
    status: RegistryHostStatus,
    os_hint: RegistryHostOsHint,
) -> RegistryHost {
    RegistryHost {
        id: id.to_string(),
        name: name.to_string(),
        endpoint: endpoint.to_string(),
        status,
        os_hint,
        provider_targets: vec![registry_target(
            &format!("{id}-ssh"),
            "SSH",
            RegistryProviderKind::Ssh,
        )],
        presets: Vec::new(),
        rules: Vec::new(),
    }
}

fn registry_target(id: &str, label: &str, kind: RegistryProviderKind) -> RegistryProviderTarget {
    RegistryProviderTarget {
        id: id.to_string(),
        label: label.to_string(),
        kind,
    }
}

fn home_presets() -> Vec<RegistryPreset> {
    vec![
        RegistryPreset {
            id: "preset-home-daily".to_string(),
            name: "日常开发 (基础)".to_string(),
            derived_from: None,
            rules: vec![
                preset_rule("React 前端", "家庭宽带 (SSH)"),
                preset_rule("FastAPI Backend", "家庭宽带 (SSH)"),
                preset_rule("PostgreSQL Main", "家庭宽带 (SSH)"),
                preset_rule("Redis Cache", "家庭宽带 (SSH)"),
            ],
        },
        RegistryPreset {
            id: "preset-home-office".to_string(),
            name: "公司办公 (派生)".to_string(),
            derived_from: Some("日常开发 (基础)".to_string()),
            rules: vec![
                preset_rule("React 前端", "Tailscale 组网"),
                preset_rule("FastAPI Backend", "Tailscale 组网"),
            ],
        },
    ]
}

fn preset_rule(service_name: &str, target_label: &str) -> RegistryPresetRule {
    RegistryPresetRule {
        service_name: service_name.to_string(),
        target_label: target_label.to_string(),
    }
}

fn home_registry_rules() -> Vec<RegistryRule> {
    vec![
        registry_rule(
            "react-frontend",
            "React 前端",
            "react.home.localhost",
            "Tailscale · 家里",
            "3000",
            RegistryRuleRuntimeState::Running,
        ),
        registry_rule(
            "fastapi-backend",
            "FastAPI Backend",
            "api.home.localhost",
            "Tailscale · 家里",
            "8000",
            RegistryRuleRuntimeState::Running,
        ),
        registry_rule(
            "postgres-main",
            "PostgreSQL Main",
            "pg.home.localhost",
            "SSH · 家庭宽带",
            "5432",
            RegistryRuleRuntimeState::Recoverable,
        ),
        registry_rule(
            "redis-cache",
            "Redis Cache",
            "redis.home.localhost",
            "SSH · 家庭宽带",
            "6379",
            RegistryRuleRuntimeState::Running,
        ),
        registry_rule(
            "go-microservice",
            "Go Microservice",
            "go.home.localhost",
            "SSH · 家庭宽带",
            "8081",
            RegistryRuleRuntimeState::Running,
        ),
        registry_rule(
            "nextjs-app",
            "Next.js App",
            "next.home.localhost",
            "Tailscale · 家里",
            "3001",
            RegistryRuleRuntimeState::Running,
        ),
        registry_rule(
            "rabbitmq",
            "RabbitMQ",
            "mq.home.localhost",
            "SSH · 家庭宽带",
            "5672 + 15672",
            RegistryRuleRuntimeState::Error,
        ),
        registry_rule(
            "elasticsearch",
            "ElasticSearch",
            "es.home.localhost",
            "SSH · 家庭宽带",
            "9200",
            RegistryRuleRuntimeState::Recoverable,
        ),
        registry_rule(
            "kibana",
            "Kibana",
            "kibana.home.localhost",
            "SSH · 家庭宽带",
            "5601",
            RegistryRuleRuntimeState::Recoverable,
        ),
    ]
}

fn registry_rule(
    slug: &str,
    service_name: &str,
    alias: &str,
    provider_label: &str,
    port_summary: &str,
    runtime_state: RegistryRuleRuntimeState,
) -> RegistryRule {
    RegistryRule {
        id: format!("rule-{slug}"),
        service_name: service_name.to_string(),
        alias: alias.to_string(),
        provider_label: provider_label.to_string(),
        port_summary: port_summary.to_string(),
        runtime_state,
    }
}

fn demo_now_epoch_seconds() -> u64 {
    DEMO_REFRESHED_AT_EPOCH_SECONDS
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::{PortOwnerType, PortProtocol};
    use serde_json::json;

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
        assert_eq!(retried.summary.issue_count, 0);
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
            load_registry_snapshot().hosts[0]
                .rules
                .iter()
                .find(|rule| rule.id == "rule-postgres-main")
                .map(|rule| rule.port_summary.as_str()),
            Some("5432")
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
        assert_eq!(json["result"]["hosts"].as_array().map(Vec::len), Some(12));
        assert_eq!(json["result"]["selected_host_id"], "host-home-mac-mini");
        assert_eq!(
            json["result"]["hosts"][0]["rules"].as_array().map(Vec::len),
            Some(9)
        );
        assert_eq!(
            json["result"]["hosts"][0]["presets"][1]["derived_from"],
            "日常开发 (基础)"
        );
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
