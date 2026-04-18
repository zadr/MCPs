import Foundation
import MCP

enum SwiftTestTool {
    static let name = "swift_test"

    // MARK: - Test result model

    enum TestStatus: String, Sendable {
        case passed, failed
    }

    struct TestCase: Sendable {
        let name: String
        let status: TestStatus
        let duration: Double?           // seconds
        let failureMessage: String?     // only for failed tests
    }

    struct TestResult: Sendable {
        let succeeded: Bool
        let testCases: [TestCase]
        let totalCount: Int
        let failedCount: Int
        let duration: Double?           // total seconds
        let rawOutput: String
    }

    // MARK: - Handle

    static func handle(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let packagePath = args["packagePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: packagePath")
        }

        var cmdArgs = ["test"]

        if let filter = args["filter"]?.stringValue {
            cmdArgs.append(contentsOf: ["--filter", filter])
        }

        let parallel = args["parallel"]?.boolValue ?? true
        cmdArgs.append(parallel ? "--parallel" : "--no-parallel")

        let result = try await ShellCommand.run(
            "/usr/bin/swift",
            arguments: cmdArgs,
            workingDirectory: packagePath
        )

        let parsed = parseTestOutput(result.output, exitCode: result.exitCode)
        let response = formatTestResult(parsed)
        let isError = !parsed.succeeded

