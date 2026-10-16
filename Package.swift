// swift-tools-version: 6.0
// 轻量验证入口：`swift build` / `swift test` 即可编译全部代码（含 SwiftUI App）。
// 正式的 .app 打包走 project.yml + xcodegen（见 Scripts/bootstrap.sh）。
import PackageDescription

let package = Package(
    name: "LifeOS",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "LifeOS", targets: ["LifeOS"]),
    ],
    dependencies: [
        .package(path: "LifeOSCore"),
    ],
    targets: [
        .executableTarget(
            name: "LifeOS",
            dependencies: ["LifeOSCore"],
            path: "LifeOS",
            exclude: ["Resources"]
        ),
    ]
)
