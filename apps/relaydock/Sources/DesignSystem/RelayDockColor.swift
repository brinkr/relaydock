import SwiftUI

enum RelayDockColor {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let sidebarSelection = Color.primary.opacity(0.07)
    static let contentBackground = Color(nsColor: .textBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let rowHover = Color.primary.opacity(0.035)
    static let subtleBorder = Color.primary.opacity(0.09)
}
