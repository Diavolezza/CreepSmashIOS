// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CreepSmashCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CreepSmashCore", targets: ["CreepSmashCore"])
    ],
    targets: [
        .target(name: "CreepSmashCore"),
        .testTarget(name: "CreepSmashCoreTests", dependencies: ["CreepSmashCore"])
    ]
)
