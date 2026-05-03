// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "relaydock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "relaydock", targets: ["RelayDockApp"])
    ],
    targets: [
        .executableTarget(
            name: "RelayDockApp",
            path: "apps/relaydock/Sources"
        )
    ]
)
