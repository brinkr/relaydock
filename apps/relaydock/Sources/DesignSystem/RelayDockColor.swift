import SwiftUI

enum RelayDockColor {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(red: 0.965, green: 0.965, blue: 0.969)
    static let sidebarSelection = Color.black.opacity(0.05)
    static let sidebarAccent = Color(red: 0.000, green: 0.478, blue: 1.000)
    static let topBarBackground = Color.white.opacity(0.96)
    static let contentBackground = Color(nsColor: .textBackgroundColor)
    static let controlBackground = Color(red: 0.953, green: 0.961, blue: 0.973)
    static let listBandBackground = Color(red: 0.988, green: 0.990, blue: 0.994)
    static let groupHeaderBackground = Color(red: 0.976, green: 0.980, blue: 0.988)
    static let rowHover = Color(red: 0.972, green: 0.978, blue: 0.988)
    static let subtleBorder = Color(nsColor: .separatorColor)
}
