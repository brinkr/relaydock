# Storage And Diagnostics

Use SQLite as the default local data store unless a later ADR changes it.

Rust core should own:

- configuration schema
- migrations
- import/export validation
- runtime persistence
- recovery collection persistence

Sensitive credentials should use macOS Keychain through the Swift/platform layer, not plain SQLite.

Diagnostics should be structured enough for:

- UI display
- log filtering
- future CLI/agent queries
- conflict diagnosis
