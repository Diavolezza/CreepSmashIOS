// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CreepSmashCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CreepSmashCore", targets: ["CreepSmashCore"])
    ],
    targets: [
        // Optimized also in Debug builds: continuing a saved game replays it, which takes many times
        // longer without optimization (and the tests run faster).
        .target(name: "CreepSmashCore", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .testTarget(name: "CreepSmashCoreTests", dependencies: ["CreepSmashCore"])
    ]
)
