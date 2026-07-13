// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "git-tools-mcp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "GitToolsCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "git-tools/Sources/GitToolsCore"
        ),
        .executableTarget(
            name: "git-tools-mcp",
            dependencies: ["GitToolsCore"],
            path: "git-tools/Sources/git-tools-mcp"
        ),
        .testTarget(
            name: "GitToolsCoreTests",
            dependencies: ["GitToolsCore"],
            path: "git-tools/Tests"
        ),
    ]
)
