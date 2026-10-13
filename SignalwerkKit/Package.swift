// swift-tools-version: 5.9
import PackageDescription

// Kern der Signalwerk-App: Datenmodelle, Schnittstelle zum Dashboard (/api/app/v1),
// Live-Ereignisse (SSE), Chat über Socket.IO und eine Demo ohne Server. Ohne UIKit/SwiftUI,
// damit die Tests mit `swift test` auch auf dem Mac-Runner laufen.
let package = Package(
    name: "SignalwerkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SignalwerkKit", targets: ["SignalwerkKit"]),
    ],
    targets: [
        .target(name: "SignalwerkKit"),
        .testTarget(
            name: "SignalwerkKitTests",
            dependencies: ["SignalwerkKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
