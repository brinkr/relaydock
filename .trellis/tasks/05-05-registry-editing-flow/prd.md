# Wire storage-backed registry editing flow

## Goal

Replace the current placeholder-only registry editing entry points with a real native configuration flow backed by RelayDock's existing Rust storage foundation.

This task exists because `资源登记` now looks structurally correct, but key entry points such as `新建资源分组`, `设置`, `新增规则`, `编辑映射`, and `编辑规则` still stop at placeholder sheets. The next useful step is to let the user create and modify saved configuration data through SwiftUI forms, persist that data through the bridge into Rust-owned storage, and reload it into the native registry workspace.

## What I already know

- The current shell and UI density work is complete and archived under `05-05-align-localport-ui`.
- `RegistryView` still routes all editing actions into `RegistryPlaceholderSheet`.
- Rust core already has SQLite-backed configuration storage via `RelayDockStore::save_configuration` / `load_configuration`.
- The bridge currently exposes `load_registry_snapshot`, but not a storage-backed mutation flow for registry configuration.
- The earlier runnable slice intentionally left registry editing UI and SSH command import out of scope.
- Product docs already define `资源登记` as the configuration center for hosts, rules, presets, provider targets, and SSH command import.
- The user confirmed that the first saved configuration should be created explicitly by `新建资源分组`, not by silently auto-seeding a starter snapshot.
- The user confirmed that the first editing slice should keep provider-target editing narrow: `类型(SSH/Tailscale) + 标签 + target_address + target_port(可选)`, without exposing `auth_ref` or credential management in Swift.

## Assumptions (temporary)

- First useful slice should prioritize saved host/rule/provider-target editing over SSH import and preset derivation.
- It is acceptable for `运行与恢复` to remain demo-backed in this task as long as `资源登记` stops being a fake editing surface.
- When no saved configuration exists yet, `资源登记` should stay empty until the user creates the first host through `新建资源分组`.
- Provider-target editing in this slice should stay limited to connection identity and addressing fields, leaving auth references and secrets outside the Swift form surface.

## Open Questions

## Requirements

- Replace placeholder-only registry sheets with functional native forms for the first configuration slice:
  - `新建资源分组`
  - `主机设置`
  - `新增规则`
  - `编辑映射`
  - `编辑规则`
- Keep the forms SwiftUI-native and focused; do not turn `资源登记` into a giant page-level editor.
- Add coarse-grained bridge commands for reading and writing registry configuration. Swift should submit structured form data; Rust should validate, persist, and return the next snapshot or a structured error.
- Rust storage remains the source of truth for saved hosts, rules, presets, and provider targets.
- The first saved configuration snapshot must be created explicitly from the `新建资源分组` flow when storage is empty.
- Provider-target forms in this slice should edit only:
  - `类型`
  - `标签`
  - `target_address`
  - `target_port(可选)`
- `auth_ref`, Keychain integration, and credential management must stay outside this slice.
- Registry reloads must reflect saved edits after:
  - sheet save
  - toolbar `重新检查`
  - app relaunch or fresh bridge reload
- Validation failures must surface as explicit user-visible sheet errors rather than silent no-ops.
- The first slice must cover enough provider-target data that a host and rule can be represented meaningfully in saved configuration without storing secrets in SQLite.

## Acceptance Criteria

- [ ] `资源登记` no longer uses placeholder sheets for `新建资源分组`, `主机设置`, `新增规则`, `编辑映射`, and `编辑规则`.
- [ ] Saving a new host updates the left host list immediately and persists across a fresh app launch or snapshot reload.
- [ ] Saving a new rule or editing an existing rule updates the selected-host rule list immediately and persists across reload.
- [ ] Bridge/storage validation errors are shown inside the editing flow with actionable text.
- [ ] `load_registry_snapshot` returns storage-backed configuration when saved data exists rather than always returning the demo registry fixture.
- [ ] `swift build`, `cargo test -p relaydock-core`, `cargo clippy --all-targets -- -D warnings`, and `git diff --check` pass.
- [ ] Visual QA captures a fresh `资源登记` screenshot showing at least one real editing flow result after save.

## Definition of Done

- Tests added or updated for new bridge/storage command behavior
- Native sheet forms compile and save through the bridge
- Validation and error mapping are documented if command contracts change
- Visual QA rerun after the editing flow lands

## Out of Scope

- SSH command import parsing UI and parser bridge
- Preset derivation or full preset editor
- Real SSH credential management, Keychain integration, or secret storage
- Tailscale-specific probing or runtime validation
- Replacing the current demo-backed `运行与恢复` snapshot with persisted runtime/config coupling

## Technical Notes

- Likely Swift files:
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  - bridge model / executor files under `apps/relaydock/Sources/Bridge/`
- Likely Rust files:
  - `crates/relaydock-core/src/commands.rs`
  - `crates/relaydock-core/src/storage.rs`
  - `crates/relaydock-core/src/domain.rs`
- Product / architecture references:
  - `documents/01-product-baseline.md`
  - `documents/03-domain-model.md`
  - `documents/06-provider-and-network-scenarios.md`
  - `documents/08-import-export-and-ai.md`
  - `documents/10-technology-stack-decision.md`
- This task should preserve the `SwiftUI + AppKit shell + Rust core` boundary and keep Swift from owning persistence rules.
