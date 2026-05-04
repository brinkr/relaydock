use crate::ports::{detect_conflict, next_available_port, PortClaim, PortConflict, PortUsage};
use serde::{Deserialize, Serialize};

const DEMO_REFRESHED_AT_EPOCH_SECONDS: u64 = 1_777_777_777;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum BridgeCommand {
    CheckPortClaim(CheckPortClaimCommand),
    LoadRunRecoverySnapshot,
    StartDemoRule(DemoRuleActionCommand),
    StopDemoRuntime(DemoRuntimeActionCommand),
    ClearDemoRecoveryItem(DemoRecoveryActionCommand),
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
        BridgeCommand::StartDemoRule(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            start_demo_rule(command.snapshot, &command.rule_id),
        )),
        BridgeCommand::StopDemoRuntime(command) => Ok(BridgeCommandResult::RunRecoverySnapshot(
            stop_demo_runtime(command.snapshot, &command.runtime_id),
        )),
        BridgeCommand::ClearDemoRecoveryItem(command) => {
            Ok(BridgeCommandResult::RunRecoverySnapshot(
                clear_demo_recovery_item(command.snapshot, &command.recovery_id),
            ))
        }
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
    let hosts = vec![RunRecoveryHost {
        id: "host-home-mac-mini".to_string(),
        name: "Mac mini · 家".to_string(),
        endpoint: "admin@192.168.1.5".to_string(),
        provider_summary: "SSH · 家庭宽带".to_string(),
        rows: vec![running_demo_row(), recoverable_demo_row()],
    }];

    RunRecoverySnapshotResult {
        refreshed_at_epoch_seconds: demo_now_epoch_seconds(),
        summary: RunRecoverySummary::from_hosts(&hosts),
        hosts,
        last_action: None,
    }
}

fn running_demo_row() -> RunRecoveryRow {
    RunRecoveryRow {
        id: "runtime-rule-react-frontend".to_string(),
        rule_id: "rule-react-frontend".to_string(),
        runtime_id: Some("runtime-rule-react-frontend".to_string()),
        recovery_id: None,
        host_id: "host-home-mac-mini".to_string(),
        service_name: "React 前端".to_string(),
        alias: "react.home.localhost".to_string(),
        provider_label: "SSH · 家庭宽带".to_string(),
        port_summary: "3000".to_string(),
        state: RunRecoveryRowState::Connected,
        status_text: "运行中".to_string(),
        telemetry: Some("6h 12m · 2ms · 0次".to_string()),
        error: None,
        actions: vec![RunRecoveryAction {
            action: RunRecoveryActionKind::Stop,
            label: "停止".to_string(),
        }],
    }
}

fn recoverable_demo_row() -> RunRecoveryRow {
    RunRecoveryRow {
        id: "recovery-rule-postgres-main".to_string(),
        rule_id: "rule-postgres-main".to_string(),
        runtime_id: None,
        recovery_id: Some("recovery-rule-postgres-main".to_string()),
        host_id: "host-home-mac-mini".to_string(),
        service_name: "PostgreSQL Main".to_string(),
        alias: "pg.home.localhost".to_string(),
        provider_label: "SSH · 家庭宽带".to_string(),
        port_summary: "5432".to_string(),
        state: RunRecoveryRowState::Recoverable,
        status_text: "待恢复".to_string(),
        telemetry: None,
        error: Some(RunRecoveryRowError {
            code: "provider_exited".to_string(),
            summary: "上次 OpenSSH 进程退出，等待手动恢复".to_string(),
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

        assert_eq!(result.hosts.len(), 1);
        assert_eq!(result.hosts[0].rows.len(), 2);
        assert_eq!(result.summary.connected_hosts, 1);
        assert_eq!(result.summary.running_forwards, 1);
        assert_eq!(result.summary.recoverable_count, 1);
        assert_eq!(
            result.hosts[0].rows[0].state,
            RunRecoveryRowState::Connected
        );
        assert_eq!(
            result.hosts[0].rows[1].state,
            RunRecoveryRowState::Recoverable
        );
    }

    #[test]
    fn demo_start_stop_and_clear_transition_through_structured_snapshots() {
        let loaded = load_run_recovery_snapshot();

        let started = start_demo_rule(loaded, "rule-postgres-main");
        assert_eq!(started.summary.running_forwards, 2);
        assert_eq!(started.summary.recoverable_count, 0);
        assert!(started.last_action.as_ref().is_some_and(|status| status.ok));
        assert!(started.hosts[0].rows.iter().any(|row| {
            row.rule_id == "rule-postgres-main" && row.state == RunRecoveryRowState::Connected
        }));

        let stopped = stop_demo_runtime(started, "runtime-rule-postgres-main");
        assert_eq!(stopped.summary.running_forwards, 1);
        assert_eq!(stopped.summary.recoverable_count, 1);
        assert!(stopped.hosts[0].rows.iter().any(|row| {
            row.rule_id == "rule-postgres-main" && row.state == RunRecoveryRowState::Recoverable
        }));

        let cleared = clear_demo_recovery_item(stopped, "recovery-rule-postgres-main");
        assert_eq!(cleared.summary.running_forwards, 1);
        assert_eq!(cleared.summary.recoverable_count, 0);
        assert!(!cleared.hosts[0]
            .rows
            .iter()
            .any(|row| row.rule_id == "rule-postgres-main"));
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
        assert_eq!(json["result"]["summary"]["running_forwards"], 1);
        assert_eq!(
            json["result"]["hosts"][0]["rows"][1]["actions"][0]["action"],
            "recover"
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
