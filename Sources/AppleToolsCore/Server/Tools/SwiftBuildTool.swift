import Foundation
import MCP

enum SwiftBuildTool {
    static let name = "swift_build"

    // MARK: - Diagnostic model

    struct Diagnostic: Sendable {
        enum Severity: String, Sendable {
            case error, warning, note
        }

        let file: String
        let line: Int
        let column: Int
        let severity: Severity
        let message: String

        var formatted: String {
            "\(file):\(line):\(column): \(message)"
        }
    }

    struct BuildResult: Sendable {
        let succeeded: Bool
        let errors: [Diagnostic]
        let warnings: [Diagnostic]
        let notes: [Diagnostic]
        let rawOutput: String
    }

    // MARK: - Handle

    static func handle(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        TraceLog.enter([("arguments", String(describing: arguments))])
        guard let args = arguments,
              let packagePath = args["packagePath"]?.stringValue else {
            TraceLog.point("missing-packagePath")
            throw MCPError.invalidParams("Missing required argument: packagePath")
        }

        guard let timeoutSeconds = args["timeoutSeconds"]?.intValue
            ?? args["timeoutSeconds"]?.doubleValue.map({ Int($0) }) else {
            TraceLog.point("missing-timeoutSeconds")
            throw MCPError.invalidParams("Missing required argument: timeoutSeconds (integer, seconds)")
        }
        guard timeoutSeconds > 0 else {
            TraceLog.point("timeout-nonpositive", [("timeoutSeconds", timeoutSeconds)])
            throw MCPError.invalidParams("timeoutSeconds must be > 0")
        }

        let configuration = args["configuration"]?.stringValue ?? "debug"
        guard configuration == "debug" || configuration == "release" else {
            TraceLog.point("bad-configuration", [("configuration", configuration)])
            throw MCPError.invalidParams("configuration must be \"debug\" or \"release\"")
        }

        var cmdArgs = ["build", "-c", configuration]

        if let target = args["target"]?.stringValue {
            TraceLog.point("target-set", [("target", target)])
            cmdArgs.append(contentsOf: ["--target", target])
        }

        TraceLog.point("running", [("packagePath", packagePath), ("timeoutSeconds", timeoutSeconds), ("cmdArgs", String(describing: cmdArgs))])
        do {
            let result = try await ShellCommand.run(
                Toolchain.swiftPath,
                arguments: cmdArgs,
                workingDirectory: packagePath,
                timeout: TimeInterval(timeoutSeconds)
            )

            let parsed = parseBuildOutput(result.output, exitCode: result.exitCode)
            let response = formatBuildResult(parsed)
            let isError = !parsed.succeeded

            TraceLog.exit([("exitCode", result.exitCode), ("isError", isError)])
            return .init(
                content: [.text(text: response, annotations: nil, _meta: nil)],
                isError: isError
            )
        } catch let error as AppleToolsError {
            if case .processTimedOut(let reason) = error {
                TraceLog.point("process-timed-out", [("reason", reason)])
                return .init(
                    content: [.text(text: "Build timed out: \(reason)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            TraceLog.point("throwing", [("error", String(describing: error))])
            throw error
        }
    }

    // MARK: - Parsing

    static func parseBuildOutput(_ output: String, exitCode: Int32) -> BuildResult {
        TraceLog.enter([("outputLength", output.count), ("exitCode", exitCode)])
        var errors: [Diagnostic] = []
        var warnings: [Diagnostic] = []
        var notes: [Diagnostic] = []

        // Pattern: /path/to/File.swift:42:10: error: cannot find 'foo' in scope
        // Also handles paths with spaces by using a non-greedy match up to :\d+:\d+:
        let diagnosticPattern =
            #"^(.+?):(\d+):(\d+): (error|warning|note): (.+)$"#

        let regex = try? NSRegularExpression(pattern: diagnosticPattern, options: .anchorsMatchLines)

        if let regex {
            let nsOutput = output as NSString
            let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))
            TraceLog.point("diagnostic-matches", [("count", matches.count)])

            for match in matches {
                guard match.numberOfRanges == 6 else {
                    TraceLog.point("match-bad-ranges")
                    continue
                }

                let file = nsOutput.substring(with: match.range(at: 1))
                let lineStr = nsOutput.substring(with: match.range(at: 2))
                let colStr = nsOutput.substring(with: match.range(at: 3))
                let severityStr = nsOutput.substring(with: match.range(at: 4))
                let message = nsOutput.substring(with: match.range(at: 5))

                guard let line = Int(lineStr),
                      let column = Int(colStr),
                      let severity = Diagnostic.Severity(rawValue: severityStr) else {
                    TraceLog.point("match-parse-failed")
                    continue
                }

                let diagnostic = Diagnostic(
                    file: file, line: line, column: column,
                    severity: severity, message: message
                )

                switch severity {
                case .error:
                    TraceLog.point("case-error")
                    errors.append(diagnostic)
                case .warning:
                    TraceLog.point("case-warning")
                    warnings.append(diagnostic)
                case .note:
                    TraceLog.point("case-note")
                    notes.append(diagnostic)
                }
            }
        } else {
            TraceLog.point("regex-nil")
        }

        let succeeded = exitCode == 0
        TraceLog.exit([("succeeded", succeeded), ("errors", errors.count), ("warnings", warnings.count), ("notes", notes.count)])
        return BuildResult(
            succeeded: succeeded,
            errors: errors,
            warnings: warnings,
            notes: notes,
            rawOutput: output
        )
    }

    // MARK: - Formatting

    static func formatBuildResult(_ result: BuildResult) -> String {
        TraceLog.enter([("succeeded", result.succeeded), ("errors", result.errors.count), ("warnings", result.warnings.count)])
        var parts: [String] = []

        // Summary line
        if result.succeeded {
            if result.warnings.isEmpty {
                TraceLog.point("succeeded-clean")
                parts.append("Build succeeded.")
            } else {
                TraceLog.point("succeeded-with-warnings")
                parts.append("Build succeeded with \(result.warnings.count) warning\(result.warnings.count == 1 ? "" : "s").")
            }
        } else {
            TraceLog.point("failed")
            var counts: [String] = []
            if !result.errors.isEmpty {
                counts.append("\(result.errors.count) error\(result.errors.count == 1 ? "" : "s")")
            }
            if !result.warnings.isEmpty {
                counts.append("\(result.warnings.count) warning\(result.warnings.count == 1 ? "" : "s")")
            }
            if counts.isEmpty {
                parts.append("Build failed.")
            } else {
                parts.append("Build failed: \(counts.joined(separator: ", ")).")
            }
        }

        // Errors section
        if !result.errors.isEmpty {
            TraceLog.point("errors-section", [("count", result.errors.count)])
            parts.append("")
            parts.append("Errors:")
            for diag in result.errors {
                parts.append("  \(diag.formatted)")
            }
            // Attach related notes immediately after errors
            let notesByContext = notesGroupedByProximity(
                notes: result.notes, relativeTo: result.errors
            )
            for (_, contextNotes) in notesByContext where !contextNotes.isEmpty {
                for note in contextNotes {
                    parts.append("    note: \(note.formatted)")
                }
            }
        }

        // Warnings section
        if !result.warnings.isEmpty {
            TraceLog.point("warnings-section", [("count", result.warnings.count)])
            parts.append("")
            parts.append("Warnings:")
            for diag in result.warnings {
                parts.append("  \(diag.formatted)")
            }
        }

        // Fallback: if build failed but we parsed nothing useful, include raw output
        if !result.succeeded && result.errors.isEmpty && result.warnings.isEmpty {
            TraceLog.point("fallback-raw-output")
            let trimmed = trimBuildNoise(result.rawOutput)
            if !trimmed.isEmpty {
                parts.append("")
                parts.append("Raw output:")
                parts.append(trimmed)
            }
        }

        TraceLog.exit([("partCount", parts.count)])
        return parts.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Group notes by proximity to error diagnostics (same file, nearby lines).
    /// Returns an array of (errorIndex, [notes]) pairs.
    private static func notesGroupedByProximity(
        notes: [Diagnostic],
        relativeTo errors: [Diagnostic]
    ) -> [(Int, [Diagnostic])] {
        TraceLog.enter([("notes", notes.count), ("errors", errors.count)])
        guard !notes.isEmpty, !errors.isEmpty else {
            TraceLog.point("empty")
            return []
        }

        var result: [(Int, [Diagnostic])] = []
        var usedNotes = Set<Int>()

        for (errorIdx, error) in errors.enumerated() {
            var contextNotes: [Diagnostic] = []
            for (noteIdx, note) in notes.enumerated() where !usedNotes.contains(noteIdx) {
                if note.file == error.file && abs(note.line - error.line) <= 10 {
                    contextNotes.append(note)
                    usedNotes.insert(noteIdx)
                }
            }
            if !contextNotes.isEmpty {
                result.append((errorIdx, contextNotes))
            }
        }

        TraceLog.exit([("groupCount", result.count)])
        return result
    }

    /// Strip noisy build-progress lines (Compiling, Linking, Fetching, etc.)
    /// and keep only potentially useful output.
    private static func trimBuildNoise(_ output: String) -> String {
        TraceLog.enter([("outputLength", output.count)])
        let noisePatterns: [String] = [
            "^Building for ",
            "^Compiling ",
            "^Linking ",
            "^Fetching ",
            "^Cloning ",
            "^Resolving ",
            "^\\[\\d+/\\d+\\] ",
            "^Build complete!",
            "^\\s*$",
        ]
        let lines = output.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            !noisePatterns.contains { pattern in
                line.range(of: pattern, options: .regularExpression) != nil
            }
        }
        let result = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap at 100 lines to avoid massive output
        let resultLines = result.components(separatedBy: "\n")
        if resultLines.count > 100 {
            TraceLog.point("capped", [("total", resultLines.count)])
            return resultLines.prefix(100).joined(separator: "\n") + "\n... (\(resultLines.count - 100) more lines)"
        }
        TraceLog.exit([("lineCount", resultLines.count)])
        return result
    }
}
