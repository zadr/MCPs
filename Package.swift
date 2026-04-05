// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "apple-tools-mcp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AppleToolsCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AppleToolsCore"
        ),
        .executableTarget(
            name: "apple-tools-mcp",
            dependencies: ["AppleToolsCore"],
            path: "Sources/apple-tools-mcp"
        ),
        .testTarget(
            name: "AppleToolsCoreTests",
            dependencies: ["AppleToolsCore"]
        ),
    ]
)
