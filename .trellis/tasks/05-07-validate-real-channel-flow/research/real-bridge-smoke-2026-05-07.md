# Real Bridge Smoke Evidence - 2026-05-07

## Scope

This smoke test used the compiled `target/debug/relaydock-bridge` directly with `RELAYDOCK_STORE_PATH` pointing at an isolated QA SQLite database:

```text
/tmp/relaydock-real-channel-1778135436.sqlite3
```

The test intentionally did not use `RELAYDOCK_VISUAL_QA_FIXTURE`, so responses came from the production bridge command path and SQLite-backed store.

## Commands And Evidence Files

- Empty registry load: `/tmp/relaydock-bridge-empty-registry.json`
- Empty run/recovery load: `/tmp/relaydock-bridge-empty-run.json`
- Save host: `/tmp/relaydock-bridge-save-host.json`
- Save rule: `/tmp/relaydock-bridge-save-rule.json`
- Run/recovery after save: `/tmp/relaydock-bridge-after-save-run.json`
- Start rule: `/tmp/relaydock-bridge-start-rule.json`
- Reload after start: `/tmp/relaydock-bridge-after-start-reload.json`
- Stop runtime after reload reconciliation: `/tmp/relaydock-bridge-stop-runtime.json`
- Reachable SSH target save host: `/tmp/relaydock-bridge-macminim4-save-host.json`
- Reachable SSH target save rule: `/tmp/relaydock-bridge-macminim4-save-rule.json`
- Reachable SSH target run/recovery after save: `/tmp/relaydock-bridge-macminim4-after-save-run.json`
- Reachable SSH target start rule: `/tmp/relaydock-bridge-macminim4-start-rule.json`
- Reachable SSH target reload after start: `/tmp/relaydock-bridge-macminim4-after-start-reload.json`
- Reachable SSH target stop runtime: `/tmp/relaydock-bridge-macminim4-stop-runtime.json`
- Reachable SSH target reload after stop: `/tmp/relaydock-bridge-macminim4-after-stop-reload.json`

## Observed Results

### Empty Store

- `load_registry_snapshot` returned `ok=true`, `hosts=[]`, and `selected_host_id=""`.
- `load_run_recovery_snapshot` returned `ok=true`, `hosts=[]`, `recoverable_count=0`, and message `没有运行或待恢复项目`.
- This confirms the isolated production bridge path does not seed demo rows for empty storage.

### Saved Real Host And Rule

Saved host:

- `id=host-local-ssh`
- `name=Localhost SSH QA`
- `endpoint=brink@127.0.0.1`
- one SSH provider target: `target-local-ssh`

Saved rule:

- `id=rule-local-http`
- `service_name=Local HTTP`
- `alias=local.qa.localhost`
- `provider_label=SSH · 本机 QA`
- `port_summary=38080`
- registry runtime state: `stopped`

`load_run_recovery_snapshot` after save projected the rule as a recoverable runtime candidate:

- `id=recovery-rule-local-http`
- `runtime_id=null`
- `recovery_id=recovery-rule-local-http`
- `state=recoverable`
- actions: `恢复`, `改本地端口`, `清除`

This confirms the saved registry data feeds run/recovery through the same SQLite-backed bridge store.

### Start/Reload/Stop Behavior

`start_rule` for `rule-local-http` returned `ok=true` and last action `已启动规则`:

- `runtime_id=runtime-rule-local-http`
- state: `connected`
- summary: `运行状态正常`
- action: `停止`

However, a reload immediately after start reconciled the pid away and returned the row to recoverable:

- `runtime_id=null`
- `recovery_id=recovery-rule-local-http`
- state: `recoverable`
- error code: `stopped_from_connected`
- error summary: `上次运行已断开，等待手动恢复`
- runtime snapshot table then had empty `instances` and `provider_processes`.
- recovery collection persisted one item for `rule-local-http`.

The environment check `nc -z 127.0.0.1 22` returned exit code `1`, so the local SSH provider target was not reachable. The observed behavior is consistent with OpenSSH spawning, then exiting quickly after the immediate status check.

After reload reconciliation, `stop_runtime_instance` for `runtime-rule-local-http` returned a structured bridge error:

- code: `runtime_lifecycle_failed`
- summary: `未找到要停止的运行实例`
- detail: `runtime_id=runtime-rule-local-http`
- suggested recovery: `重新读取运行状态；如果进程已经退出，可清除待恢复项。`

### Successful Reachable SSH Lifecycle

A second isolated store used an existing SSH config alias that supports non-interactive login:

```text
/tmp/relaydock-real-channel-macminim4-1778135941.sqlite3
```

Connectivity probe:

- `ssh -o BatchMode=yes -o ConnectTimeout=5 macminim4 true` returned exit code `0`.

Saved host/rule:

- host: `host-macminim4`
- provider target: `target-macminim4-ssh`
- rule: `rule-macminim4-ssh`
- local forward: `39022 -> 127.0.0.1:22`

Before start, run/recovery projected the saved rule as recoverable.

`start_rule` returned:

- `ok=true`
- last action: `已启动规则`
- `runtime_id=runtime-rule-macminim4-ssh`
- state: `connected`
- summary: `运行状态正常`

An intermediate SQLite runtime snapshot inspection during the smoke run showed
provider process metadata with pid `828` and command:

```text
ssh -N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=2 -p 22 -L 39022:127.0.0.1:22 iwhale@macminim4
```

Reload after start preserved the connected runtime row and reported telemetry `0m · - · 0次`.

`stop_runtime_instance` returned:

- `ok=true`
- last action: `已停止运行实例并加入恢复列表`
- `affected_runtime_id=runtime-rule-macminim4-ssh`
- summary: `存在可恢复的转发`

Reload after stop returned the row to recoverable with error code `stopped_from_connected`. A final `ps -p 828` showed no remaining process.

Note: the listed bridge JSON outputs preserve the user-visible runtime state,
last actions, and structured errors. They do not expose provider process
metadata. The final SQLite state after stop/reload also clears runtime process
metadata, so the pid/command detail above is a live intermediate observation
rather than a durable final-state artifact.

## Diagnostic Implications

This is exactly the kind of real evidence the Logs/Diagnostics page should be shaped around later:

- distinguish persisted configuration from runtime/process state
- show provider reachability/start lifecycle facts
- show that `start_rule` returned connected before a later reload moved the row to recovery
- expose pid reconciliation and recovery insertion as a first-class diagnostic event
- keep the structured bridge error for failed stop attempts after reconciliation

## Follow-Up Candidates

- Consider making `start_rule` observe for a short settle window or otherwise detect immediate OpenSSH exit before reporting `已启动规则`.
- Logs/Diagnostics should eventually show bridge command history and reconciliation events, not only derived snapshot summaries.
- The full reachable-target lifecycle now works, so the next diagnostics task should focus on what to display from command history, provider pid metadata, reconciliation, and recovery insertion.
