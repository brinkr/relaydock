# Rust Core Directory Structure

The concrete Rust crate has not been created yet. Use this layout when adding it:

- `crates/relaydock-core/` for the reusable domain and runtime library
- `crates/relaydock-ffi/` for C ABI / Swift bridge exports if needed
- `crates/relaydock-cli/` only when CLI reuse becomes an explicit task

Inside `relaydock-core`, prefer modules around domain ownership:

- `domain`
- `runtime`
- `providers`
- `ports`
- `storage`
- `diagnostics`
- `import`

Do not put macOS UI or Swift-specific concepts inside `relaydock-core`.
