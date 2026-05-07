import AppKit
import SwiftUI

@MainActor
final class RelayDockWindowController: NSWindowController {
    convenience init() {
        let rootView = RelayDockShellView(viewModel: RelayDockShellViewModel())
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "RelayDock"
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 920, height: 620)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
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