        return .init(
            content: [.text(text: response, annotations: nil, _meta: nil)],
            isError: isError
        )
    }

    // MARK: - Parsing

    static func parseTestOutput(_ output: String, exitCode: Int32) -> TestResult {
        let lines = output.components(separatedBy: "\n")
        var testCases: [TestCase] = []

        // --- XCTest format ---
        // Test Case '-[ModuleTests.ClassName testMethod]' passed (0.003 seconds).
        // Test Case '-[ModuleTests.ClassName testMethod]' failed (0.001 seconds).
        let xcTestPattern =
            #"Test Case '-\[(.+?) (.+?)\]' (passed|failed) \((\d+\.\d+) seconds\)\."#
        let xcTestRegex = try? NSRegularExpression(pattern: xcTestPattern)

        // --- Swift Testing format ---
        // ✔ Test testFoo() passed after 0.001 seconds.
        // ✘ Test testBar() failed after 0.002 seconds.
        // Also handles: ✔ Test "name" passed after 0.001 seconds.
        // Newer Swift Testing (v1743+) uses SF Symbols (e.g. 􁁛) instead of ✔✘◆,
        // so we match any non-whitespace prefix before "Test".
        let swiftTestingPattern =
            #"\S+\s+Test (.+?) (passed|failed) after (\d+\.\d+) seconds\."#
        let swiftTestingRegex = try? NSRegularExpression(pattern: swiftTestingPattern)

        // Collect context lines between "started" and the result line.
        // In XCTest, failure details appear BEFORE the "failed" result line.
        // In Swift Testing, they can appear BEFORE the result line too.
        var pendingContextLines: [String] = []
        var isInsideTestCase = false

        for line in lines {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            // Detect "started" markers — begin collecting context
            let isXCTestStarted = line.contains("Test Case") && line.contains("started")
            // Swift Testing uses "◇ Test" (older) or SF Symbol + "Test" (newer, e.g. "􀟈  Test")
            let isSwiftTestingStarted = line.contains("Test") && line.contains("started")
                && !isXCTestStarted && !line.contains("Test Suite") && !line.contains("Test run")
            if isXCTestStarted || isSwiftTestingStarted {
                pendingContextLines = []
                isInsideTestCase = true
                continue
            }

            // Try XCTest result format
            if let regex = xcTestRegex,
               let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges == 5 {
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

            // Try Swift Testing result format (skip summary lines like "Test run with...")
            if !line.contains("Test run"),
               let regex = swiftTestingRegex,
               let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges == 4 {
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

        // --- Parallel format ---
        // [1/141] Testing Module.Class/testMethod
        // In parallel mode, swift test emits progress lines instead of
        // individual pass/fail results. We extract the total from N/M.
        var parallelTotal = 0
        let parallelPattern = #"\[(\d+)/(\d+)\] Testing (.+)"#
        if let parallelRegex = try? NSRegularExpression(pattern: parallelPattern) {
            for line in lines {
                let nsLine = line as NSString
                let range = NSRange(location: 0, length: nsLine.length)
                if let match = parallelRegex.firstMatch(in: line, range: range),
                   match.numberOfRanges >= 3 {
                    if let total = Int(nsLine.substring(with: match.range(at: 2))) {
                        parallelTotal = max(parallelTotal, total)
                    }
                }
            }
        }

        // Parse summary line: "Executed N test(s), with M failure(s) ... in S (seconds)"
        var totalCount = testCases.count
        var failedCount = testCases.filter { $0.status == .failed }.count
        var totalDuration: Double?

        let summaryPattern = #"Executed (\d+) tests?, with (\d+) failures? .* in (\d+\.\d+) \("#
        if let summaryRegex = try? NSRegularExpression(pattern: summaryPattern) {
            let nsOutput = output as NSString
            let fullRange = NSRange(location: 0, length: nsOutput.length)
            // Use the last match — the overall summary, not a per-suite summary
            let matches = summaryRegex.matches(in: output, range: fullRange)
            if let match = matches.last, match.numberOfRanges >= 4 {
                if let t = Int(nsOutput.substring(with: match.range(at: 1))) {
                    totalCount = max(totalCount, t)
                }
                if let f = Int(nsOutput.substring(with: match.range(at: 2))) {
                    failedCount = max(failedCount, f)
                }
                totalDuration = Double(nsOutput.substring(with: match.range(at: 3)))
            }
        }

        // Also try Swift Testing summary formats:
        //   "N test(s) passed"
        //   "Test run with N test(s) in M suite(s) passed after S seconds."
        let stSummaryPatterns = [
            #"(\d+) tests? passed"#,
            #"Test run with (\d+) tests? in \d+ suites? passed"#,
        ]
        for pattern in stSummaryPatterns {
            if let stRegex = try? NSRegularExpression(pattern: pattern) {
                let nsOutput = output as NSString
                let fullRange = NSRange(location: 0, length: nsOutput.length)
                if let match = stRegex.firstMatch(in: output, range: fullRange),
                   match.numberOfRanges >= 2 {
                    let passedCount = Int(nsOutput.substring(with: match.range(at: 1))) ?? 0
                    totalCount = max(totalCount, passedCount + failedCount)
                }
            }
        }

        // Apply parallel total — this covers the case where --parallel output
        // doesn't include per-test pass/fail lines or XCTest summary lines
        totalCount = max(totalCount, parallelTotal)

        let succeeded = exitCode == 0
        return TestResult(
            succeeded: succeeded,
            testCases: testCases,
            totalCount: totalCount,
            failedCount: failedCount,
            duration: totalDuration,
            rawOutput: output
        )
    }

    // MARK: - Formatting

    static func formatTestResult(_ result: TestResult) -> String {
        var parts: [String] = []

        // Summary line
        let passedCount = result.totalCount - result.failedCount
        if result.succeeded {
            let summary = "\(result.totalCount) test\(result.totalCount == 1 ? "" : "s") passed."
            parts.append(summary)
        } else {
            let summary = "\(passedCount) passed, \(result.failedCount) failed"
                + " (\(result.totalCount) total)."
            parts.append(summary)
        }

        // If all passed, we're done -- keep it short
        if result.succeeded && result.failedCount == 0 {
            return parts.joined(separator: "\n")
        }

        // Failed tests with details
        let failures = result.testCases.filter { $0.status == .failed }
        if !failures.isEmpty {
            parts.append("")
            parts.append("Failures:")

            // Group failures by normalized message
            let groups = groupFailuresByMessage(failures)
            let hasAnyGroup = groups.contains { $0.tests.count > 1 }

            if hasAnyGroup {
                // Grouped format: message as header, tests listed underneath
                for group in groups {
                    let countLabel = group.tests.count == 1 ? "1 test" : "\(group.tests.count) tests"
                    parts.append("")
                    parts.append("\"\(group.displayMessage)\" (\(countLabel)):")
                    for tc in group.tests {
                        parts.append("  - \(tc.name)")
                    }
                }
            } else {
                // Individual format: test name as header, message underneath
                for tc in failures {
                    parts.append("  FAIL \(tc.name)")
                    if let msg = tc.failureMessage, !msg.isEmpty {
                        // Indent failure details
                        for detail in msg.components(separatedBy: "\n") {
                            parts.append("    \(detail)")
                        }
                    }
                }
            }
        }

        // Fallback: if tests failed but we parsed nothing, include filtered raw output
        if !result.succeeded && failures.isEmpty && result.testCases.isEmpty {
            let filtered = stripBuildOutput(result.rawOutput)
            if !filtered.isEmpty {
                parts.append("")
                parts.append("Raw output:")
                parts.append(filtered)
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Failure grouping

    struct FailureGroup {
        let displayMessage: String
        let tests: [TestCase]
    }

    /// Normalize a failure message for grouping purposes.
    /// Strips file path/line number prefixes (e.g., "/path/to/file.swift:42: ")
    /// and trims whitespace so that the same logical assertion from different
    /// test sites gets grouped together.
    static func normalizeFailureMessage(_ message: String?) -> String {
        guard let message = message, !message.isEmpty else {
            return "Unknown failure"
        }

        // A failure message may span multiple lines. We normalize each line
        // and rejoin. The file-path prefix pattern is:
        //   /some/path/File.swift:123: error: -[Module.Class testMethod] : <actual message>
        //   /some/path/File.swift:123: <actual message>
        let pathPrefixPattern = #"^/?(?:[^\s:]+/)*[^\s:]+\.\w+:\d+:\s*"#
        // Also strip the "error: -[Module.Class testMethod] : " part that XCTest emits
        let xcTestErrorPattern = #"^error:\s*-\[[^\]]+\]\s*:\s*"#

        let pathRegex = try? NSRegularExpression(pattern: pathPrefixPattern)
        let xcTestErrorRegex = try? NSRegularExpression(pattern: xcTestErrorPattern)

        let lines = message.components(separatedBy: "\n")
        let normalized = lines.map { line -> String in
            var result = line.trimmingCharacters(in: .whitespaces)
            // Strip file path prefix
            if let regex = pathRegex {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
            // Strip "error: -[...] : " prefix
            if let regex = xcTestErrorRegex {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
            return result.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        let joined = normalized.joined(separator: "\n")
        return joined.isEmpty ? "Unknown failure" : joined
    }

    /// Group failed test cases by their normalized failure message.
    /// Returns groups in order of first appearance, preserving test order within each group.
    static func groupFailuresByMessage(_ failures: [TestCase]) -> [FailureGroup] {
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

        return groupOrder.compactMap { key in
            guard let entry = groupMap[key] else { return nil }
            return FailureGroup(displayMessage: entry.displayMessage, tests: entry.tests)
        }
    }

    // MARK: - Helpers

    private static func formatDuration(_ seconds: Double) -> String {
        if seconds < 1.0 {
            return String(format: "%.3fs", seconds)
        } else if seconds < 60.0 {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = seconds - Double(mins * 60)
            return String(format: "%dm %.1fs", mins, secs)
        }
    }

    /// Strip build/compilation lines that precede actual test execution.
    private static func stripBuildOutput(_ output: String) -> String {
        let lines = output.components(separatedBy: "\n")
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
        let filtered = lines.filter { line in
            !noisePatterns.contains { pattern in
                line.range(of: pattern, options: .regularExpression) != nil
            }
        }
        let result = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let resultLines = result.components(separatedBy: "\n")
        if resultLines.count > 100 {
            return resultLines.prefix(100).joined(separator: "\n") + "\n... (\(resultLines.count - 100) more lines)"
        }
        return result
    }
}
