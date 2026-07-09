import Foundation
import MCP

enum SwiftLintTool {
    static let name = "swiftlint"

    static var definition: Tool {
        Tool(
            name: name,
            description: "SwiftLint linter. Lint Swift files for style and convention violations, auto-correct fixable issues, and inspect rule configuration. Searches common installation paths (Homebrew, Mint, CocoaPods, SPM build).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("lint"),
                            .string("fix"),
                            .string("rules"),
                            .string("rule_config"),
                            .string("version"),
                        ]),
                        "description": .string("The action to perform. lint: run linter, fix: auto-correct fixable violations, rules: list available rules, rule_config: show effective value for a specific rule, version: show SwiftLint version"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to a Swift file or directory to lint/fix"),
                    ]),
                    "configPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to a .swiftlint.yml config file (optional, auto-detected if omitted)"),
                    ]),
                    "strict": .object([
                        "type": .string("boolean"),
                        "description": .string("Treat warnings as errors (default: false, for lint)"),
                    ]),
                    "ruleName": .object([
                        "type": .string("string"),
                        "description": .string("Rule identifier to inspect, e.g. \"line_length\" (for rule_config)"),
                    ]),
                    "enabledOnly": .object([
                        "type": .string("boolean"),
                        "description": .string("Only show enabled rules (default: false, for rules)"),
                    ]),
                    "swiftlintPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to swiftlint binary (optional, auto-detected from Homebrew/Mint/PATH if omitted; use for Bazel, Docker, or custom installations)"),
                    ]),
                    "traceLog": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to write an exhaustive JSONL trace log to for debugging. Enables tracing process-wide once set."),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(readOnlyHint: false, openWorldHint: false)
        )
    }

    // MARK: - Handle

    static func handle(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        if let traceLogPath = arguments?["traceLog"]?.stringValue, !traceLogPath.isEmpty {
            TraceLog.enable(path: traceLogPath)
        }
        TraceLog.enter([("arguments", String(describing: arguments))])
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            TraceLog.point("missing-action")
            throw MCPError.invalidParams("Missing required argument: action")
        }

        switch action {
        case "lint":
            TraceLog.point("action:lint")
            return try await handleLint(args: args)
        case "fix":
            TraceLog.point("action:fix")
            return try await handleFix(args: args)
        case "rules":
            TraceLog.point("action:rules")
            return try await handleRules(args: args)
        case "rule_config":
            TraceLog.point("action:rule_config")
            return try await handleRuleConfig(args: args)
        case "version":
            TraceLog.point("action:version")
            return try await handleVersion(args: args)
        default:
            TraceLog.point("unknown-action", [("action", action)])
            throw MCPError.invalidParams(
                "Unknown action: \(action). Valid actions: lint, fix, rules, rule_config, version"
            )
        }
    }

    // MARK: - Lint

    private static func handleLint(args: [String: Value]) async throws -> CallTool.Result {
        TraceLog.enter()
        guard let path = args["path"]?.stringValue else {
            TraceLog.point("missing-path")
            throw MCPError.invalidParams("Missing required argument: path (for lint)")
        }

        let overridePath = args["swiftlintPath"]?.stringValue
        var cmdArgs = ["lint", "--reporter", "json", "--quiet"]
        if let configPath = args["configPath"]?.stringValue {
            TraceLog.point("config-path", [("configPath", configPath)])
            cmdArgs.append(contentsOf: ["--config", configPath])
        }
        if args["strict"]?.boolValue == true {
            TraceLog.point("strict-enabled")
            cmdArgs.append("--strict")
        }
        cmdArgs.append(path)

        let result = try await runSwiftLint(cmdArgs, workingDirectory: directoryForPath(path), overridePath: overridePath)

        let violations = parseJSONViolations(result.output)

        if violations.isEmpty && result.exitCode == 0 {
            TraceLog.exit([("violations", 0), ("exitCode", result.exitCode)])
            return textResult("Lint passed. No violations.")
        }

        let formatted = formatViolations(violations)
        let isError = violations.contains { $0.severity == "error" } || result.exitCode != 0
        TraceLog.exit([("violations", violations.count), ("isError", isError), ("exitCode", result.exitCode)])
        return .init(
            content: [.text(text: formatted, annotations: nil, _meta: nil)],
            isError: isError
        )
    }

    // MARK: - Fix

    private static func handleFix(args: [String: Value]) async throws -> CallTool.Result {
        TraceLog.enter()
        guard let path = args["path"]?.stringValue else {
            TraceLog.point("missing-path")
            throw MCPError.invalidParams("Missing required argument: path (for fix)")
        }

        let overridePath = args["swiftlintPath"]?.stringValue
        var cmdArgs = ["lint", "--fix", "--reporter", "json", "--quiet"]
        if let configPath = args["configPath"]?.stringValue {
            TraceLog.point("config-path", [("configPath", configPath)])
            cmdArgs.append(contentsOf: ["--config", configPath])
        }
        cmdArgs.append(path)

        let result = try await runSwiftLint(cmdArgs, workingDirectory: directoryForPath(path), overridePath: overridePath)

        let remaining = parseJSONViolations(result.output)

        if remaining.isEmpty {
            TraceLog.exit([("remaining", 0)])
            return textResult("Fix complete. No remaining violations.")
        }

        let formatted = formatViolations(remaining)
        TraceLog.exit([("remaining", remaining.count)])
        return textResult("Fix complete. Remaining violations:\n\n\(formatted)")
    }

    // MARK: - Rules

    private static func handleRules(args: [String: Value]) async throws -> CallTool.Result {
        TraceLog.enter()
        let overridePath = args["swiftlintPath"]?.stringValue
        var cmdArgs = ["rules"]

        if let configPath = args["configPath"]?.stringValue {
            TraceLog.point("config-path", [("configPath", configPath)])
            cmdArgs.append(contentsOf: ["--config", configPath])
        }
        if args["enabledOnly"]?.boolValue == true {
            TraceLog.point("enabled-only")
            cmdArgs.append("--enabled")
        }

        let result = try await runSwiftLint(cmdArgs, overridePath: overridePath)
        if result.exitCode != 0 {
            TraceLog.exit([("exitCode", result.exitCode)])
            return errorResult("swiftlint rules failed:\n\(result.output)")
        }

        let parsed = parseRulesTable(result.output)
        TraceLog.exit([("exitCode", result.exitCode)])
        return textResult(parsed)
    }

    // MARK: - Rule Config

    private static func handleRuleConfig(args: [String: Value]) async throws -> CallTool.Result {
        TraceLog.enter()
        guard let ruleName = args["ruleName"]?.stringValue else {
            TraceLog.point("missing-ruleName")
            throw MCPError.invalidParams("Missing required argument: ruleName (for rule_config)")
        }

        let overridePath = args["swiftlintPath"]?.stringValue
        var cmdArgs = ["rules"]
        if let configPath = args["configPath"]?.stringValue {
            TraceLog.point("config-path", [("configPath", configPath)])
            cmdArgs.append(contentsOf: ["--config", configPath])
        }

        let result = try await runSwiftLint(cmdArgs, overridePath: overridePath)
        if result.exitCode != 0 {
            TraceLog.exit([("exitCode", result.exitCode)])
            return errorResult("swiftlint rules failed:\n\(result.output)")
        }

        let ruleInfo = extractRuleFromTable(result.output, identifier: ruleName)
        if let ruleInfo {
            TraceLog.exit([("found", true), ("ruleName", ruleName)])
            return textResult(ruleInfo)
        }

        TraceLog.exit([("found", false), ("ruleName", ruleName)])
        return errorResult("Rule \"\(ruleName)\" not found. Use action \"rules\" to list available rules.")
    }

    // MARK: - Version

    private static func handleVersion(args: [String: Value]) async throws -> CallTool.Result {
        TraceLog.enter()
        let result = try await runSwiftLint(["version"], overridePath: args["swiftlintPath"]?.stringValue)
        if result.exitCode != 0 {
            TraceLog.exit([("exitCode", result.exitCode)])
            return errorResult("swiftlint version failed:\n\(result.output)")
        }
        TraceLog.exit([("exitCode", result.exitCode)])
        return textResult("SwiftLint \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // MARK: - JSON Violation Parsing

    struct Violation: Sendable {
        let file: String
        let line: Int
        let character: Int
        let severity: String
        let ruleID: String
        let reason: String
    }

    private static func parseJSONViolations(_ output: String) -> [Violation] {
        TraceLog.enter()
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            TraceLog.point("invalid-json")
            return []
        }

        TraceLog.point("entries", [("count", json.count)])
        return json.compactMap { entry -> Violation? in
            guard let file = entry["file"] as? String,
                  let line = entry["line"] as? Int,
                  let severity = entry["severity"] as? String,
                  let ruleID = entry["rule_id"] as? String,
                  let reason = entry["reason"] as? String else {
                TraceLog.point("skip-entry")
                return nil
            }
            let character = entry["character"] as? Int ?? 0
            return Violation(
                file: file, line: line, character: character,
                severity: severity, ruleID: ruleID, reason: reason
            )
        }
    }

    // MARK: - Violation Formatting

    private static func formatViolations(_ violations: [Violation]) -> String {
        TraceLog.enter([("count", violations.count)])
        let errorCount = violations.filter { $0.severity == "error" }.count
        let warningCount = violations.filter { $0.severity == "warning" }.count

        var parts: [String] = []

        var summaryParts: [String] = []
        if errorCount > 0 {
            TraceLog.point("errors", [("errorCount", errorCount)])
            summaryParts.append("\(errorCount) error\(errorCount == 1 ? "" : "s")")
        }
        if warningCount > 0 {
            TraceLog.point("warnings", [("warningCount", warningCount)])
            summaryParts.append("\(warningCount) warning\(warningCount == 1 ? "" : "s")")
        }
        parts.append("Lint: \(summaryParts.joined(separator: ", ")) (\(violations.count) total).")

        let errors = violations.filter { $0.severity == "error" }
        let warnings = violations.filter { $0.severity == "warning" }

        if !errors.isEmpty {
            TraceLog.point("append-errors", [("count", errors.count)])
            parts.append("")
            parts.append("Errors:")
            appendGroupedViolations(errors, to: &parts)
        }

        if !warnings.isEmpty {
            TraceLog.point("append-warnings", [("count", warnings.count)])
            parts.append("")
            parts.append("Warnings:")
            appendGroupedViolations(warnings, to: &parts)
        }

        TraceLog.exit()
        return parts.joined(separator: "\n")
    }

    private static func appendGroupedViolations(_ violations: [Violation], to parts: inout [String]) {
        TraceLog.enter([("count", violations.count)])
        let grouped = Dictionary(grouping: violations, by: { $0.ruleID })
        let ruleOrder = violations.reduce(into: [String]()) { acc, v in
            if !acc.contains(v.ruleID) { acc.append(v.ruleID) }
        }

        TraceLog.point("rules", [("ruleCount", ruleOrder.count)])
        for ruleID in ruleOrder {
            guard let ruleViolations = grouped[ruleID] else {
                TraceLog.point("skip-rule", [("ruleID", ruleID)])
                continue
            }

            if ruleViolations.count == 1 {
                TraceLog.point("single", [("ruleID", ruleID)])
                let v = ruleViolations[0]
                let loc = shortPath(v.file)
                parts.append("  \(loc):\(v.line):\(v.character): [\(ruleID)] \(v.reason)")
            } else {
                TraceLog.point("grouped", [("ruleID", ruleID), ("count", ruleViolations.count)])
                parts.append("  [\(ruleID)] \(ruleViolations[0].reason) (\(ruleViolations.count) occurrences):")
                let fileGrouped = Dictionary(grouping: ruleViolations, by: { $0.file })
                let fileOrder = ruleViolations.reduce(into: [String]()) { acc, v in
                    if !acc.contains(v.file) { acc.append(v.file) }
                }
                for file in fileOrder {
                    guard let fileViolations = fileGrouped[file] else {
                        TraceLog.point("skip-file")
                        continue
                    }
                    let loc = shortPath(file)
                    let lineNumbers = fileViolations.map { String($0.line) }.joined(separator: ", ")
                    parts.append("    \(loc): lines \(lineNumbers)")
                }
            }
        }
        TraceLog.exit()
    }

    // MARK: - Rules Table Parsing

    private static func parseRulesTable(_ output: String) -> String {
        TraceLog.enter()
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 2 else {
            TraceLog.point("too-few-lines", [("count", lines.count)])
            return output
        }

        var enabled: [String] = []
        var disabled: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("|") else { continue }

            let columns = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard columns.count >= 4 else { continue }

            let identifier = columns[0]
            if identifier == "identifier" || identifier.allSatisfy({ $0 == "-" }) { continue }

            let isEnabled = columns.contains("yes")
            let kind = columns.count > 2 ? columns[2] : ""
            let entry = "\(identifier) (\(kind))"

            if isEnabled {
                enabled.append(entry)
            } else {
                disabled.append(entry)
            }
        }

        TraceLog.point("parsed", [("enabled", enabled.count), ("disabled", disabled.count)])
        var parts: [String] = []
        parts.append("Enabled rules (\(enabled.count)):")
        for rule in enabled {
            parts.append("  \(rule)")
        }

        if !disabled.isEmpty {
            TraceLog.point("has-disabled", [("count", disabled.count)])
            parts.append("")
            parts.append("Disabled rules (\(disabled.count)):")
            for rule in disabled {
                parts.append("  \(rule)")
            }
        }

        TraceLog.exit()
        return parts.joined(separator: "\n")
    }

    private static func extractRuleFromTable(_ output: String, identifier: String) -> String? {
        TraceLog.enter([("identifier", identifier)])
        let lines = output.components(separatedBy: "\n")

        var headerColumns: [String]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("|") else { continue }

            let columns = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if columns.first == "identifier" {
                TraceLog.point("header-row")
                headerColumns = columns
                continue
            }

            guard columns.count >= 2 else { continue }
            if columns[0].allSatisfy({ $0 == "-" }) { continue }

            if columns[0] == identifier, let headers = headerColumns {
                TraceLog.point("match", [("identifier", identifier)])
                var parts: [String] = []
                parts.append("Rule: \(identifier)")
                for (i, header) in headers.enumerated() where i < columns.count {
                    if header != "identifier" {
                        parts.append("  \(header): \(columns[i])")
                    }
                }
                TraceLog.exit([("found", true)])
                return parts.joined(separator: "\n")
            }
        }

        TraceLog.exit([("found", false)])
        return nil
    }

    // MARK: - Executable Resolution

    private static func findSwiftLintPath() async -> String? {
        TraceLog.enter()
        let candidates = [
            "/opt/homebrew/bin/swiftlint",
            "/usr/local/bin/swiftlint",
            "/usr/bin/swiftlint",
        ]

        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                TraceLog.exit([("source", "candidate"), ("path", path)])
                return path
            }
        }

        if let result = try? await ShellCommand.runAndTrim("/usr/bin/which", arguments: ["swiftlint"]),
           result.exitCode == 0, !result.output.isEmpty {
            TraceLog.exit([("source", "which"), ("path", result.output)])
            return result.output
        }

        TraceLog.exit([("source", "none")])
        return nil
    }

    // MARK: - Helpers

    private static func runSwiftLint(
        _ arguments: [String],
        workingDirectory: String? = nil,
        overridePath: String? = nil
    ) async throws -> ShellCommand.Result {
        TraceLog.enter([("arguments", String(describing: arguments)), ("workingDirectory", workingDirectory), ("overridePath", overridePath)])
        let swiftlintPath: String
        if let overridePath {
            guard FileManager.default.isExecutableFile(atPath: overridePath) else {
                TraceLog.point("override-not-executable", [("overridePath", overridePath)])
                throw MCPError.invalidParams("swiftlintPath is not executable: \(overridePath)")
            }
            TraceLog.point("override-path", [("overridePath", overridePath)])
            swiftlintPath = overridePath
        } else {
            guard let found = await findSwiftLintPath() else {
                TraceLog.point("not-found")
                throw MCPError.invalidParams(
                    "SwiftLint not found. Install via: brew install swiftlint, or pass swiftlintPath for custom installations."
                )
            }
            swiftlintPath = found
        }
        let result = try await ShellCommand.run(swiftlintPath, arguments: arguments, workingDirectory: workingDirectory)
        TraceLog.exit([("exitCode", result.exitCode)])
        return result
    }

    private static func directoryForPath(_ path: String) -> String {
        TraceLog.enter([("path", path)])
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            TraceLog.exit([("isDir", true)])
            return path
        }
        TraceLog.exit([("isDir", false)])
        return (path as NSString).deletingLastPathComponent
    }

    private static func shortPath(_ path: String) -> String {
        TraceLog.enter([("path", path)])
        let components = path.components(separatedBy: "/")
        if components.count > 3 {
            TraceLog.point("truncated", [("componentCount", components.count)])
            return components.suffix(3).joined(separator: "/")
        }
        return path
    }

    private static func textResult(_ text: String) -> CallTool.Result {
        TraceLog.enter()
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        TraceLog.enter()
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}
