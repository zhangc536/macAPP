// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "YourApp",
            targets: ["YourApp"]
        )
    ],
    dependencies: [
        // 添加任何必要的依赖
    ],
    targets: [
        .executableTarget(
            name: "YourApp",
            dependencies: [],
            path: "trae/Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
