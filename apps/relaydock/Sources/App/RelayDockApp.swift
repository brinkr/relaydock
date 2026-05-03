import AppKit
import SwiftUI

@main
final class RelayDockApp: NSObject, NSApplicationDelegate {
    private var windowController: RelayDockWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = RelayDockApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let windowController = RelayDockWindowController()
        self.windowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
