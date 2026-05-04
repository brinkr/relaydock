import AppKit
import SwiftUI

private enum RelayDockToolbarItemIdentifier {
    static let search = NSToolbarItem.Identifier("RelayDockToolbarSearch")
    static let recheck = NSToolbarItem.Identifier("RelayDockToolbarRecheck")
    static let collapseAll = NSToolbarItem.Identifier("RelayDockToolbarCollapseAll")
    static let stopAll = NSToolbarItem.Identifier("RelayDockToolbarStopAll")
    static let clearRecovery = NSToolbarItem.Identifier("RelayDockToolbarClearRecovery")
}

@MainActor
final class RelayDockWindowController: NSWindowController {
    convenience init() {
        let rootView = RelayDockShellView(viewModel: RelayDockShellViewModel())
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "RelayDock"
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 920, height: 620)
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unifiedCompact
        window.toolbar = RelayDockToolbarController.makeToolbar()
        RelayDockWindowController.centerWindowOnPrimaryScreen(window)

        self.init(window: window)
        shouldCascadeWindows = true
    }

    private static func centerWindowOnPrimaryScreen(_ window: NSWindow) {
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let frame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

@MainActor
private final class RelayDockToolbarController: NSObject, NSToolbarDelegate {
    private static let shared = RelayDockToolbarController()

    static func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "RelayDockMainToolbar")
        toolbar.delegate = shared
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            RelayDockToolbarItemIdentifier.search,
            RelayDockToolbarItemIdentifier.recheck,
            RelayDockToolbarItemIdentifier.collapseAll,
            RelayDockToolbarItemIdentifier.stopAll,
            RelayDockToolbarItemIdentifier.clearRecovery,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case RelayDockToolbarItemIdentifier.search:
            return makeSearchItem()
        case RelayDockToolbarItemIdentifier.recheck:
            return makeButtonItem(identifier: itemIdentifier, title: "重新检查", symbolName: "arrow.clockwise")
        case RelayDockToolbarItemIdentifier.collapseAll:
            return makeButtonItem(identifier: itemIdentifier, title: "全部折叠", symbolName: "rectangle.compress.vertical")
        case RelayDockToolbarItemIdentifier.stopAll:
            return makeButtonItem(identifier: itemIdentifier, title: "停止全部运行", symbolName: "stop.fill")
        case RelayDockToolbarItemIdentifier.clearRecovery:
            return makeButtonItem(identifier: itemIdentifier, title: "清空恢复列表", symbolName: "xmark.circle")
        default:
            return nil
        }
    }

    private func makeSearchItem() -> NSToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: RelayDockToolbarItemIdentifier.search)
        let searchField = item.searchField
        searchField.placeholderString = "搜索主机 / 服务 / 别名"
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 12)

        item.label = "搜索"
        item.paletteLabel = "搜索"
        return item
    }

    private func makeButtonItem(
        identifier: NSToolbarItem.Identifier,
        title: String,
        symbolName: String
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = title
        item.paletteLabel = title
        item.toolTip = title
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        item.target = self
        item.action = #selector(toolbarActionPressed(_:))
        return item
    }

    @objc private func toolbarActionPressed(_ sender: NSToolbarItem) {}
}
