use crate::domain::{Host, ProviderTarget, ProviderTargetType, Rule, RuntimeInstanceId};
use crate::runtime::{
    LocalPortBinding, RecoveryItem, RuntimeErrorCode, RuntimeErrorInfo, RuntimeInstance,
};
use serde::{Deserialize, Serialize};
use std::fmt;
use std::process::{Child, Command, Stdio};
use std::time::SystemTime;
use thiserror::Error;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpenSshCommand {
    pub program: String,
    pub args: Vec<String>,
}

impl OpenSshCommand {
    pub fn display_command(&self) -> String {
        std::iter::once(self.program.as_str())
            .chain(self.args.iter().map(String::as_str))
            .collect::<Vec<_>>()
            .join(" ")
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpenSshLaunchPlan {
    pub command: OpenSshCommand,
    pub runtime_instance: RuntimeInstance,
    pub target_label: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderProcessExit {
    pub code: Option<i32>,
    pub success: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProviderProcessStatus {
    Running { pid: Option<u32> },
    Exited { exit: ProviderProcessExit },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderObservation {
    pub status: ProviderProcessStatus,
    pub runtime_instance: RuntimeInstance,
    pub diagnostic: Option<ProviderDiagnostic>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderDiagnostic {
    pub code: ProviderDiagnosticCode,
    pub summary: String,
    pub detail: Option<String>,
    pub rule_id: Option<String>,
    pub provider_target_id: Option<String>,
    pub runtime_instance_id: Option<String>,
    pub suggested_recovery: Option<String>,
}

impl ProviderDiagnostic {
    fn new(code: ProviderDiagnosticCode, summary: impl Into<String>) -> Self {
        Self {
            code,
            summary: summary.into(),
            detail: None,
            rule_id: None,
            provider_target_id: None,
            runtime_instance_id: None,
            suggested_recovery: None,
        }
    }

    fn with_detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }

    fn with_rule_context(mut self, rule: &Rule, provider_target: &ProviderTarget) -> Self {
        self.rule_id = Some(rule.id.to_string());
        self.provider_target_id = Some(provider_target.id.to_string());
        self
    }

    fn with_runtime(mut self, runtime: &RuntimeInstance) -> Self {
        self.runtime_instance_id = Some(runtime.id.to_string());
        self
    }

    fn with_recovery(mut self, suggested_recovery: impl Into<String>) -> Self {
        self.suggested_recovery = Some(suggested_recovery.into());
        self
    }
}

impl fmt::Display for ProviderDiagnostic {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.summary)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderDiagnosticCode {
    InvalidProviderTarget,
    UnsupportedProviderTarget,
    ProcessStartFailed,
    ProcessStatusFailed,
    ProcessTerminationFailed,
    ProcessExited,
}

#[derive(Clone, Debug, PartialEq, Eq, Error)]
#[error("{diagnostic}")]
pub struct ProviderError {
    pub diagnostic: Box<ProviderDiagnostic>,
}

impl ProviderError {
    pub fn diagnostic(&self) -> &ProviderDiagnostic {
        &self.diagnostic
    }

    fn invalid_target(summary: impl Into<String>) -> Self {
        Self::new(ProviderDiagnostic::new(
            ProviderDiagnosticCode::InvalidProviderTarget,
            summary,
        ))
    }

    fn new(diagnostic: ProviderDiagnostic) -> Self {
        Self {
            diagnostic: Box::new(diagnostic),
        }
    }

    fn process_start_failed(command: &OpenSshCommand, detail: impl Into<String>) -> Self {
        Self::new(
            ProviderDiagnostic::new(
                ProviderDiagnosticCode::ProcessStartFailed,
                "OpenSSH process could not be started",
            )
            .with_detail(format!("{}: {}", command.display_command(), detail.into()))
            .with_recovery(
                "Check that system ssh is installed and the provider target is reachable.",
            ),
        )
    }

    fn process_status_failed(detail: impl Into<String>) -> Self {
        Self::new(
            ProviderDiagnostic::new(
                ProviderDiagnosticCode::ProcessStatusFailed,
                "OpenSSH process status could not be observed",
            )
            .with_detail(detail),
        )
    }

    fn process_termination_failed(detail: impl Into<String>) -> Self {
        Self::new(
            ProviderDiagnostic::new(
                ProviderDiagnosticCode::ProcessTerminationFailed,
                "OpenSSH process could not be stopped",
            )
            .with_detail(detail),
        )
    }

    fn with_rule_context(mut self, rule: &Rule, provider_target: &ProviderTarget) -> Self {
        self.diagnostic = Box::new(self.diagnostic.with_rule_context(rule, provider_target));
        self
    }

    fn with_runtime(mut self, runtime: &RuntimeInstance) -> Self {
        self.diagnostic = Box::new(self.diagnostic.with_runtime(runtime));
        self
    }
}

pub trait ProviderProcess {
    fn process_id(&self) -> Option<u32>;
    fn try_wait(&mut self) -> Result<Option<ProviderProcessExit>, ProviderError>;
    fn terminate(&mut self) -> Result<(), ProviderError>;
}

pub trait ProviderProcessLauncher {
    type Process: ProviderProcess;

    fn launch(&self, command: &OpenSshCommand) -> Result<Self::Process, ProviderError>;
}

pub trait ProviderProcessController {
    fn is_running(&self, pid: u32) -> Result<bool, ProviderError>;
    fn terminate_pid(&self, pid: u32) -> Result<(), ProviderError>;
}

#[derive(Clone, Copy, Debug, Default)]
pub struct SystemProcessLauncher;

#[derive(Clone, Copy, Debug, Default)]
pub struct SystemPidProcessController;

impl ProviderProcessController for SystemPidProcessController {
    fn is_running(&self, pid: u32) -> Result<bool, ProviderError> {
        let status = Command::new("kill")
            .arg("-0")
            .arg(pid.to_string())
            .status()
            .map_err(|error| ProviderError::process_status_failed(error.to_string()))?;

        Ok(status.success())
    }

    fn terminate_pid(&self, pid: u32) -> Result<(), ProviderError> {
        let status = Command::new("kill")
            .arg("-TERM")
            .arg(pid.to_string())
            .status()
            .map_err(|error| ProviderError::process_termination_failed(error.to_string()))?;

        if status.success() {
            Ok(())
        } else {
            Err(ProviderError::process_termination_failed(format!(
                "kill -TERM {pid} exited with status {status}"
            )))
        }
    }
}

impl ProviderProcessLauncher for SystemProcessLauncher {
    type Process = SystemProviderProcess;

    fn launch(&self, command: &OpenSshCommand) -> Result<Self::Process, ProviderError> {
        let child = Command::new(&command.program)
            .args(&command.args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|error| ProviderError::process_start_failed(command, error.to_string()))?;

        Ok(SystemProviderProcess { child })
    }
}

pub struct SystemProviderProcess {
    child: Child,
}

impl ProviderProcess for SystemProviderProcess {
    fn process_id(&self) -> Option<u32> {
        Some(self.child.id())
    }

    fn try_wait(&mut self) -> Result<Option<ProviderProcessExit>, ProviderError> {
        self.child
            .try_wait()
            .map(|exit_status| {
                exit_status.map(|status| ProviderProcessExit {
                    code: status.code(),
                    success: status.success(),
                })
            })
            .map_err(|error| ProviderError::process_status_failed(error.to_string()))
    }

    fn terminate(&mut self) -> Result<(), ProviderError> {
        self.child
            .kill()
            .map_err(|error| ProviderError::process_termination_failed(error.to_string()))?;
        let _ = self.child.wait();
        Ok(())
    }
}

#[derive(Clone, Debug)]
pub struct OpenSshProvider<L = SystemProcessLauncher> {
    launcher: L,
}

impl OpenSshProvider<SystemProcessLauncher> {
    pub fn system() -> Self {
        Self {
            launcher: SystemProcessLauncher,
        }
    }
}

impl<L> OpenSshProvider<L>
where
    L: ProviderProcessLauncher,
{
    pub fn new(launcher: L) -> Self {
        Self { launcher }
    }

    pub fn build_launch_plan(
        &self,
        host: &Host,
        rule: &Rule,
        provider_target: &ProviderTarget,
        runtime_instance_id: RuntimeInstanceId,
    ) -> Result<OpenSshLaunchPlan, ProviderError> {
        build_openssh_launch_plan(host, rule, provider_target, runtime_instance_id)
    }

    pub fn start_rule(
        &self,
        host: &Host,
        rule: &Rule,
        provider_target: &ProviderTarget,
        runtime_instance_id: RuntimeInstanceId,
    ) -> Result<SshRuntimeHandle<L::Process>, ProviderError> {
        let plan = self.build_launch_plan(host, rule, provider_target, runtime_instance_id)?;
        self.start_launch_plan(rule, provider_target, plan)
    }

    pub fn start_rule_with_bindings(
        &self,
        host: &Host,
        rule: &Rule,
        provider_target: &ProviderTarget,
        runtime_instance_id: RuntimeInstanceId,
        local_bindings: Vec<LocalPortBinding>,
    ) -> Result<SshRuntimeHandle<L::Process>, ProviderError> {
        let plan = build_openssh_launch_plan_with_bindings(
            host,
            rule,
            provider_target,
            runtime_instance_id,
            local_bindings,
        )?;
        self.start_launch_plan(rule, provider_target, plan)
    }

    fn start_launch_plan(
        &self,
        rule: &Rule,
        provider_target: &ProviderTarget,
        plan: OpenSshLaunchPlan,
    ) -> Result<SshRuntimeHandle<L::Process>, ProviderError> {
        let process = self.launcher.launch(&plan.command).map_err(|error| {
            error
                .with_rule_context(rule, provider_target)
                .with_runtime(&plan.runtime_instance)
        })?;

        Ok(SshRuntimeHandle {
            runtime_instance: plan.runtime_instance,
            process,
            command: plan.command,
            target_label: plan.target_label,
        })
    }
}

pub struct SshRuntimeHandle<P>
where
    P: ProviderProcess,
{
    runtime_instance: RuntimeInstance,
    process: P,
    command: OpenSshCommand,
    target_label: String,
}

impl<P> SshRuntimeHandle<P>
where
    P: ProviderProcess,
{
    pub fn runtime_instance(&self) -> &RuntimeInstance {
        &self.runtime_instance
    }

    pub fn command(&self) -> &OpenSshCommand {
        &self.command
    }

    pub fn target_label(&self) -> &str {
        &self.target_label
    }

    pub fn observe_status(
        &mut self,
        observed_at: SystemTime,
    ) -> Result<ProviderObservation, ProviderError> {
        match self
            .process
            .try_wait()
            .map_err(|error| error.with_runtime(&self.runtime_instance))?
        {
            None => {
                self.runtime_instance.mark_connected(observed_at);
                Ok(ProviderObservation {
                    status: ProviderProcessStatus::Running {
                        pid: self.process.process_id(),
                    },
                    runtime_instance: self.runtime_instance.clone(),
                    diagnostic: None,
                })
            }
            Some(exit) => {
                let diagnostic = ProviderDiagnostic::new(
                    ProviderDiagnosticCode::ProcessExited,
                    "OpenSSH process exited",
                )
                .with_detail(format!(
                    "exit_code={:?}, success={}",
                    exit.code, exit.success
                ))
                .with_runtime(&self.runtime_instance)
                .with_recovery("Move the runtime instance to recovery and offer retry.");
                self.runtime_instance.mark_error(
                    RuntimeErrorInfo::new(
                        RuntimeErrorCode::ProviderExited,
                        diagnostic.summary.clone(),
                    )
                    .with_detail(diagnostic.detail.clone().unwrap_or_default()),
                );

                Ok(ProviderObservation {
                    status: ProviderProcessStatus::Exited { exit },
                    runtime_instance: self.runtime_instance.clone(),
                    diagnostic: Some(diagnostic),
                })
            }
        }
    }

    pub fn stop(mut self, stopped_at: SystemTime) -> Result<RecoveryItem, ProviderError> {
        self.process
            .terminate()
            .map_err(|error| error.with_runtime(&self.runtime_instance))?;
        Ok(self.runtime_instance.stop(stopped_at))
    }
}

pub fn build_openssh_launch_plan(
    host: &Host,
    rule: &Rule,
    provider_target: &ProviderTarget,
    runtime_instance_id: RuntimeInstanceId,
) -> Result<OpenSshLaunchPlan, ProviderError> {
    build_openssh_launch_plan_with_bindings(
        host,
        rule,
        provider_target,
        runtime_instance_id,
        local_bindings_for_rule(rule),
    )
}

pub fn build_openssh_launch_plan_with_bindings(
    host: &Host,
    rule: &Rule,
    provider_target: &ProviderTarget,
    runtime_instance_id: RuntimeInstanceId,
    local_bindings: Vec<LocalPortBinding>,
) -> Result<OpenSshLaunchPlan, ProviderError> {
    validate_ssh_launch_inputs(host, rule, provider_target)?;

    let mut args = vec![
        "-N".to_string(),
        "-T".to_string(),
        "-o".to_string(),
        "ExitOnForwardFailure=yes".to_string(),
        "-o".to_string(),
        "ServerAliveInterval=15".to_string(),
        "-o".to_string(),
        "ServerAliveCountMax=2".to_string(),
    ];

    if let Some(target_port) = provider_target.target_port {
        args.push("-p".to_string());
        args.push(target_port.to_string());
    }

    for binding in &local_bindings {
        args.push("-L".to_string());
        args.push(format!(
            "{}:{}:{}",
            binding.local_port, binding.remote_host, binding.remote_port
        ));
    }

    args.push(destination(
        host.user.as_deref(),
        &provider_target.target_address,
    ));

    Ok(OpenSshLaunchPlan {
        command: OpenSshCommand {
            program: "ssh".to_string(),
            args,
        },
        runtime_instance: RuntimeInstance::new(
            runtime_instance_id,
            rule.id.clone(),
            rule.host_id.clone(),
            provider_target.id.clone(),
            local_bindings,
        ),
        target_label: provider_target.label.clone(),
    })
}

pub fn runtime_from_recovery_item(
    recovery_item: RecoveryItem,
    runtime_instance_id: RuntimeInstanceId,
) -> RuntimeInstance {
    recovery_item.recover(runtime_instance_id)
}

fn validate_ssh_launch_inputs(
    host: &Host,
    rule: &Rule,
    provider_target: &ProviderTarget,
) -> Result<(), ProviderError> {
    if provider_target.target_type != ProviderTargetType::Ssh {
        return Err(ProviderError::new(
            ProviderDiagnostic::new(
                ProviderDiagnosticCode::UnsupportedProviderTarget,
                "provider target is not SSH",
            )
            .with_rule_context(rule, provider_target),
        ));
    }

    if rule.host_id != host.id {
        return Err(
            ProviderError::invalid_target("rule host does not match launch host")
                .with_rule_context(rule, provider_target),
        );
    }

    if provider_target.host_id != host.id {
        return Err(ProviderError::invalid_target(
            "provider target host does not match launch host",
        )
        .with_rule_context(rule, provider_target));
    }

    if rule.provider_target_id != provider_target.id {
        return Err(ProviderError::invalid_target(
            "rule provider target does not match launch provider target",
        )
        .with_rule_context(rule, provider_target));
    }

    Ok(())
}

fn local_bindings_for_rule(rule: &Rule) -> Vec<LocalPortBinding> {
    std::iter::once(&rule.main_port)
        .chain(rule.secondary_ports.iter())
        .map(|mapping| {
            LocalPortBinding::new(
                mapping.local_port,
                mapping.remote_host.clone(),
                mapping.remote_port,
            )
        })
        .collect()
}

fn destination(user: Option<&str>, target_address: &str) -> String {
    match user {
        Some(user) if !user.is_empty() => format!("{user}@{target_address}"),
        _ => target_address.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{
        HostId, HostStatusHint, LocalAlias, Metadata, OsFamily, PortMapping, ProviderTargetId,
        RuleId,
    };
    use std::cell::RefCell;
    use std::rc::Rc;
    use std::time::UNIX_EPOCH;

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
    struct MockProcess {
        pid: Option<u32>,
        exit: Option<ProviderProcessExit>,
        terminated: Rc<RefCell<bool>>,
    }

    impl ProviderProcess for MockProcess {
        fn process_id(&self) -> Option<u32> {
            self.pid
        }

        fn try_wait(&mut self) -> Result<Option<ProviderProcessExit>, ProviderError> {
            Ok(self.exit.clone())
        }

        fn terminate(&mut self) -> Result<(), ProviderError> {
            *self.terminated.borrow_mut() = true;
            Ok(())
        }
    }

    #[derive(Clone, Debug)]
    struct MockPidController {
        running: bool,
        terminated: Rc<RefCell<Vec<u32>>>,
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

    fn host() -> Host {
        Host {
            id: HostId::from("host-1"),
            name: "Mac mini".to_string(),
            address: "192.168.1.5".to_string(),
            port: Some(22),
            user: Some("admin".to_string()),
            tags: vec!["home".to_string()],
            os_family: OsFamily::MacOS,
            os_distro: None,
            status_hint: HostStatusHint::Unknown,
            provider_targets: vec![ssh_target()],
        }
    }

    fn ssh_target() -> ProviderTarget {
        ProviderTarget {
            id: ProviderTargetId::from("target-1"),
            host_id: HostId::from("host-1"),
            target_type: ProviderTargetType::Ssh,
            label: "SSH · 家庭宽带".to_string(),
            target_address: "192.168.1.5".to_string(),
            target_port: Some(2222),
            auth_ref: Some("keychain://ssh/home".to_string()),
            meta: Metadata::new(),
        }
    }

    fn rule() -> Rule {
        let rule_id = RuleId::from("rule-1");
        Rule {
            id: rule_id.clone(),
            host_id: HostId::from("host-1"),
            name: "Web".to_string(),
            alias: Some(LocalAlias {
                hostname: "web.home.localhost".to_string(),
                rule_id: rule_id.clone(),
                generated: true,
                editable: true,
            }),
            provider_target_id: ProviderTargetId::from("target-1"),
            remote_host: "127.0.0.1".to_string(),
            main_port: PortMapping::new(3000, "127.0.0.1", 3000),
            secondary_ports: vec![PortMapping::new(5432, "127.0.0.1", 5432)],
            kind: Some("web".to_string()),
            icon_hint: None,
            tags: Vec::new(),
            notes: None,
        }
    }

    #[test]
    fn builds_openssh_command_from_structured_rule() {
        let plan = build_openssh_launch_plan(
            &host(),
            &rule(),
            &ssh_target(),
            RuntimeInstanceId::from("runtime-1"),
        )
        .expect("plan builds");

        assert_eq!(plan.command.program, "ssh");
        assert_eq!(
            plan.command.args,
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
                "2222",
                "-L",
                "3000:127.0.0.1:3000",
                "-L",
                "5432:127.0.0.1:5432",
                "admin@192.168.1.5",
            ]
        );
        assert_eq!(plan.runtime_instance.local_bindings.len(), 2);
        assert_eq!(plan.target_label, "SSH · 家庭宽带");
    }

    #[test]
    fn rejects_non_ssh_provider_target() {
        let mut target = ssh_target();
        target.target_type = ProviderTargetType::Tailscale;

        let error = build_openssh_launch_plan(
            &host(),
            &rule(),
            &target,
            RuntimeInstanceId::from("runtime-1"),
        )
        .expect_err("target is unsupported");

        assert_eq!(
            error.diagnostic.code,
            ProviderDiagnosticCode::UnsupportedProviderTarget
        );
    }

    #[test]
    fn start_rule_launches_process_and_keeps_runtime_starting() {
        let launched = Rc::new(RefCell::new(Vec::new()));
        let provider = OpenSshProvider::new(MockLauncher {
            launched: launched.clone(),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
                terminated: Rc::new(RefCell::new(false)),
            },
        });

        let handle = provider
            .start_rule(
                &host(),
                &rule(),
                &ssh_target(),
                RuntimeInstanceId::from("runtime-1"),
            )
            .expect("rule starts");

        assert_eq!(launched.borrow().len(), 1);
        assert_eq!(
            handle.runtime_instance().status,
            crate::runtime::RuntimeStatus::Starting
        );
        assert_eq!(handle.command().program, "ssh");
    }

    #[test]
    fn observing_running_process_marks_runtime_connected() {
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
                terminated: Rc::new(RefCell::new(false)),
            },
        });
        let mut handle = provider
            .start_rule(
                &host(),
                &rule(),
                &ssh_target(),
                RuntimeInstanceId::from("runtime-1"),
            )
            .expect("rule starts");

        let observation = handle.observe_status(UNIX_EPOCH).expect("status observes");

        assert_eq!(
            observation.status,
            ProviderProcessStatus::Running { pid: Some(4242) }
        );
        assert_eq!(
            observation.runtime_instance.status,
            crate::runtime::RuntimeStatus::Connected
        );
        assert!(observation.diagnostic.is_none());
    }

    #[test]
    fn observing_exited_process_maps_structured_diagnostic() {
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: Some(4242),
                exit: Some(ProviderProcessExit {
                    code: Some(255),
                    success: false,
                }),
                terminated: Rc::new(RefCell::new(false)),
            },
        });
        let mut handle = provider
            .start_rule(
                &host(),
                &rule(),
                &ssh_target(),
                RuntimeInstanceId::from("runtime-1"),
            )
            .expect("rule starts");

