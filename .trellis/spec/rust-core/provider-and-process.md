# Provider And Process

First provider scope:

- system OpenSSH for SSH forwarding
- local Tailscale status/CLI integration when available

First stage should not implement a custom SSH protocol stack.

Rust core owns:

- command construction
- process lifecycle tracking
- status observation
- reconnect/recovery decisions
- error attribution

Swift shell owns:

- permission prompts
- user-visible confirmation flows
- system integration surfaces

Provider abstractions must describe what users care about: which target/channel a rule runs through, not provider internals.

## System OpenSSH Provider

### 1. Scope / Trigger

- Trigger: RelayDock needs its first runnable provider path before Tailscale or custom protocol work.
- Provider: system OpenSSH via the local `ssh` executable.
- Owner: Rust core owns command construction, process lifecycle tracking, status observation, and structured diagnostics.

### 2. Signatures

Rust entrypoints:

```rust
build_openssh_launch_plan(host, rule, provider_target, runtime_instance_id)
OpenSshProvider::system().start_rule(host, rule, provider_target, runtime_instance_id)
handle.observe_status(observed_at)
handle.stop(stopped_at)
ProviderProcessController::is_running(pid)
ProviderProcessController::terminate_pid(pid)
runtime_from_recovery_item(recovery_item, runtime_instance_id)
```

### 3. Contracts

- Only `ProviderTargetType::Ssh` is accepted by the OpenSSH provider.
- `Rule.host_id`, `Rule.provider_target_id`, and `ProviderTarget.host_id` must all match the launch context.
- Command construction must use structured `Rule` port mappings, not pasted shell strings.
- OpenSSH command uses `ssh -N -T`, `ExitOnForwardFailure=yes`, and keepalive options.
- Each `Rule.main_port` and `Rule.secondary_ports` becomes a separate `-L local:remote_host:remote_port` argument.
- Provider target labels remain user-oriented strings such as `SSH · 家庭宽带`; Rust should carry the label but not expand it into UI prose.
- The JSON sidecar cannot retain `Child` handles across invocations. Cross-invocation observation and stop must go through persisted pid metadata plus `ProviderProcessController`.
- Pid-backed control is a transitional MVP: terminate only the recorded provider pid, do not claim full process-tree supervision until a daemon or launch-agent design exists.

### 4. Validation & Error Matrix

- Non-SSH target -> `unsupported_provider_target`.
- Host/rule/provider target mismatch -> `invalid_provider_target`.
- Process spawn failure -> `process_start_failed` with command detail and recovery hint.
- Process observation failure -> `process_status_failed`.
- Process termination failure -> `process_termination_failed`.
- Process exit -> `process_exited`, mapped to `RuntimeErrorCode::ProviderExited`.
- Missing persisted pid metadata for a runtime -> bridge-level `runtime_lifecycle_failed`, not a provider error.

### 5. Good/Base/Bad Cases

- Good: a structured rule with one main port and one secondary port builds two `-L` arguments.
- Base: a running child process marks the runtime instance `Connected` when observed.
- Base: a recorded pid that is no longer running moves the runtime to recovery during snapshot load.
- Bad: storing an imported raw `ssh -L ...` command as the source of truth for starting a rule.

### 6. Tests Required

- Command construction from structured rule and SSH provider target.
- Rejection of non-SSH provider target.
- Mock process launcher verifies process start without launching real `ssh`.
- Running observation marks runtime connected.
- Exited observation emits structured diagnostic and runtime error.
- Stop terminates process and produces a `RecoveryItem`.
- Mock pid controller verifies pid observation and pid termination without launching or killing real processes.
- Recovery hook creates a new starting runtime from `RecoveryItem`.

### 7. Wrong vs Correct

Wrong:

```rust
Command::new("sh").arg("-c").arg(user_pasted_ssh_command).spawn()?;
```

Correct:

```rust
let plan = build_openssh_launch_plan(host, rule, provider_target, runtime_id)?;
launcher.launch(&plan.command)?;
```
