use crate::domain::{HostId, ProviderTargetId, RuleId, RuntimeInstanceId};
use crate::ports::PortUsage;
use serde::{Deserialize, Serialize};
use std::time::{Duration, SystemTime};
use thiserror::Error;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeInstance {
    pub id: RuntimeInstanceId,
    pub rule_id: RuleId,
    pub host_id: HostId,
    pub provider_target_id: ProviderTargetId,
    pub local_bindings: Vec<LocalPortBinding>,
    pub status: RuntimeStatus,
    pub latency_ms: Option<u32>,
    pub uptime_seconds: Option<u64>,
    pub failure_count_today: u32,
    pub started_at: Option<SystemTime>,
    pub last_error: Option<RuntimeErrorInfo>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeEvent {
    pub id: String,
    pub level: RuntimeEventLevel,
    pub kind: RuntimeEventKind,
    pub summary: String,
    pub detail: Option<String>,
    pub occurred_at: SystemTime,
    pub host_id: Option<HostId>,
    pub rule_id: Option<RuleId>,
    pub runtime_instance_id: Option<RuntimeInstanceId>,
    pub provider_target_id: Option<ProviderTargetId>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RuntimeEventLevel {
    Info,
    Notice,
    Warning,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RuntimeEventKind {
    SshStartRequested,
    SshStartSucceeded,
    SshStartFailed,
    RuntimeHealthOk,
    RuntimeObserved,
    RuntimeHealthWarning,
    RuntimeRecovered,
}

impl RuntimeEvent {
    pub fn new(
        kind: RuntimeEventKind,
        level: RuntimeEventLevel,
        summary: impl Into<String>,
        occurred_at: SystemTime,
    ) -> Self {
        Self {
            id: runtime_event_id(&kind, occurred_at),
            level,
            kind,
            summary: summary.into(),
            detail: None,
            occurred_at,
            host_id: None,
            rule_id: None,
            runtime_instance_id: None,
            provider_target_id: None,
        }
    }

    pub fn with_detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }

    pub fn with_runtime_context(mut self, runtime: &RuntimeInstance) -> Self {
        self.host_id = Some(runtime.host_id.clone());
        self.rule_id = Some(runtime.rule_id.clone());
        self.runtime_instance_id = Some(runtime.id.clone());
        self.provider_target_id = Some(runtime.provider_target_id.clone());
        self
    }

    pub fn with_rule_context(
        mut self,
        host_id: HostId,
        rule_id: RuleId,
        provider_target_id: ProviderTargetId,
        runtime_instance_id: RuntimeInstanceId,
    ) -> Self {
        self.host_id = Some(host_id);
        self.rule_id = Some(rule_id);
        self.runtime_instance_id = Some(runtime_instance_id);
        self.provider_target_id = Some(provider_target_id);
        self
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderProcessRecord {
    pub runtime_instance_id: RuntimeInstanceId,
    pub provider_kind: ProviderProcessKind,
    pub pid: u32,
    pub command_summary: String,
    pub target_label: String,
    pub started_at: Option<SystemTime>,
    pub last_observed_at: SystemTime,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalTunnelHealth {
    pub healthy: bool,
    pub checked_bindings: Vec<LocalTunnelBindingHealth>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalTunnelBindingHealth {
    pub local_port: u16,
    pub healthy: bool,
    pub detail: Option<String>,
}

pub trait LocalTunnelHealthChecker {
    fn check(&self, runtime: &RuntimeInstance) -> LocalTunnelHealth;
}

#[derive(Clone, Copy, Debug)]
pub struct TcpLocalTunnelHealthChecker {
    pub timeout: Duration,
}

impl Default for TcpLocalTunnelHealthChecker {
    fn default() -> Self {
        Self {
            timeout: Duration::from_millis(250),
        }
    }
}

impl LocalTunnelHealthChecker for TcpLocalTunnelHealthChecker {
    fn check(&self, runtime: &RuntimeInstance) -> LocalTunnelHealth {
        let checked_bindings = runtime
            .local_bindings
            .iter()
            .map(|binding| {
                let ipv4 = std::net::SocketAddr::from(([127, 0, 0, 1], binding.local_port));
                let ipv6 =
                    std::net::SocketAddr::from(([0, 0, 0, 0, 0, 0, 0, 1], binding.local_port));
                let healthy = std::net::TcpStream::connect_timeout(&ipv4, self.timeout)
                    .or_else(|_| std::net::TcpStream::connect_timeout(&ipv6, self.timeout))
                    .map(|stream| {
                        drop(stream);
                    })
                    .is_ok();

                LocalTunnelBindingHealth {
                    local_port: binding.local_port,
                    healthy,
                    detail: (!healthy).then(|| {
                        format!(
                            "loopback tcp connect failed for port {}",
                            binding.local_port
                        )
                    }),
                }
            })
            .collect::<Vec<_>>();

        let healthy =
            !checked_bindings.is_empty() && checked_bindings.iter().all(|binding| binding.healthy);

        LocalTunnelHealth {
            healthy,
            checked_bindings,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderProcessKind {
    OpenSsh,
}

impl RuntimeInstance {
    pub fn new(
        id: RuntimeInstanceId,
        rule_id: RuleId,
        host_id: HostId,
        provider_target_id: ProviderTargetId,
        local_bindings: Vec<LocalPortBinding>,
    ) -> Self {
        Self {
            id,
            rule_id,
            host_id,
            provider_target_id,
            local_bindings,
            status: RuntimeStatus::Starting,
            latency_ms: None,
            uptime_seconds: None,
            failure_count_today: 0,
            started_at: None,
            last_error: None,
        }
    }

    pub fn mark_connected(&mut self, started_at: SystemTime) {
        self.status = RuntimeStatus::Connected;
        self.started_at = Some(started_at);
        self.last_error = None;
    }

    pub fn mark_reconnecting(&mut self, reason: impl Into<String>) {
        self.status = RuntimeStatus::Reconnecting;
        self.failure_count_today += 1;
        self.last_error = Some(RuntimeErrorInfo::new(
            RuntimeErrorCode::KeepAliveTimeout,
            reason,
        ));
    }

    pub fn mark_error(&mut self, error: RuntimeErrorInfo) {
        self.status = RuntimeStatus::Error;
        self.failure_count_today += 1;
        self.last_error = Some(error);
    }

    pub fn stop(self, stopped_at: SystemTime) -> RecoveryItem {
        RecoveryItem {
            rule_id: self.rule_id,
            host_id: self.host_id,
            provider_target_id: self.provider_target_id,
            last_local_bindings: self.local_bindings,
            last_seen_status: self.status,
            recoverable_since: stopped_at,
        }
    }

    pub fn apply_local_port_override(
        &mut self,
        original_port: u16,
        effective_port: u16,
        reason: OverrideReason,
    ) -> Result<LocalPortOverride, RuntimeTransitionError> {
        let binding = self
            .local_bindings
            .iter_mut()
            .find(|binding| binding.local_port == original_port)
            .ok_or(RuntimeTransitionError::BindingNotFound { original_port })?;

        binding.local_port = effective_port;
        binding.temporary_override = true;

        Ok(LocalPortOverride {
            runtime_instance_id: self.id.clone(),
            original_port,
            effective_port,
            reason,
            persisted: false,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RuntimeStatus {
    Configured,
    Starting,
    Connected,
    Reconnecting,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecoveryItem {
    pub rule_id: RuleId,
    pub host_id: HostId,
    pub provider_target_id: ProviderTargetId,
    pub last_local_bindings: Vec<LocalPortBinding>,
    pub last_seen_status: RuntimeStatus,
    pub recoverable_since: SystemTime,
}

impl RecoveryItem {
    pub fn recover(self, runtime_instance_id: RuntimeInstanceId) -> RuntimeInstance {
        RuntimeInstance::new(
            runtime_instance_id,
            self.rule_id,
            self.host_id,
            self.provider_target_id,
            self.last_local_bindings,
        )
    }

    pub fn clear(self, cleared_at: SystemTime) -> ClearedRecoveryItem {
        ClearedRecoveryItem {
            rule_id: self.rule_id,
            host_id: self.host_id,
            provider_target_id: self.provider_target_id,
            cleared_at,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClearedRecoveryItem {
    pub rule_id: RuleId,
    pub host_id: HostId,
    pub provider_target_id: ProviderTargetId,
    pub cleared_at: SystemTime,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalPortBinding {
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
    pub temporary_override: bool,
}

impl LocalPortBinding {
    pub fn new(local_port: u16, remote_host: impl Into<String>, remote_port: u16) -> Self {
        Self {
            local_port,
            remote_host: remote_host.into(),
            remote_port,
            temporary_override: false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalPortOverride {
    pub runtime_instance_id: RuntimeInstanceId,
    pub original_port: u16,
    pub effective_port: u16,
    pub reason: OverrideReason,
    pub persisted: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum OverrideReason {
    Conflict { usage: Box<PortUsage> },
    Manual,
    AutoIncrement,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeErrorInfo {
    pub code: RuntimeErrorCode,
    pub summary: String,
    pub detail: Option<String>,
}

impl RuntimeErrorInfo {
    pub fn new(code: RuntimeErrorCode, summary: impl Into<String>) -> Self {
        Self {
            code,
            summary: summary.into(),
            detail: None,
        }
    }

    pub fn with_detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RuntimeErrorCode {
    KeepAliveTimeout,
    ProviderExited,
    PortConflict,
    TunnelHealthCheckFailed,
    InvalidConfiguration,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Eq, Error)]
pub enum RuntimeTransitionError {
    #[error("local binding for original port {original_port} was not found")]
    BindingNotFound { original_port: u16 },
}

pub fn uptime_seconds_since(started_at: SystemTime, now: SystemTime) -> Option<u64> {
    now.duration_since(started_at)
        .ok()
        .map(|duration| duration.as_secs())
}

fn runtime_event_id(kind: &RuntimeEventKind, occurred_at: SystemTime) -> String {
    let millis = occurred_at
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0);
    format!("{kind:?}-{millis}").to_ascii_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn instance() -> RuntimeInstance {
        RuntimeInstance::new(
            RuntimeInstanceId::from("rt-1"),
            RuleId::from("rule-1"),
            HostId::from("host-1"),
            ProviderTargetId::from("target-1"),
            vec![LocalPortBinding::new(3000, "127.0.0.1", 3000)],
        )
    }

    #[test]
    fn new_runtime_instance_starts_in_starting_state() {
        let runtime = instance();

        assert_eq!(runtime.status, RuntimeStatus::Starting);
        assert_eq!(runtime.failure_count_today, 0);
        assert!(runtime.started_at.is_none());
    }

    #[test]
    fn connected_runtime_clears_last_error() {
        let mut runtime = instance();
        runtime.mark_error(RuntimeErrorInfo::new(
            RuntimeErrorCode::ProviderExited,
            "provider exited",
        ));

        let started_at = SystemTime::UNIX_EPOCH;
        runtime.mark_connected(started_at);

        assert_eq!(runtime.status, RuntimeStatus::Connected);
        assert_eq!(runtime.started_at, Some(started_at));
        assert!(runtime.last_error.is_none());
    }

    #[test]
    fn reconnecting_records_keepalive_error_and_failure_count() {
        let mut runtime = instance();

        runtime.mark_reconnecting("keepalive timed out");

        assert_eq!(runtime.status, RuntimeStatus::Reconnecting);
        assert_eq!(runtime.failure_count_today, 1);
        assert_eq!(
            runtime.last_error.as_ref().map(|error| &error.code),
            Some(&RuntimeErrorCode::KeepAliveTimeout)
        );
    }

    #[test]
    fn stop_turns_runtime_instance_into_recovery_item() {
        let mut runtime = instance();
        runtime.mark_connected(SystemTime::UNIX_EPOCH);

        let recovery = runtime.stop(SystemTime::UNIX_EPOCH);

        assert_eq!(recovery.rule_id, RuleId::from("rule-1"));
        assert_eq!(recovery.last_seen_status, RuntimeStatus::Connected);
        assert_eq!(recovery.last_local_bindings.len(), 1);
    }

    #[test]
    fn recovery_item_can_start_new_runtime_instance() {
        let recovery = instance().stop(SystemTime::UNIX_EPOCH);

        let runtime = recovery.recover(RuntimeInstanceId::from("rt-2"));

        assert_eq!(runtime.id, RuntimeInstanceId::from("rt-2"));
        assert_eq!(runtime.status, RuntimeStatus::Starting);
        assert_eq!(runtime.local_bindings[0].local_port, 3000);
    }

    #[test]
    fn local_port_override_is_session_scoped_by_default() {
        let mut runtime = instance();

        let override_record = runtime
            .apply_local_port_override(3000, 3001, OverrideReason::AutoIncrement)
            .expect("binding exists");

        assert_eq!(override_record.original_port, 3000);
        assert_eq!(override_record.effective_port, 3001);
        assert!(!override_record.persisted);
        assert_eq!(runtime.local_bindings[0].local_port, 3001);
        assert!(runtime.local_bindings[0].temporary_override);
    }
}