        let observation = handle.observe_status(UNIX_EPOCH).expect("status observes");

        assert!(matches!(
            observation.status,
            ProviderProcessStatus::Exited {
                exit: ProviderProcessExit {
                    code: Some(255),
                    success: false
                }
            }
        ));
        assert_eq!(
            observation
                .diagnostic
                .as_ref()
                .map(|diagnostic| &diagnostic.code),
            Some(&ProviderDiagnosticCode::ProcessExited)
        );
        assert_eq!(
            observation.runtime_instance.status,
            crate::runtime::RuntimeStatus::Error
        );
        assert_eq!(
            observation
                .runtime_instance
                .last_error
                .as_ref()
                .map(|error| &error.code),
            Some(&RuntimeErrorCode::ProviderExited)
        );
    }

    #[test]
    fn stop_terminates_process_and_returns_recovery_item() {
        let terminated = Rc::new(RefCell::new(false));
        let provider = OpenSshProvider::new(MockLauncher {
            launched: Rc::new(RefCell::new(Vec::new())),
            next_process: MockProcess {
                pid: Some(4242),
                exit: None,
                terminated: terminated.clone(),
            },
        });
        let handle = provider
            .start_rule(
                &host(),
                &rule(),
                &ssh_target(),
                RuntimeInstanceId::from("runtime-1"),
            )
            .expect("rule starts");

        let recovery = handle.stop(UNIX_EPOCH).expect("runtime stops");

        assert!(*terminated.borrow());
        assert_eq!(recovery.rule_id, RuleId::from("rule-1"));
        assert_eq!(recovery.last_local_bindings.len(), 2);
    }

    #[test]
    fn recovery_hook_creates_starting_runtime_from_recovery_item() {
        let plan = build_openssh_launch_plan(
            &host(),
            &rule(),
            &ssh_target(),
            RuntimeInstanceId::from("runtime-1"),
        )
        .expect("plan builds");
        let recovery = plan.runtime_instance.stop(UNIX_EPOCH);

        let runtime = runtime_from_recovery_item(recovery, RuntimeInstanceId::from("runtime-2"));

        assert_eq!(runtime.id, RuntimeInstanceId::from("runtime-2"));
        assert_eq!(runtime.status, crate::runtime::RuntimeStatus::Starting);
        assert_eq!(runtime.local_bindings.len(), 2);
    }

    #[test]
    fn pid_controller_can_observe_and_terminate_mock_process() {
        let terminated = Rc::new(RefCell::new(Vec::new()));
        let controller = MockPidController {
            running: true,
            terminated: terminated.clone(),
        };

        assert!(controller.is_running(4242).expect("pid observes"));
        controller.terminate_pid(4242).expect("pid terminates");

        assert_eq!(*terminated.borrow(), vec![4242]);
    }
}
