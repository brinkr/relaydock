# Rust Core Directory Structure

The Rust workspace is rooted at the repository root.

Current crate:

- `crates/relaydock-core/` contains the reusable domain and runtime library.

Planned crates:

- `crates/relaydock-ffi/` for C ABI / Swift bridge exports if needed
- `crates/relaydock-cli/` only when CLI reuse becomes an explicit task

Inside `relaydock-core`, use modules around domain ownership.

Current modules:

- `domain`
- `runtime`
- `ports`

Planned modules:

- `providers`
- `storage`
- `diagnostics`
- `import`

Do not put macOS UI or Swift-specific concepts inside `relaydock-core`.
