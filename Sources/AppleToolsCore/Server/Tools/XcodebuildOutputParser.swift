import Foundation

/// Shared parser for xcodebuild output. Extracts structured diagnostics, test results,
/// scheme lists, and build settings from raw xcodebuild text output.
enum XcodebuildOutputParser {

    // MARK: - Diagnostic model (reusable across build/archive/analyze)

    struct Diagnostic: Sendable, Equatable {
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

    struct LinkerError: Sendable, Equatable {
        let message: String
    }

    struct BuildResult: Sendable {
        let succeeded: Bool
        let errors: [Diagnostic]
        let warnings: [Diagnostic]
        let notes: [Diagnostic]
        let linkerErrors: [LinkerError]
        let rawOutput: String
    }

    // MARK: - Test model

    enum TestStatus: String, Sendable {
        case passed, failed
    }

    struct TestCase: Sendable {
        let name: String
        let status: TestStatus
        let duration: Double?
        let failureMessage: String?
    }

    struct TestResult: Sendable {
        let succeeded: Bool
        let testCases: [TestCase]
        let totalCount: Int
        let failedCount: Int
        let duration: Double?
        let rawOutput: String
    }

    struct FailureGroup {
        let displayMessage: String
        let tests: [TestCase]
    }

    // MARK: - Scheme list model

    struct ProjectInfo: Sendable {
        let targets: [String]
        let buildConfigurations: [String]
        let schemes: [String]
    }

    // MARK: - Build output parsing

    static func parseBuildOutput(_ output: String, exitCode: Int32) -> BuildResult {
        TraceLog.enter([("outputLength", output.count), ("exitCode", exitCode)])
        var errors: [Diagnostic] = []
        var warnings: [Diagnostic] = []
        var notes: [Diagnostic] = []
        var linkerErrors: [LinkerError] = []

        let lines = output.components(separatedBy: "\n")

        // Pattern: /path/to/File.swift:42:10: error: cannot find 'foo' in scope
        let diagnosticPattern =
            #"^(.+?):(\d+):(\d+): (error|warning|note): (.+)$"#
        let diagnosticRegex = try? NSRegularExpression(pattern: diagnosticPattern, options: .anchorsMatchLines)

        // Standalone error/warning without file location (e.g. clang errors)
        let standaloneErrorPattern = #"^error: (.+)$"#
        let standaloneErrorRegex = try? NSRegularExpression(pattern: standaloneErrorPattern, options: .anchorsMatchLines)

        if let regex = diagnosticRegex {
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
                case .error: errors.append(diagnostic)
                case .warning: warnings.append(diagnostic)
                case .note: notes.append(diagnostic)
                }
            }
        } else {
            TraceLog.point("diagnostic-regex-nil")
        }

