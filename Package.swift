// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "pr-scout",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "pr-scout", targets: ["PRScout"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "PRScout",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "PRScoutTests",
            dependencies: ["PRScout"]
        ),
    ]
)
