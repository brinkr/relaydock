import AppKit
import SwiftUI

final class RelayDockWindowController: NSWindowController {
    convenience init() {
        let rootView = RelayDockShellView(viewModel: RelayDockShellViewModel())
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "RelayDock"
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 920, height: 620)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unifiedCompact

        self.init(window: window)
        shouldCascadeWindows = true
    }
}