        // Parse linker errors
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ld: ") {
                TraceLog.point("linker-ld")
                linkerErrors.append(LinkerError(message: trimmed))
            } else if trimmed.hasPrefix("Undefined symbols for architecture") ||
                        trimmed.hasPrefix("Undefined symbol:") {
                TraceLog.point("linker-undefined")
                linkerErrors.append(LinkerError(message: trimmed))
            }
        }

        // Parse standalone "error:" lines that are not file-located diagnostics
        // (e.g., "error: linker command failed with exit code 1")
        if let regex = standaloneErrorRegex, errors.isEmpty && linkerErrors.isEmpty {
            let nsOutput = output as NSString
            let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))
            TraceLog.point("standalone-error-branch", [("count", matches.count)])
            for match in matches {
                guard match.numberOfRanges == 2 else { continue }
                let message = nsOutput.substring(with: match.range(at: 1))
                // Avoid duplicating file-located errors (those have file:line:col: before "error:")
                linkerErrors.append(LinkerError(message: "error: \(message)"))
            }
        }

        let succeeded = exitCode == 0
        TraceLog.exit([("succeeded", succeeded), ("errors", errors.count), ("warnings", warnings.count), ("linkerErrors", linkerErrors.count)])
        return BuildResult(
            succeeded: succeeded,
            errors: errors,
            warnings: warnings,
            notes: notes,
            linkerErrors: linkerErrors,
            rawOutput: output
        )
    }

    // MARK: - Build result formatting

    static func formatBuildResult(_ result: BuildResult, action: String = "Build") -> String {
        TraceLog.enter([("action", action), ("succeeded", result.succeeded), ("errors", result.errors.count), ("warnings", result.warnings.count), ("linkerErrors", result.linkerErrors.count)])
        var parts: [String] = []

        // Summary line
        if result.succeeded {
            if result.warnings.isEmpty {
                TraceLog.point("succeeded-clean")
                parts.append("\(action) succeeded.")
            } else {
                TraceLog.point("succeeded-with-warnings")
                parts.append("\(action) succeeded with \(result.warnings.count) warning\(result.warnings.count == 1 ? "" : "s").")
            }
        } else {
            TraceLog.point("failed")
            var counts: [String] = []
            let totalErrors = result.errors.count + result.linkerErrors.count
            if totalErrors > 0 {
                counts.append("\(totalErrors) error\(totalErrors == 1 ? "" : "s")")
            }
            if !result.warnings.isEmpty {
                counts.append("\(result.warnings.count) warning\(result.warnings.count == 1 ? "" : "s")")
            }
            if counts.isEmpty {
                parts.append("\(action) failed.")
            } else {
                parts.append("\(action) failed: \(counts.joined(separator: ", ")).")
            }
        }

        // Errors section — group by file
        if !result.errors.isEmpty {
            TraceLog.point("errors-section", [("count", result.errors.count)])
            parts.append("")
            parts.append("Errors:")

            let grouped = Dictionary(grouping: result.errors, by: { $0.file })
            // Sort files for deterministic output; use first-seen order by finding the
            // minimum index of each file in the original array
            let fileOrder = result.errors.reduce(into: [String]()) { acc, diag in
                if !acc.contains(diag.file) { acc.append(diag.file) }
            }

            for file in fileOrder {
                guard let diags = grouped[file] else { continue }
                if fileOrder.count > 1 {
                    parts.append("  \(file):")
                    for diag in diags {
                        parts.append("    line \(diag.line):\(diag.column): \(diag.message)")
                    }
                    // Attach related notes
                    let relatedNotes = result.notes.filter { $0.file == file }
                    for note in relatedNotes {
                        parts.append("    note line \(note.line): \(note.message)")
                    }
                } else {
                    for diag in diags {
                        parts.append("  \(diag.formatted)")
                    }
                    // Attach related notes
                    let relatedNotes = result.notes.filter { $0.file == file }
                    for note in relatedNotes {
                        parts.append("    note: \(note.formatted)")
                    }
                }
            }
        }

        // Linker errors section
        if !result.linkerErrors.isEmpty {
            TraceLog.point("linker-errors-section", [("count", result.linkerErrors.count)])
            parts.append("")
            parts.append("Linker errors:")
            for err in result.linkerErrors {
                parts.append("  \(err.message)")
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

        // Fallback: if failed but we parsed nothing useful, include filtered raw output
        if !result.succeeded && result.errors.isEmpty && result.warnings.isEmpty && result.linkerErrors.isEmpty {
            TraceLog.point("fallback-raw-output")
            let trimmed = trimXcodebuildNoise(result.rawOutput)
            if !trimmed.isEmpty {
                parts.append("")
                parts.append("Raw output:")
                parts.append(trimmed)
            }
        }

        TraceLog.exit([("partCount", parts.count)])
        return parts.joined(separator: "\n")
    }

    // MARK: - Test output parsing

    static func parseTestOutput(_ output: String, exitCode: Int32) -> TestResult {
        TraceLog.enter([("outputLength", output.count), ("exitCode", exitCode)])
        let lines = output.components(separatedBy: "\n")
        var testCases: [TestCase] = []

        // XCTest format:
        // Test Case '-[Module.Class testMethod]' passed (0.003 seconds).
        let xcTestPattern =
            #"Test Case '-\[(.+?) (.+?)\]' (passed|failed) \((\d+\.\d+) seconds\)\."#
        let xcTestRegex = try? NSRegularExpression(pattern: xcTestPattern)

        // Swift Testing format:
        // ✔ Test testFoo() passed after 0.001 seconds.
        let swiftTestingPattern =
            #"[✔✘◆] Test (.+?) (passed|failed) after (\d+\.\d+) seconds\."#
        let swiftTestingRegex = try? NSRegularExpression(pattern: swiftTestingPattern)

        var pendingContextLines: [String] = []
        var isInsideTestCase = false

        TraceLog.point("scan-lines", [("count", lines.count)])
        for line in lines {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            // Detect "started" markers
            let isXCTestStarted = line.contains("Test Case") && line.contains("started")
            let isSwiftTestingStarted = line.contains("◇ Test") && line.contains("started")
            if isXCTestStarted || isSwiftTestingStarted {
                TraceLog.point("test-started")
                pendingContextLines = []
                isInsideTestCase = true
                continue
            }

            // Try XCTest result format
            if let regex = xcTestRegex,
               let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges == 5 {
                TraceLog.point("xctest-result")
                let module = nsLine.substring(with: match.range(at: 1))
                let method = nsLine.substring(with: match.range(at: 2))
                let statusStr = nsLine.substring(with: match.range(at: 3))
                let durationStr = nsLine.substring(with: match.range(at: 4))

                let name = "\(module).\(method)"
                let status: TestStatus = statusStr == "passed" ? .passed : .failed
                let duration = Double(durationStr)

                let failureMsg: String? = (status == .failed && !pendingContextLines.isEmpty)
                    ? pendingContextLines.joined(separator: "\n")
                    : nil

                testCases.append(TestCase(
                    name: name, status: status,
                    duration: duration, failureMessage: failureMsg
                ))

                pendingContextLines = []
                isInsideTestCase = false
                continue
            }

            // Try Swift Testing result format
            if let regex = swiftTestingRegex,
               let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges == 4 {
                TraceLog.point("swifttesting-result")
                let name = nsLine.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let statusStr = nsLine.substring(with: match.range(at: 2))
                let durationStr = nsLine.substring(with: match.range(at: 3))

                let status: TestStatus = statusStr == "passed" ? .passed : .failed
                let duration = Double(durationStr)

                let failureMsg: String? = (status == .failed && !pendingContextLines.isEmpty)
                    ? pendingContextLines.joined(separator: "\n")
                    : nil

                testCases.append(TestCase(
                    name: name, status: status,
                    duration: duration, failureMessage: failureMsg
                ))

                pendingContextLines = []
                isInsideTestCase = false
                continue
            }

            // Collect context lines between "started" and result
            if isInsideTestCase {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty
                    && !trimmed.hasPrefix("Test Suite") {
                    pendingContextLines.append(trimmed)
                }
            }
        }

        // Parse summary: "Executed N test(s), with M failure(s) ... in S (seconds)"
        var totalCount = testCases.count
        var failedCount = testCases.filter { $0.status == .failed }.count
        var totalDuration: Double?
        TraceLog.point("parsed-cases", [("testCases", testCases.count)])

        let summaryPattern = #"Executed (\d+) tests?, with (\d+) failures? .* in (\d+\.\d+) \("#
        if let summaryRegex = try? NSRegularExpression(pattern: summaryPattern) {
            let nsOutput = output as NSString
            let fullRange = NSRange(location: 0, length: nsOutput.length)
            // Use the last match — the overall summary, not a per-suite summary
            let matches = summaryRegex.matches(in: output, range: fullRange)
            if let match = matches.last, match.numberOfRanges >= 4 {
                TraceLog.point("xctest-summary-matched")
                if let t = Int(nsOutput.substring(with: match.range(at: 1))) {
                    totalCount = max(totalCount, t)
                }
                if let f = Int(nsOutput.substring(with: match.range(at: 2))) {
                    failedCount = max(failedCount, f)
                }
                totalDuration = Double(nsOutput.substring(with: match.range(at: 3)))
            }
        }

        // Also try Swift Testing summary
        let stSummaryPattern = #"(\d+) tests? passed"#
        if let stRegex = try? NSRegularExpression(pattern: stSummaryPattern) {
            let nsOutput = output as NSString
            let fullRange = NSRange(location: 0, length: nsOutput.length)
            if let match = stRegex.firstMatch(in: output, range: fullRange),
               match.numberOfRanges >= 2 {
                TraceLog.point("swifttesting-summary-matched")
                let passedCount = Int(nsOutput.substring(with: match.range(at: 1))) ?? 0
                totalCount = max(totalCount, passedCount + failedCount)
            }
        }

        let succeeded = exitCode == 0
        TraceLog.exit([("succeeded", succeeded), ("totalCount", totalCount), ("failedCount", failedCount)])
        return TestResult(
            succeeded: succeeded,
            testCases: testCases,
            totalCount: totalCount,
            failedCount: failedCount,
            duration: totalDuration,
            rawOutput: output
        )
    }

    // MARK: - Test result formatting

    static func formatTestResult(_ result: TestResult) -> String {
        TraceLog.enter([("succeeded", result.succeeded), ("totalCount", result.totalCount), ("failedCount", result.failedCount)])
        var parts: [String] = []

        let passedCount = result.totalCount - result.failedCount
        if result.succeeded {
            TraceLog.point("succeeded")
            var summary = "\(result.totalCount) test\(result.totalCount == 1 ? "" : "s") passed."
            if let d = result.duration {
                summary += " (\(formatDuration(d)))"
            }
            parts.append(summary)
        } else {
            TraceLog.point("failed")
            var summary = "\(passedCount) passed, \(result.failedCount) failed"
            summary += " (\(result.totalCount) total)."
            if let d = result.duration {
                summary += " (\(formatDuration(d)))"
            }
            parts.append(summary)
        }

        // If all passed, keep it short
        if result.succeeded && result.failedCount == 0 {
            TraceLog.exit([("allPassed", true)])
            return parts.joined(separator: "\n")
        }

        // Failed tests with details
        let failures = result.testCases.filter { $0.status == .failed }
        if !failures.isEmpty {
            parts.append("")
            parts.append("Failures:")

            let groups = groupFailuresByMessage(failures)
            let hasAnyGroup = groups.contains { $0.tests.count > 1 }

            if hasAnyGroup {
                TraceLog.point("grouped-failures", [("groupCount", groups.count)])
                for group in groups {
                    let countLabel = group.tests.count == 1 ? "1 test" : "\(group.tests.count) tests"
                    parts.append("")
                    parts.append("\"\(group.displayMessage)\" (\(countLabel)):")
                    for tc in group.tests {
                        var line = "  - \(tc.name)"
                        if let d = tc.duration {
                            line += " (\(formatDuration(d)))"
                        }
                        parts.append(line)
                    }
                }
            } else {
                TraceLog.point("individual-failures", [("count", failures.count)])
                for tc in failures {
                    var line = "  FAIL \(tc.name)"
                    if let d = tc.duration {
                        line += " (\(formatDuration(d)))"
                    }
                    parts.append(line)
                    if let msg = tc.failureMessage, !msg.isEmpty {
                        for detail in msg.components(separatedBy: "\n") {
                            parts.append("    \(detail)")
                        }
                    }
                }
            }
        }

        // Fallback: if tests failed but nothing parsed
        if !result.succeeded && failures.isEmpty && result.testCases.isEmpty {
            TraceLog.point("fallback-raw-output")
            let filtered = stripBuildOutput(result.rawOutput)
            if !filtered.isEmpty {
                parts.append("")
                parts.append("Raw output:")
                parts.append(filtered)
            }
        }

        TraceLog.exit([("partCount", parts.count)])
        return parts.joined(separator: "\n")
    }

    // MARK: - Failure grouping

    static func normalizeFailureMessage(_ message: String?) -> String {
        TraceLog.enter([("message", message)])
        guard let message = message, !message.isEmpty else {
            TraceLog.point("empty-message")
            return "Unknown failure"
        }

        let pathPrefixPattern = #"^/?(?:[^\s:]+/)*[^\s:]+\.\w+:\d+:\s*"#
        let xcTestErrorPattern = #"^error:\s*-\[[^\]]+\]\s*:\s*"#

        let pathRegex = try? NSRegularExpression(pattern: pathPrefixPattern)
        let xcTestErrorRegex = try? NSRegularExpression(pattern: xcTestErrorPattern)

        let lines = message.components(separatedBy: "\n")
        let normalized = lines.map { line -> String in
            var result = line.trimmingCharacters(in: .whitespaces)
            if let regex = pathRegex {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
            if let regex = xcTestErrorRegex {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
            return result.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        let joined = normalized.joined(separator: "\n")
        TraceLog.exit([("resultLength", joined.count)])
        return joined.isEmpty ? "Unknown failure" : joined
    }

    static func groupFailuresByMessage(_ failures: [TestCase]) -> [FailureGroup] {
        TraceLog.enter([("failures", failures.count)])
        var groupOrder: [String] = []
        var groupMap: [String: (displayMessage: String, tests: [TestCase])] = [:]

        for tc in failures {
            let normalized = normalizeFailureMessage(tc.failureMessage)
            if var existing = groupMap[normalized] {
                existing.tests.append(tc)
                groupMap[normalized] = existing
            } else {
                groupOrder.append(normalized)
                groupMap[normalized] = (displayMessage: normalized, tests: [tc])
            }
        }

        let result = groupOrder.compactMap { key -> FailureGroup? in
            guard let entry = groupMap[key] else { return nil }
            return FailureGroup(displayMessage: entry.displayMessage, tests: entry.tests)
        }
        TraceLog.exit([("groupCount", result.count)])
        return result
    }

    // MARK: - Scheme list parsing

    static func parseListOutput(_ output: String) -> ProjectInfo {
        TraceLog.enter([("outputLength", output.count)])
        var targets: [String] = []
        var buildConfigurations: [String] = []
        var schemes: [String] = []

        enum Section {
            case none, targets, buildConfigurations, schemes
        }

        var currentSection: Section = .none

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { continue }

            // Detect section headers
            if trimmed.hasSuffix("Targets:") || trimmed == "Targets:" {
                TraceLog.point("section-targets")
                currentSection = .targets
                continue
            }
            if trimmed.hasSuffix("Build Configurations:") || trimmed == "Build Configurations:" {
                TraceLog.point("section-buildConfigurations")
                currentSection = .buildConfigurations
                continue
            }
            if trimmed.hasSuffix("Schemes:") || trimmed == "Schemes:" {
                TraceLog.point("section-schemes")
                currentSection = .schemes
                continue
            }

            // "If no build configuration..." is a footer line — stop collecting
            if trimmed.hasPrefix("If no build configuration") {
                TraceLog.point("footer-line")
                currentSection = .none
                continue
            }

            // "Information about project" is a header — skip it
            if trimmed.hasPrefix("Information about project") {
                continue
            }

            switch currentSection {
            case .targets:
                targets.append(trimmed)
            case .buildConfigurations:
                buildConfigurations.append(trimmed)
            case .schemes:
                schemes.append(trimmed)
            case .none:
                break
            }
        }

        TraceLog.exit([("targets", targets.count), ("buildConfigurations", buildConfigurations.count), ("schemes", schemes.count)])
        return ProjectInfo(targets: targets, buildConfigurations: buildConfigurations, schemes: schemes)
    }

    static func formatProjectInfo(_ info: ProjectInfo) -> String {
        TraceLog.enter([("schemes", info.schemes.count), ("targets", info.targets.count), ("buildConfigurations", info.buildConfigurations.count)])
        var parts: [String] = []

        if !info.schemes.isEmpty {
            TraceLog.point("schemes-section")
            parts.append("Schemes:")
            for scheme in info.schemes {
                parts.append("  \(scheme)")
            }
        }

        if !info.targets.isEmpty {
            TraceLog.point("targets-section")
            if !parts.isEmpty { parts.append("") }
            parts.append("Targets:")
            for target in info.targets {
                parts.append("  \(target)")
            }
        }

        if !info.buildConfigurations.isEmpty {
            TraceLog.point("buildConfigurations-section")
            if !parts.isEmpty { parts.append("") }
            parts.append("Build Configurations:")
            for config in info.buildConfigurations {
                parts.append("  \(config)")
            }
        }

        if parts.isEmpty {
            TraceLog.point("empty")
            return "No schemes, targets, or build configurations found."
        }

        TraceLog.exit([("partCount", parts.count)])
        return parts.joined(separator: "\n")
    }

    // MARK: - Build settings parsing

    static func parseBuildSettings(_ output: String) -> String {
        TraceLog.enter([("outputLength", output.count)])
        let lines = output.components(separatedBy: "\n")
        var cleaned: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty lines
            if trimmed.isEmpty { continue }
            // Skip "Build settings for action ..." header
            if trimmed.hasPrefix("Build settings for action") { continue }
            // Skip "Build settings from ..." headers
            if trimmed.hasPrefix("Build settings from") { continue }
            cleaned.append(trimmed)
        }

        if cleaned.isEmpty {
            TraceLog.point("empty")
            return "No build settings found."
        }

        TraceLog.exit([("lineCount", cleaned.count)])
        return cleaned.joined(separator: "\n")
    }

    // MARK: - Analyze output parsing

    static func parseAnalyzeOutput(_ output: String, exitCode: Int32) -> BuildResult {
        TraceLog.enter([("outputLength", output.count), ("exitCode", exitCode)])
        // Analyze uses the same diagnostic format as build, plus analyzer-specific warnings
        // that also follow the file:line:col: warning: pattern
        return parseBuildOutput(output, exitCode: exitCode)
    }

    // MARK: - Helpers

    static func formatDuration(_ seconds: Double) -> String {
        TraceLog.enter([("seconds", seconds)])
        if seconds < 1.0 {
            TraceLog.point("sub-second")
            return String(format: "%.3fs", seconds)
        } else if seconds < 60.0 {
            TraceLog.point("sub-minute")
            return String(format: "%.1fs", seconds)
        } else {
            TraceLog.point("minutes")
            let mins = Int(seconds) / 60
            let secs = seconds - Double(mins * 60)
            return String(format: "%dm %.1fs", mins, secs)
        }
    }

    /// Strip noisy xcodebuild progress lines and keep only potentially useful output.
    static func trimXcodebuildNoise(_ output: String) -> String {
        TraceLog.enter([("outputLength", output.count)])
        let noisePatterns: [String] = [
            #"^\s*CompileC "#,
            #"^\s*CompileSwift "#,
            #"^\s*CompileSwiftSources "#,
            #"^\s*Ld "#,
            #"^\s*LinkStoryboards"#,
            #"^\s*ProcessInfoPlistFile"#,
            #"^\s*ProcessProductPackaging"#,
            #"^\s*CodeSign "#,
            #"^\s*CopySwiftLibs"#,
            #"^\s*CpResource "#,
            #"^\s*CreateBuildDirectory"#,
            #"^\s*MkDir "#,
            #"^\s*PBXCp "#,
            #"^\s*Ditto "#,
            #"^\s*Touch "#,
            #"^\s*WriteAuxiliaryFile "#,
            #"^\s*RegisterExecutionPolicyException"#,
            #"^\s*Validate "#,
            #"^\s*PhaseScriptExecution "#,
            #"^\s*SetMode "#,
            #"^\s*SetOwnerAndGroup "#,
            #"^\s*GenerateDSYMFile"#,
            #"^\s*note: "#,
            #"^\s*cd "#,
            #"^\s*/usr/bin/"#,
            #"^\s*export "#,
            #"^\s*$"#,
        ]
        let lines = output.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            return !noisePatterns.contains { pattern in
                line.range(of: pattern, options: .regularExpression) != nil
            }
        }
        let result = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let resultLines = result.components(separatedBy: "\n")
        if resultLines.count > 100 {
            TraceLog.point("capped", [("total", resultLines.count)])
            return resultLines.prefix(100).joined(separator: "\n") + "\n... (\(resultLines.count - 100) more lines)"
        }
        TraceLog.exit([("lineCount", resultLines.count)])
        return result
    }

    /// Strip build/compilation lines from test output — the user asked to test, not to see compilation.
    static func stripBuildOutput(_ output: String) -> String {
        TraceLog.enter([("outputLength", output.count)])
        let lines = output.components(separatedBy: "\n")
        let noisePatterns: [String] = [
            #"^\s*CompileC "#,
            #"^\s*CompileSwift "#,
            #"^\s*CompileSwiftSources "#,
            #"^\s*Ld "#,
            #"^\s*LinkStoryboards"#,
            #"^\s*ProcessInfoPlistFile"#,
            #"^\s*ProcessProductPackaging"#,
            #"^\s*CodeSign "#,
            #"^\s*CopySwiftLibs"#,
            #"^\s*CpResource "#,
            #"^\s*CreateBuildDirectory"#,
            #"^\s*MkDir "#,
            #"^\s*PBXCp "#,
            #"^\s*Ditto "#,
            #"^\s*Touch "#,
            #"^\s*WriteAuxiliaryFile "#,
            #"^\s*RegisterExecutionPolicyException"#,
            #"^\s*Validate "#,
            #"^\s*PhaseScriptExecution "#,
            #"^\s*SetMode "#,
            #"^\s*SetOwnerAndGroup "#,
            #"^\s*GenerateDSYMFile"#,
            #"^\s*Building for "#,
            #"^\s*Compiling "#,
            #"^\s*Linking "#,
            #"^\s*Fetching "#,
            #"^\s*Cloning "#,
            #"^\s*Resolving "#,
            #"^\s*\[\d+/\d+\] "#,
            #"^\s*Build complete!"#,
            #"^\s*note: "#,
            #"^\s*cd "#,
            #"^\s*/usr/bin/"#,
            #"^\s*export "#,
            #"^\s*$"#,
        ]
        let filtered = lines.filter { line in
            return !noisePatterns.contains { pattern in
                line.range(of: pattern, options: .regularExpression) != nil
            }
        }
        let result = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let resultLines = result.components(separatedBy: "\n")
        if resultLines.count > 100 {
            TraceLog.point("capped", [("total", resultLines.count)])
            return resultLines.prefix(100).joined(separator: "\n") + "\n... (\(resultLines.count - 100) more lines)"
        }
        TraceLog.exit([("lineCount", resultLines.count)])
        return result
    }
}
