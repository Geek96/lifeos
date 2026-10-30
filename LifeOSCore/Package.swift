// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LifeOSCore", targets: ["LifeOSCore"]),
    ],
    targets: [
        .target(name: "LifeOSCore"),
        .testTarget(name: "LifeOSCoreTests", dependencies: ["LifeOSCore"]),
    ]
)
