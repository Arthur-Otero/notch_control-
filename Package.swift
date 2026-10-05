// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchControl",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NotchControlCore", targets: ["NotchControlCore"]),
        .executable(name: "NotchControlProof", targets: ["NotchControlProof"]),
        .executable(name: "NotchControl", targets: ["NotchControl"])
    ],
    targets: [
        .target(name: "NotchControlCore"),
        .target(name: "NotchControlUI", dependencies: ["NotchControlCore"]),
        .executableTarget(name: "NotchControlProof", dependencies: ["NotchControlCore", "NotchControlUI"]),
        .executableTarget(name: "NotchControl", dependencies: ["NotchControlCore", "NotchControlUI"], resources: [.process("Resources")]),
        .testTarget(name: "NotchControlCoreTests", dependencies: ["NotchControlCore"]),
        .testTarget(name: "NotchControlPresentationTests", dependencies: ["NotchControl", "NotchControlUI"])
    ]
)
