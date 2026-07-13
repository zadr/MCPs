// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPs",
    platforms: [
        .macOS(.v13)
    ],

    /* git-tools */
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

        /* apple-tools */
        .target(
            name: "AppleToolsCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "apple-tools/Sources/AppleToolsCore"
        ),
        .executableTarget(
            name: "apple-tools-mcp",
            dependencies: ["AppleToolsCore"],
            path: "apple-tools/Sources/apple-tools-mcp"
        ),
        .testTarget(
            name: "AppleToolsCoreTests",
            dependencies: ["AppleToolsCore"],
            path: "apple-tools/Tests"
        ),
    ]
)
