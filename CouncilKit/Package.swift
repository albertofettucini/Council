// swift-tools-version: 5.9
import PackageDescription

// CouncilKit — the Council engine, UI-free: providers, clients, fan-out orchestration,
// deliberation pipeline (peer review / debate / divergence judge / synthesis), session
// model + persistence, .council config codec, Keychain access. The app and the `council`
// CLI are both thin shells over this.
let package = Package(
    name: "CouncilKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CouncilKit", targets: ["CouncilKit"]),
        .executable(name: "council", targets: ["council"]),
    ],
    targets: [
        .target(name: "CouncilKit"),
        .executableTarget(name: "council", dependencies: ["CouncilKit"]),
        .testTarget(name: "CouncilKitTests", dependencies: ["CouncilKit"]),
    ]
)
