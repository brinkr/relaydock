# Create Native Swift App Shell

## Purpose

Create the first macOS-native RelayDock application shell using SwiftUI plus AppKit where needed.

This task establishes the real app surface without implementing provider runtime behavior.

## Inputs

- `documents/01-product-baseline.md`
- `documents/05-ui-information-architecture.md`
- `documents/10-technology-stack-decision.md`
- `documents/11-localport-prototype-reference.md`
- `.trellis/spec/project/index.md`
- `.trellis/spec/swift-shell/index.md`

## Requirements

- Create the macOS app project structure.
- Add a native main window shell with source-list sidebar, top toolbar, status bar, and placeholder content for the four top-level pages.
- Include pages named `运行与恢复`, `资源登记`, `日志与诊断`, and `偏好设置`.
- Keep Chinese-first UI text.
- Use LocalPort only as a visual/information-density reference.
- Keep destructive actions separate in visible labels.

## Non-Goals

- No runtime provider execution.
- No Rust core implementation.
- No WebView/React/Tauri/Electron shell.
- No dashboard/KPI homepage.

## Acceptance Criteria

- The project opens as a native macOS app shell.
- The four page placeholders are reachable from the source list.
- Toolbar and status bar are present.
- Layout direction follows the RelayDock UI documents, not the LocalPort React component tree.
