# State And ViewModel Boundaries

Swift may own:

- selected sidebar item
- selected host/rule
- expanded/collapsed UI state
- form drafts
- sheet/popover presentation state
- platform permission prompts
- user-visible transient feedback

Swift should not own:

- SSH command parsing
- port scan logic
- runtime recovery strategy
- provider process orchestration state machine
- conflict diagnosis rules
- persisted recovery collection logic

When a ViewModel needs domain state, request a structured snapshot from Rust core through the bridge.
