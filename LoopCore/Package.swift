// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoopCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LoopCore", targets: ["LoopCore"])],
    targets: [
        .target(name: "CAtomic"),
        .target(name: "LoopCore", dependencies: ["CAtomic"]),
        .testTarget(name: "LoopCoreTests", dependencies: ["LoopCore"]),
    ]
)
