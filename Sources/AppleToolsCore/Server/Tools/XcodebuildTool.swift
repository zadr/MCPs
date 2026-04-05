import Foundation
import MCP

enum XcodebuildTool {
    static let name = "xcodebuild"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Xcode build system. Build, test, clean, archive projects, list schemes, and inspect build settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("list_schemes"),
                            .string("build"),
                            .string("test"),
                            .string("clean"),
                            .string("archive"),
                            .string("show_build_settings"),
                            .string("analyze"),
                        ]),
                        "description": .string("The xcodebuild action to perform. One of: list_schemes, build, test, clean, archive, show_build_settings, analyze"),
                    ]),
                    "projectPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to directory containing .xcodeproj or .xcworkspace"),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string("The scheme to build/test/clean/archive/analyze"),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration, e.g. \"Debug\" or \"Release\""),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "description": .string("Build destination, e.g. \"platform=iOS Simulator,name=iPhone 15\""),
                    ]),
                    "extraArgs": .object([
                        "type": .string("string"),
                        "description": .string("Additional xcodebuild arguments or build settings, e.g. \"ARCHS=arm64 CODE_SIGNING_ALLOWED=NO\""),
                    ]),
                    "archivePath": .object([
                        "type": .string("string"),
                        "description": .string("Path for the .xcarchive output (required for archive action)"),
                    ]),
                    "onlyTesting": .object([
                        "type": .string("string"),
                        "description": .string("Run only specific tests, e.g. \"MyAppTests/testLogin\""),
                    ]),
                    "skipTesting": .object([
                        "type": .string("string"),
                        "description": .string("Skip specific tests, e.g. \"MyAppUITests\""),
                    ]),
                ]),
                "required": .array([.string("action"), .string("projectPath")]),
            ]),
            annotations: .init(readOnlyHint: false, openWorldHint: false)
        )
    }

    // MARK: - Handle

    static func handle(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: action")
        }
        guard let projectPath = args["projectPath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: projectPath")
        }

        switch action {
        case "list_schemes":
            return try await handleListSchemes(projectPath: projectPath)
        case "build":
            return try await handleBuild(args: args, projectPath: projectPath)
        case "test":
            return try await handleTest(args: args, projectPath: projectPath)
        case "clean":
            return try await handleClean(args: args, projectPath: projectPath)
        case "archive":
            return try await handleArchive(args: args, projectPath: projectPath)
        case "show_build_settings":
            return try await handleShowBuildSettings(args: args, projectPath: projectPath)
        case "analyze":
            return try await handleAnalyze(args: args, projectPath: projectPath)
        default:
            throw MCPError.invalidParams(
                "Unknown action: \(action). Valid actions: list_schemes, build, test, clean, archive, show_build_settings, analyze"
            )
        }
    }

    // MARK: - Actions

    private static func handleListSchemes(projectPath: String) async throws -> CallTool.Result {
        var cmdArgs = [String]()
        if let projectArg = try detectProjectArgument(in: projectPath) {
            cmdArgs.append(contentsOf: projectArg)
        }
        cmdArgs.append("-list")

        let result = try await runXcodebuild(cmdArgs, workingDirectory: projectPath)
        let isError = result.exitCode != 0

        if isError {
            return .init(content: [.text(text: result.output, annotations: nil, _meta: nil)], isError: true)
        }

        let info = XcodebuildOutputParser.parseListOutput(result.output)
        let formatted = XcodebuildOutputParser.formatProjectInfo(info)
        return .init(content: [.text(text: formatted, annotations: nil, _meta: nil)], isError: false)
    }

    private static func handleBuild(args: [String: Value], projectPath: String) async throws -> CallTool.Result {
        guard let scheme = args["scheme"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: scheme (required for build)")
        }

        var cmdArgs = try buildCommonArgs(projectPath: projectPath, scheme: scheme, args: args)
        cmdArgs.insert("build", at: 0)
        appendExtraArgs(from: args, to: &cmdArgs)

        let result = try await runXcodebuild(cmdArgs, workingDirectory: projectPath)
        let parsed = XcodebuildOutputParser.parseBuildOutput(result.output, exitCode: result.exitCode)
        let response = XcodebuildOutputParser.formatBuildResult(parsed, action: "Build")
        return .init(
            content: [.text(text: response, annotations: nil, _meta: nil)],
            isError: !parsed.succeeded
        )
    }

    private static func handleTest(args: [String: Value], projectPath: String) async throws -> CallTool.Result {
        guard let scheme = args["scheme"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: scheme (required for test)")
        }

        var cmdArgs = try buildCommonArgs(projectPath: projectPath, scheme: scheme, args: args)
        cmdArgs.insert("test", at: 0)

        if let onlyTesting = args["onlyTesting"]?.stringValue {
            cmdArgs.append(contentsOf: ["-only-testing:\(onlyTesting)"])
        }
        if let skipTesting = args["skipTesting"]?.stringValue {
            cmdArgs.append(contentsOf: ["-skip-testing:\(skipTesting)"])
        }
        appendExtraArgs(from: args, to: &cmdArgs)

        let result = try await runXcodebuild(cmdArgs, workingDirectory: projectPath)
        let parsed = XcodebuildOutputParser.parseTestOutput(result.output, exitCode: result.exitCode)
        let response = XcodebuildOutputParser.formatTestResult(parsed)
        return .init(
            content: [.text(text: response, annotations: nil, _meta: nil)],
            isError: !parsed.succeeded
        )
    }

    private static func handleClean(args: [String: Value], projectPath: String) async throws -> CallTool.Result {
        guard let scheme = args["scheme"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: scheme (required for clean)")
        }

        var cmdArgs = try buildCommonArgs(projectPath: projectPath, scheme: scheme, args: args)
        cmdArgs.insert("clean", at: 0)

        let result = try await runXcodebuild(cmdArgs, workingDirectory: projectPath)
        let isError = result.exitCode != 0
        let status = isError ? "Clean failed (exit code \(result.exitCode))." : "Clean succeeded."
        return .init(
            content: [.text(text: status, annotations: nil, _meta: nil)],
            isError: isError
        )
    }

    private static func handleArchive(args: [String: Value], projectPath: String) async throws -> CallTool.Result {
        guard let scheme = args["scheme"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: scheme (required for archive)")
        }
        guard let archivePath = args["archivePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: archivePath (required for archive)")
        }

        var cmdArgs = try buildCommonArgs(projectPath: projectPath, scheme: scheme, args: args)
        cmdArgs.insert("archive", at: 0)
        cmdArgs.append(contentsOf: ["-archivePath", archivePath])
        appendExtraArgs(from: args, to: &cmdArgs)

        let result = try await runXcodebuild(cmdArgs, workingDirectory: projectPath)
        let parsed = XcodebuildOutputParser.parseBuildOutput(result.output, exitCode: result.exitCode)
        var response = XcodebuildOutputParser.formatBuildResult(parsed, action: "Archive")
        if parsed.succeeded {
            response += "\nArchive path: \(archivePath)"
        }
        return .init(
            content: [.text(text: response, annotations: nil, _meta: nil)],
            isError: !parsed.succeeded
        )
    }

    private static func handleShowBuildSettings(args: [String: Value], projectPath: String) async throws -> CallTool.Result {
        guard let scheme = args["scheme"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: scheme (required for show_build_settings)")
        }

        var cmdArgs = try buildCommonArgs(projectPath: projectPath, scheme: scheme, args: args)
        cmdArgs.append("-showBuildSettings")

        let result = try await runXcodebuild(cmdArgs, workingDirectory: projectPath)
        let isError = result.exitCode != 0

        if isError {
            return .init(content: [.text(text: result.output, annotations: nil, _meta: nil)], isError: true)
        }

        let cleaned = XcodebuildOutputParser.parseBuildSettings(result.output)
        return .init(content: [.text(text: cleaned, annotations: nil, _meta: nil)], isError: false)
    }

    private static func handleAnalyze(args: [String: Value], projectPath: String) async throws -> CallTool.Result {
        guard let scheme = args["scheme"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: scheme (required for analyze)")
        }

        var cmdArgs = try buildCommonArgs(projectPath: projectPath, scheme: scheme, args: args)
        cmdArgs.insert("analyze", at: 0)
        appendExtraArgs(from: args, to: &cmdArgs)

        let result = try await runXcodebuild(cmdArgs, workingDirectory: projectPath)
        let parsed = XcodebuildOutputParser.parseAnalyzeOutput(result.output, exitCode: result.exitCode)
        let response = XcodebuildOutputParser.formatBuildResult(parsed, action: "Analyze")
        return .init(
            content: [.text(text: response, annotations: nil, _meta: nil)],
            isError: !parsed.succeeded
        )
    }

    // MARK: - Helpers

    /// Detect whether the directory contains a .xcworkspace or .xcodeproj and return the
    /// appropriate -workspace/-project argument pair. Prefers workspace over project.
    private static func detectProjectArgument(in directoryPath: String) throws -> [String]? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directoryPath) else {
            throw MCPError.invalidParams("Cannot read directory: \(directoryPath)")
        }

        // Prefer .xcworkspace (but skip Pods workspace and any inside .xcodeproj bundles)
        if let workspace = entries.first(where: {
            $0.hasSuffix(".xcworkspace") && $0 != "Pods.xcworkspace"
        }) {
            let fullPath = (directoryPath as NSString).appendingPathComponent(workspace)
            return ["-workspace", fullPath]
        }

        if let project = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            let fullPath = (directoryPath as NSString).appendingPathComponent(project)
            return ["-project", fullPath]
        }

        // No project/workspace found — xcodebuild may still work if there's a Package.swift
        return nil
    }

    /// Build common arguments: project/workspace detection, -scheme, -configuration, -destination.
    private static func buildCommonArgs(
        projectPath: String,
        scheme: String,
        args: [String: Value]
    ) throws -> [String] {
        var cmdArgs = [String]()
        if let projectArg = try detectProjectArgument(in: projectPath) {
            cmdArgs.append(contentsOf: projectArg)
        }
        cmdArgs.append(contentsOf: ["-scheme", scheme])

        if let configuration = args["configuration"]?.stringValue {
            cmdArgs.append(contentsOf: ["-configuration", configuration])
        }
        if let destination = args["destination"]?.stringValue {
            cmdArgs.append(contentsOf: ["-destination", destination])
        }
        return cmdArgs
    }

    /// Parse and append space-separated extra arguments.
    private static func appendExtraArgs(from args: [String: Value], to cmdArgs: inout [String]) {
        if let extraArgs = args["extraArgs"]?.stringValue, !extraArgs.isEmpty {
            let extras = extraArgs.components(separatedBy: " ").filter { !$0.isEmpty }
            cmdArgs.append(contentsOf: extras)
        }
    }

    /// Resolve xcodebuild path and run the command.
    private static func runXcodebuild(
        _ arguments: [String],
        workingDirectory: String
    ) async throws -> ShellCommand.Result {
        // Use xcrun to find xcodebuild, falling back to the standard path
        let xcodebuildPath = "/usr/bin/xcrun"
        var fullArgs = ["xcodebuild"]
        fullArgs.append(contentsOf: arguments)
        return try await ShellCommand.run(xcodebuildPath, arguments: fullArgs, workingDirectory: workingDirectory)
    }
}
