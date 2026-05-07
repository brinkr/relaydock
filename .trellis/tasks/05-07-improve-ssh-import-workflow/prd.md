# Improve SSH Command Import Workflow

## Goal

Make `导入 SSH` behave like a normal macOS import workflow: users can paste with keyboard or a visible paste button, see parse state immediately, and save imported `ssh -L` forwards to the correct host/target without first understanding RelayDock's internal host/target model.

## Problem

The current implementation is too host-local and too manual:

- The user can paste only through the TextEditor context menu in the observed app run; normal keyboard paste did not work reliably.
- The sheet continues to show `已解析 0 条本地转发` after text exists, which reads like a failed parse even before parsing is triggered.
- The only obvious path is: create/select a host first -> open `导入 SSH` on that host -> parse -> save rules to that host.
- Parsed destination hints such as `root@111.230.202.80` are not enough to move the import to an existing matching host elsewhere.
- If no host exists for the parsed destination, the UI does not offer to create one from the SSH command.

## Target Behavior

### Paste And Parse

- Text input must support normal macOS keyboard paste (`Command+V`) and not rely on right-click context menu paste.
- Add a visible `粘贴` action near the SSH command input. It should read plain text from the pasteboard into the command field.
- After command text changes:
  - Do not keep showing a stale `已解析 0 条本地转发` as if it were current.
  - Prefer automatic parsing with a short debounce if practical.
  - If automatic parsing is not practical in this pass, show an explicit `待解析` state and make `解析命令` visually primary enough to be obvious.
- Parsing the sample command below must produce one preview rule:

```text
ssh -fN -L 18317:127.0.0.1:18317 root@111.230.202.80
```

### Host And Target Assignment

- The import workflow should consider all registry hosts, not only the currently selected host.
- If a parsed destination matches an existing SSH provider target by `target_address` and `target_port`:
  - Select that target automatically.
  - Save imported rules under that target's host.
- If no matching target exists:
  - Offer to create a new host/provider target from the parsed destination hint.
  - Still allow the user to choose an existing host/target manually when they know the target should belong there.
- If the user entered the import flow from a specific host, use that host as a fallback/default only when there is no parsed destination match.
- Before saving, clearly show the final destination:
  - host name
  - provider target label
  - target address and port

### Persistence

- When creating a new host from an SSH command:
  - Use the parsed destination host/address as the host address.
  - Use parsed user when available.
  - Create one SSH provider target for the parsed destination.
  - Then save imported rules against that newly created host and target.
- Do not store the raw SSH command as source of truth.
- Do not store credentials, private keys, passwords, tokens, or other secrets.

## Requirements

- Keep Rust as the SSH syntax parser through existing `parse_ssh_command`.
- Keep Swift responsible for presentation state, host/target selection, pasteboard interaction, and save orchestration.
- Avoid introducing a new bridge command unless necessary; existing `save_registry_host` and `save_registry_rule` can be composed from Swift if that keeps the slice smaller.
- Preserve existing host-local `导入 SSH` entry point, but make it route through the improved assignment workflow.
- Preserve existing manual `新增规则` and `主机设置` flows.
- Use Chinese-first UI copy.

## Acceptance Criteria

- [x] The import sheet has a visible `粘贴` action and supports normal keyboard paste.
- [x] Typing or pasting an SSH command no longer leaves a misleading stale `已解析 0 条本地转发` state.
- [x] The sample `ssh -fN -L 18317:127.0.0.1:18317 root@111.230.202.80` parses into one preview row in the UI.
- [x] Existing matching host/target is automatically selected when its SSH target matches parsed destination host and port.
- [x] When no matching host/target exists, the user can create a new host/provider target from the parsed command and save the imported rules there.
- [x] The user can manually choose an existing host/target before saving.
- [x] Saved rules appear under the chosen/new host after bridge round-trips.
- [x] `swift build` passes.
- [x] Relevant Rust parser tests still pass.
- [x] `git diff --check` passes.
- [x] If practical, visual QA or an app screenshot confirms the sheet state is understandable.

## Completion Notes

- 2026-05-07: Implemented global SSH import assignment in Swift. The host-local entry point still opens from the current host, but parsed SSH destinations are matched against all SSH provider targets first.
- 2026-05-07: If a parsed destination matches an existing host but that host lacks an SSH provider target, the import flow offers to add an SSH target to that existing host instead of creating a duplicate host.
- 2026-05-07: If no matching host exists, the default save target becomes `从解析目标新建资源分组`, preventing imported commands from silently falling back to the currently selected host.
- 2026-05-07: Added a visible paste button and restored normal macOS paste semantics by adding a standard Edit menu plus a window-level paste key equivalent for text responders.
- 2026-05-07: Added Rust-side registry rule reference validation so stored rules cannot reference a missing host or a provider target from another host.

## Verification

- `swift build`
- `cargo test -p relaydock-core ssh_import -- --nocapture`
- `cargo test -p relaydock-core registry -- --nocapture`
- `git diff --check`
- GUI smoke with isolated `RELAYDOCK_STORE_PATH=/tmp/relaydock-gui-ssh-import.sqlite3`:
  - seeded one existing SSH host,
  - opened `资源登记 -> 导入 SSH`,
  - confirmed initial state is `等待粘贴`,
  - confirmed `Command+V` pastes `ssh -fN -L 18317:127.0.0.1:18317 root@111.230.202.80`,
  - parsed to `已解析 1 条`,
  - saved under a newly created `111.230.202.80` host,
  - reloaded the registry snapshot through `relaydock-bridge` and confirmed two hosts plus one imported rule under the new SSH target.

## Out Of Scope

- Keychain/credential management.
- SSH connectivity testing before save.
- Running the imported tunnel immediately after save.
- New daemon/supervisor behavior.
- Full Logs/Diagnostics redesign.
- Parsing unsupported SSH forwarding modes beyond current Rust parser support.

## Technical Notes

- Current import sheet is `RegistrySshImportSheet` in `apps/relaydock/Sources/Features/Registry/RegistryView.swift`.
- Current sheet case is `RegistrySheet.importSSH(RegistryHost)`, which forces host-local behavior.
- Swift already has:
  - `onParseSshCommand`
  - `onSaveHost`
  - `onSaveRule`
- Rust parser already accepts the sample command through `parse_ssh_command`.
- This task likely belongs mostly in Swift shell UI/orchestration, with Rust parser tests used as regression checks.
