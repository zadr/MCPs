import Foundation
import MCP

enum NotarytoolTool {
    static let name = "notarytool"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Apple notarization service. Submit apps for notarization, check status, view history, and retrieve logs.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("submit"),
                            .string("status"),
                            .string("history"),
                            .string("log"),
                            .string("wait"),
                        ]),
                        "description": .string("The notarytool action to perform. One of: submit, status, history, log, wait"),
                    ]),
                    "filePath": .object([
                        "type": .string("string"),
                        "description": .string("Path to the file to submit (.dmg, .zip, or .pkg). Required for submit."),
                    ]),
                    "keychainProfile": .object([
                        "type": .string("string"),
                        "description": .string("Name of the keychain profile with stored notarization credentials (created via 'xcrun notarytool store-credentials')"),
                    ]),
                    "submissionId": .object([
                        "type": .string("string"),
                        "description": .string("Submission ID returned from a previous submit. Required for status, log, and wait."),
                    ]),
                    "wait": .object([
                        "type": .string("boolean"),
                        "description": .string("Wait for notarization to complete before returning (submit action only, default false)"),
                    ]),
                    "timeout": .object([
                        "type": .string("string"),
                        "description": .string("Timeout duration for wait, e.g. \"10m\", \"1h\" (used with submit --wait or the wait action)"),
                    ]),
                ]),
                "required": .array([.string("action"), .string("keychainProfile")]),
            ]),
            annotations: .init(readOnlyHint: false, openWorldHint: true)
        )
    }

    // MARK: - Handle

    static func handle(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: action")
        }
        guard let keychainProfile = args["keychainProfile"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: keychainProfile")
        }

        switch action {
        case "submit":
            return try await handleSubmit(args: args, keychainProfile: keychainProfile)
        case "status":
            return try await handleStatus(args: args, keychainProfile: keychainProfile)
        case "history":
            return try await handleHistory(keychainProfile: keychainProfile)
        case "log":
            return try await handleLog(args: args, keychainProfile: keychainProfile)
        case "wait":
            return try await handleWait(args: args, keychainProfile: keychainProfile)
        default:
            throw MCPError.invalidParams(
                "Unknown action: \(action). Valid actions: submit, status, history, log, wait"
            )
        }
    }

    // MARK: - Actions

    private static func handleSubmit(
        args: [String: Value],
        keychainProfile: String
    ) async throws -> CallTool.Result {
        guard let filePath = args["filePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: filePath (required for submit)")
        }

        var cmdArgs = ["notarytool", "submit", filePath]
        cmdArgs.append(contentsOf: ["--keychain-profile", keychainProfile])

        if args["wait"]?.boolValue == true {
            cmdArgs.append("--wait")
        }
        if let timeout = args["timeout"]?.stringValue {
            cmdArgs.append(contentsOf: ["--timeout", timeout])
        }
        cmdArgs.append(contentsOf: ["--output-format", "json"])

        let result = try await runNotarytool(cmdArgs)
        let isError = result.exitCode != 0
        let summary = formatJSONOutput(result.output, action: "submit", isError: isError)
        return .init(content: [.text(text: summary, annotations: nil, _meta: nil)], isError: isError)
    }

    private static func handleStatus(
        args: [String: Value],
        keychainProfile: String
    ) async throws -> CallTool.Result {
        guard let submissionId = args["submissionId"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: submissionId (required for status)")
        }

        let cmdArgs = [
            "notarytool", "info", submissionId,
            "--keychain-profile", keychainProfile,
            "--output-format", "json",
        ]

        let result = try await runNotarytool(cmdArgs)
        let isError = result.exitCode != 0
        let summary = formatJSONOutput(result.output, action: "status", isError: isError)
        return .init(content: [.text(text: summary, annotations: nil, _meta: nil)], isError: isError)
    }

    private static func handleHistory(
        keychainProfile: String
    ) async throws -> CallTool.Result {
        let cmdArgs = [
            "notarytool", "history",
            "--keychain-profile", keychainProfile,
            "--output-format", "json",
        ]

        let result = try await runNotarytool(cmdArgs)
        let isError = result.exitCode != 0
        let summary = formatJSONOutput(result.output, action: "history", isError: isError)
        return .init(content: [.text(text: summary, annotations: nil, _meta: nil)], isError: isError)
    }

    private static func handleLog(
        args: [String: Value],
        keychainProfile: String
    ) async throws -> CallTool.Result {
        guard let submissionId = args["submissionId"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: submissionId (required for log)")
        }

        // notarytool log outputs JSON directly (no --output-format needed)
        let cmdArgs = [
            "notarytool", "log", submissionId,
            "--keychain-profile", keychainProfile,
        ]

        let result = try await runNotarytool(cmdArgs)
        let isError = result.exitCode != 0
        let summary = formatJSONOutput(result.output, action: "log", isError: isError)
        return .init(content: [.text(text: summary, annotations: nil, _meta: nil)], isError: isError)
    }

    private static func handleWait(
        args: [String: Value],
        keychainProfile: String
    ) async throws -> CallTool.Result {
        guard let submissionId = args["submissionId"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: submissionId (required for wait)")
        }

        var cmdArgs = [
            "notarytool", "wait", submissionId,
            "--keychain-profile", keychainProfile,
        ]
        if let timeout = args["timeout"]?.stringValue {
            cmdArgs.append(contentsOf: ["--timeout", timeout])
        }
        cmdArgs.append(contentsOf: ["--output-format", "json"])

        let result = try await runNotarytool(cmdArgs)
        let isError = result.exitCode != 0
        let summary = formatJSONOutput(result.output, action: "wait", isError: isError)
        return .init(content: [.text(text: summary, annotations: nil, _meta: nil)], isError: isError)
    }

    // MARK: - Helpers

    /// Run notarytool via xcrun.
    private static func runNotarytool(_ arguments: [String]) async throws -> ShellCommand.Result {
        try await ShellCommand.run("/usr/bin/xcrun", arguments: arguments)
    }

    /// Attempt to pretty-print JSON output, or return raw output with a status header.
    private static func formatJSONOutput(_ rawOutput: String, action: String, isError: Bool) -> String {
        let statusLabel = isError ? "FAILED" : "OK"
        let header = "notarytool \(action): \(statusLabel)"

        // Try to pretty-print JSON
        guard let data = rawOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            // Not valid JSON — return raw output
            return "\(header)\n\n\(rawOutput)"
        }

        return "\(header)\n\n\(prettyString)"
    }
}
