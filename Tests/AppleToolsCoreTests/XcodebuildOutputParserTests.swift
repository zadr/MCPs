import XCTest
@testable import AppleToolsCore

final class XcodebuildOutputParserTests: XCTestCase {

    // MARK: - parseBuildOutput

    func testCleanBuildSucceeded() {
        let output = """
        CompileSwift normal arm64 /Users/dev/MyApp/Sources/main.swift
            cd /Users/dev/MyApp
            /usr/bin/swiftc ...
        Ld /Users/dev/Build/MyApp normal arm64
        ** BUILD SUCCEEDED **
        """
        let result = XcodebuildOutputParser.parseBuildOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.linkerErrors.isEmpty)
    }

    func testBuildWithErrors() {
        let output = """
        CompileSwift normal arm64 /Users/dev/MyApp/Sources/Foo.swift
        /Users/dev/MyApp/Sources/Foo.swift:42:10: error: cannot find 'bar' in scope
        /Users/dev/MyApp/Sources/Foo.swift:43:5: error: missing return in global function expected to return 'Int'
        ** BUILD FAILED **
        """
        let result = XcodebuildOutputParser.parseBuildOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertTrue(result.warnings.isEmpty)

        XCTAssertEqual(result.errors[0].file, "/Users/dev/MyApp/Sources/Foo.swift")
        XCTAssertEqual(result.errors[0].line, 42)
        XCTAssertEqual(result.errors[0].column, 10)
        XCTAssertEqual(result.errors[0].message, "cannot find 'bar' in scope")

        XCTAssertEqual(result.errors[1].line, 43)
        XCTAssertEqual(result.errors[1].column, 5)
    }

    func testBuildWithWarnings() {
        let output = """
        /Users/dev/MyApp/Sources/Foo.swift:15:5: warning: variable 'x' was never used
        /Users/dev/MyApp/Sources/Bar.swift:30:12: warning: expression implicitly coerced from 'Int?' to 'Any'
        ** BUILD SUCCEEDED **
        """
        let result = XcodebuildOutputParser.parseBuildOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertEqual(result.warnings[0].file, "/Users/dev/MyApp/Sources/Foo.swift")
        XCTAssertEqual(result.warnings[0].message, "variable 'x' was never used")
        XCTAssertEqual(result.warnings[1].file, "/Users/dev/MyApp/Sources/Bar.swift")
    }

    func testBuildWithNotes() {
        let output = """
        /Users/dev/MyApp/Sources/Foo.swift:42:10: error: cannot find 'bar' in scope
        /Users/dev/MyApp/Sources/Foo.swift:40:5: note: did you mean 'baz'?
        ** BUILD FAILED **
        """
        let result = XcodebuildOutputParser.parseBuildOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].message, "did you mean 'baz'?")
    }

    func testBuildWithLinkerErrors() {
        let output = """
        ld: library 'sqlite3' not found
        Undefined symbols for architecture arm64:
          "_OBJC_CLASS_$_SomeClass", referenced from:
              some_function in SomeFile.o
        ** BUILD FAILED **
        """
        let result = XcodebuildOutputParser.parseBuildOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.linkerErrors.count, 2)
        XCTAssertEqual(result.linkerErrors[0].message, "ld: library 'sqlite3' not found")
        XCTAssertTrue(result.linkerErrors[1].message.contains("Undefined symbols"))
    }

    func testBuildWithUndefinedSymbol() {
        let output = """
        Undefined symbol: _some_function
        ld: linker command failed with exit code 1
        ** BUILD FAILED **
        """
        let result = XcodebuildOutputParser.parseBuildOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.linkerErrors.count, 2)
        XCTAssertTrue(result.linkerErrors[0].message.contains("Undefined symbol"))
    }

    func testBuildMixedDiagnostics() {
        let output = """
        /path/A.swift:1:1: error: something broke
        /path/A.swift:2:1: warning: this is fishy
        /path/A.swift:3:1: note: see here
        /path/B.swift:10:5: error: another issue
        /path/B.swift:11:5: warning: also fishy
        """
        let result = XcodebuildOutputParser.parseBuildOutput(output, exitCode: 1)

        XCTAssertEqual(result.errors.count, 2)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertEqual(result.notes.count, 1)
    }

    // MARK: - formatBuildResult

    func testFormatCleanBuild() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: true, errors: [], warnings: [], notes: [], linkerErrors: [], rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result)
        XCTAssertEqual(formatted, "Build succeeded.")
    }

    func testFormatBuildWithCustomAction() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: true, errors: [], warnings: [], notes: [], linkerErrors: [], rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result, action: "Archive")
        XCTAssertEqual(formatted, "Archive succeeded.")
    }

    func testFormatBuildWithWarningsOnly() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: true,
            errors: [],
            warnings: [
                .init(file: "/path/A.swift", line: 1, column: 1, severity: .warning, message: "unused var")
            ],
            notes: [],
            linkerErrors: [],
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result)
        XCTAssertTrue(formatted.contains("Build succeeded with 1 warning."))
        XCTAssertTrue(formatted.contains("Warnings:"))
        XCTAssertTrue(formatted.contains("unused var"))
    }

    func testFormatBuildFailedWithErrors() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: false,
            errors: [
                .init(file: "/path/A.swift", line: 10, column: 5, severity: .error, message: "type mismatch"),
                .init(file: "/path/B.swift", line: 20, column: 3, severity: .error, message: "undeclared"),
            ],
            warnings: [
                .init(file: "/path/A.swift", line: 5, column: 1, severity: .warning, message: "unused")
            ],
            notes: [],
            linkerErrors: [],
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result)
        XCTAssertTrue(formatted.hasPrefix("Build failed: 2 errors, 1 warning."))
        XCTAssertTrue(formatted.contains("Errors:"))
        XCTAssertTrue(formatted.contains("type mismatch"))
        XCTAssertTrue(formatted.contains("Warnings:"))
    }

    func testFormatBuildFailedWithLinkerErrors() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: false,
            errors: [],
            warnings: [],
            notes: [],
            linkerErrors: [
                .init(message: "ld: library 'sqlite3' not found"),
                .init(message: "Undefined symbols for architecture arm64"),
            ],
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result)
        XCTAssertTrue(formatted.contains("Build failed: 2 errors."))
        XCTAssertTrue(formatted.contains("Linker errors:"))
        XCTAssertTrue(formatted.contains("library 'sqlite3' not found"))
    }

    func testFormatBuildFailedFallbackRawOutput() {
        let rawOutput = "some unexpected error output"
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: false, errors: [], warnings: [], notes: [], linkerErrors: [], rawOutput: rawOutput
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result)
        XCTAssertTrue(formatted.contains("Build failed."))
        XCTAssertTrue(formatted.contains("Raw output:"))
        XCTAssertTrue(formatted.contains("some unexpected error output"))
    }

    func testFormatSingularCounts() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: false,
            errors: [
                .init(file: "/path/A.swift", line: 1, column: 1, severity: .error, message: "oops")
            ],
            warnings: [],
            notes: [],
            linkerErrors: [],
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result)
        XCTAssertTrue(formatted.contains("1 error"))
        XCTAssertFalse(formatted.contains("1 errors"))
    }

    func testFormatErrorsGroupedByFile() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: false,
            errors: [
                .init(file: "/path/A.swift", line: 10, column: 5, severity: .error, message: "type mismatch"),
                .init(file: "/path/A.swift", line: 20, column: 3, severity: .error, message: "undeclared"),
                .init(file: "/path/B.swift", line: 5, column: 1, severity: .error, message: "other error"),
            ],
            warnings: [],
            notes: [],
            linkerErrors: [],
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result)
        // Multiple files should show file headers
        XCTAssertTrue(formatted.contains("/path/A.swift:"))
        XCTAssertTrue(formatted.contains("/path/B.swift:"))
        XCTAssertTrue(formatted.contains("line 10:5: type mismatch"))
        XCTAssertTrue(formatted.contains("line 20:3: undeclared"))
    }

    func testFormatAnalyzeSucceeded() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: true, errors: [], warnings: [], notes: [], linkerErrors: [], rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result, action: "Analyze")
        XCTAssertEqual(formatted, "Analyze succeeded.")
    }

    func testFormatAnalyzeWithWarnings() {
        let result = XcodebuildOutputParser.BuildResult(
            succeeded: true,
            errors: [],
            warnings: [
                .init(file: "/path/A.swift", line: 10, column: 5, severity: .warning, message: "Dereference of null pointer")
            ],
            notes: [],
            linkerErrors: [],
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatBuildResult(result, action: "Analyze")
        XCTAssertTrue(formatted.contains("Analyze succeeded with 1 warning."))
        XCTAssertTrue(formatted.contains("Dereference of null pointer"))
    }

    // MARK: - parseTestOutput

    func testXCTestAllPassed() {
        let output = """
        CompileSwift normal arm64 /Users/dev/MyApp/Tests/FooTests.swift
            cd /Users/dev/MyApp
        Test Suite 'All tests' started at 2026-01-01 00:00:00.000.
        Test Suite 'MyTests.xctest' started at 2026-01-01 00:00:00.001.
        Test Suite 'FooTests' started at 2026-01-01 00:00:00.002.
        Test Case '-[MyTests.FooTests testAlpha]' started.
        Test Case '-[MyTests.FooTests testAlpha]' passed (0.003 seconds).
        Test Case '-[MyTests.FooTests testBeta]' started.
        Test Case '-[MyTests.FooTests testBeta]' passed (0.001 seconds).
        Test Suite 'FooTests' passed at 2026-01-01 00:00:00.010.
        \t Executed 2 tests, with 0 failures (0 unexpected) in 0.004 (0.008) seconds
        Test Suite 'All tests' passed at 2026-01-01 00:00:00.012.
        \t Executed 2 tests, with 0 failures (0 unexpected) in 0.004 (0.012) seconds
        """
        let result = XcodebuildOutputParser.parseTestOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.testCases.count, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(result.testCases.allSatisfy { $0.status == .passed })
        XCTAssertEqual(result.testCases[0].name, "MyTests.FooTests.testAlpha")
        XCTAssertEqual(result.testCases[1].name, "MyTests.FooTests.testBeta")
        XCTAssertEqual(result.testCases[0].duration, 0.003)
    }

    func testXCTestWithFailures() {
        let output = """
        Test Case '-[MyTests.FooTests testGood]' started.
        Test Case '-[MyTests.FooTests testGood]' passed (0.002 seconds).
        Test Case '-[MyTests.FooTests testBad]' started.
        /Users/dev/Tests/FooTests.swift:25: error: -[MyTests.FooTests testBad] : XCTAssertEqual failed: ("1") is not equal to ("2")
        Test Case '-[MyTests.FooTests testBad]' failed (0.001 seconds).
        \t Executed 2 tests, with 1 failures (1 unexpected) in 0.003 (0.012) seconds
        """
        let result = XcodebuildOutputParser.parseTestOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.testCases.count, 2)
        XCTAssertEqual(result.failedCount, 1)

        let failed = result.testCases.filter { $0.status == .failed }
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].name, "MyTests.FooTests.testBad")
        XCTAssertNotNil(failed[0].failureMessage)
        XCTAssertTrue(failed[0].failureMessage?.contains("XCTAssertEqual failed") ?? false)
    }

    func testTestSummaryLineParsing() {
        let output = """
        Test Case '-[A.B testC]' passed (0.001 seconds).
        \t Executed 42 tests, with 3 failures (2 unexpected) in 1.234 (1.500) seconds
        """
        let result = XcodebuildOutputParser.parseTestOutput(output, exitCode: 1)

        XCTAssertEqual(result.totalCount, 42)
        XCTAssertEqual(result.failedCount, 3)
        XCTAssertEqual(result.duration, 1.234)
    }

    func testXCTestSummaryUsesLastMatch() {
        // When multiple "Executed N tests" lines exist (per-suite + overall),
        // the parser should use the last (overall) match.
        let output = """
        Test Case '-[A.B testC]' passed (0.001 seconds).
        Test Case '-[A.B testD]' passed (0.001 seconds).
        \t Executed 2 tests, with 0 failures (0 unexpected) in 0.002 (0.004) seconds
        Test Case '-[X.Y testE]' passed (0.001 seconds).
        \t Executed 1 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
        \t Executed 3 tests, with 0 failures (0 unexpected) in 0.003 (0.006) seconds
        """
        let result = XcodebuildOutputParser.parseTestOutput(output, exitCode: 0)

        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.duration, 0.003)
    }

    // MARK: - formatTestResult

    func testFormatAllTestsPassed() {
        let result = XcodebuildOutputParser.TestResult(
            succeeded: true,
            testCases: [
                .init(name: "testA", status: .passed, duration: 0.001, failureMessage: nil),
                .init(name: "testB", status: .passed, duration: 0.002, failureMessage: nil),
            ],
            totalCount: 2,
            failedCount: 0,
            duration: 0.003,
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatTestResult(result)

        XCTAssertTrue(formatted.contains("2 tests passed."))
        XCTAssertFalse(formatted.contains("Failures:"))
    }

    func testFormatTestWithFailures() {
        let result = XcodebuildOutputParser.TestResult(
            succeeded: false,
            testCases: [
                .init(name: "testGood", status: .passed, duration: 0.001, failureMessage: nil),
                .init(name: "testBad", status: .failed, duration: 0.002,
                      failureMessage: "XCTAssertEqual failed: (1) is not equal to (2)"),
            ],
            totalCount: 2,
            failedCount: 1,
            duration: 0.003,
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatTestResult(result)

        XCTAssertTrue(formatted.contains("1 passed, 1 failed"))
        XCTAssertTrue(formatted.contains("Failures:"))
        XCTAssertTrue(formatted.contains("FAIL testBad"))
        XCTAssertTrue(formatted.contains("XCTAssertEqual failed"))
    }

    func testFormatTestFallbackWhenNothingParsed() {
        let result = XcodebuildOutputParser.TestResult(
            succeeded: false,
            testCases: [],
            totalCount: 0,
            failedCount: 0,
            duration: nil,
            rawOutput: "error: no tests were run\nSome other error details"
        )
        let formatted = XcodebuildOutputParser.formatTestResult(result)

        XCTAssertTrue(formatted.contains("Raw output:"))
        XCTAssertTrue(formatted.contains("no tests were run"))
    }

    func testFormatGroupedTestFailures() {
        let result = XcodebuildOutputParser.TestResult(
            succeeded: false,
            testCases: [
                .init(name: "FooTests.testBar", status: .failed, duration: 0.001,
                      failureMessage: "XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "FooTests.testBaz", status: .failed, duration: 0.002,
                      failureMessage: "XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "BarTests.testOne", status: .failed, duration: 0.003,
                      failureMessage: "Expected true but got false"),
            ],
            totalCount: 10,
            failedCount: 3,
            duration: 1.0,
            rawOutput: ""
        )
        let formatted = XcodebuildOutputParser.formatTestResult(result)

        XCTAssertTrue(formatted.contains("Failures:"))
        XCTAssertTrue(formatted.contains("\"XCTAssertEqual failed: (nil) is not equal to (Optional(42))\" (2 tests):"))
        XCTAssertTrue(formatted.contains("  - FooTests.testBar (0.001s)"))
        XCTAssertTrue(formatted.contains("  - FooTests.testBaz (0.002s)"))
        XCTAssertTrue(formatted.contains("\"Expected true but got false\" (1 test):"))
    }

    // MARK: - parseListOutput

    func testParseListOutput() {
        let output = """
        Information about project "MyApp":
            Targets:
                MyApp
                MyAppTests
                MyAppUITests

            Build Configurations:
                Debug
                Release

            If no build configuration is specified and -scheme is not passed then "Release" is used.

            Schemes:
                MyApp
                MyApp-Debug
        """
        let info = XcodebuildOutputParser.parseListOutput(output)

        XCTAssertEqual(info.targets, ["MyApp", "MyAppTests", "MyAppUITests"])
        XCTAssertEqual(info.buildConfigurations, ["Debug", "Release"])
        XCTAssertEqual(info.schemes, ["MyApp", "MyApp-Debug"])
    }

    func testParseListOutputSchemesOnly() {
        let output = """
        Information about project "Foo":
            Schemes:
                FooScheme
        """
        let info = XcodebuildOutputParser.parseListOutput(output)

        XCTAssertTrue(info.targets.isEmpty)
        XCTAssertTrue(info.buildConfigurations.isEmpty)
        XCTAssertEqual(info.schemes, ["FooScheme"])
    }

    func testFormatProjectInfo() {
        let info = XcodebuildOutputParser.ProjectInfo(
            targets: ["MyApp", "MyAppTests"],
            buildConfigurations: ["Debug", "Release"],
            schemes: ["MyApp"]
        )
        let formatted = XcodebuildOutputParser.formatProjectInfo(info)

        XCTAssertTrue(formatted.contains("Schemes:"))
        XCTAssertTrue(formatted.contains("  MyApp"))
        XCTAssertTrue(formatted.contains("Targets:"))
        XCTAssertTrue(formatted.contains("  MyAppTests"))
        XCTAssertTrue(formatted.contains("Build Configurations:"))
        XCTAssertTrue(formatted.contains("  Debug"))
    }

    func testFormatProjectInfoEmpty() {
        let info = XcodebuildOutputParser.ProjectInfo(targets: [], buildConfigurations: [], schemes: [])
        let formatted = XcodebuildOutputParser.formatProjectInfo(info)
        XCTAssertEqual(formatted, "No schemes, targets, or build configurations found.")
    }

    // MARK: - parseBuildSettings

    func testParseBuildSettings() {
        let output = """
        Build settings for action build and target MyApp:
            ACTION = build
            AD_HOC_CODE_SIGNING_ALLOWED = YES
            ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = NO

            ARCHS = arm64
            BUILD_DIR = /Users/dev/Build
        """
        let cleaned = XcodebuildOutputParser.parseBuildSettings(output)

        // Should not contain the header
        XCTAssertFalse(cleaned.contains("Build settings for action"))
        // Should not contain empty lines
        XCTAssertFalse(cleaned.contains("\n\n"))
        // Should contain trimmed key=value pairs
        XCTAssertTrue(cleaned.contains("ACTION = build"))
        XCTAssertTrue(cleaned.contains("ARCHS = arm64"))
        XCTAssertTrue(cleaned.contains("BUILD_DIR = /Users/dev/Build"))
    }

    func testParseBuildSettingsEmpty() {
        let cleaned = XcodebuildOutputParser.parseBuildSettings("")
        XCTAssertEqual(cleaned, "No build settings found.")
    }

    // MARK: - normalizeFailureMessage

    func testNormalizeStripsFilePathPrefix() {
        let msg = "/Users/dev/Tests/FooTests.swift:25: XCTAssertEqual failed: (1) is not equal to (2)"
        let normalized = XcodebuildOutputParser.normalizeFailureMessage(msg)
        XCTAssertEqual(normalized, "XCTAssertEqual failed: (1) is not equal to (2)")
    }

    func testNormalizeStripsXCTestErrorPrefix() {
        let msg = "/Users/dev/Tests/FooTests.swift:25: error: -[MyTests.FooTests testBad] : XCTAssertEqual failed: (1) is not equal to (2)"
        let normalized = XcodebuildOutputParser.normalizeFailureMessage(msg)
        XCTAssertEqual(normalized, "XCTAssertEqual failed: (1) is not equal to (2)")
    }

    func testNormalizeNilReturnsUnknown() {
        XCTAssertEqual(XcodebuildOutputParser.normalizeFailureMessage(nil), "Unknown failure")
    }

    func testNormalizeEmptyReturnsUnknown() {
        XCTAssertEqual(XcodebuildOutputParser.normalizeFailureMessage(""), "Unknown failure")
    }

    // MARK: - groupFailuresByMessage

    func testGroupFailuresByMessageGroupsSameMessages() {
        let failures: [XcodebuildOutputParser.TestCase] = [
            .init(name: "testA", status: .failed, duration: 0.001, failureMessage: "same error"),
            .init(name: "testB", status: .failed, duration: 0.002, failureMessage: "same error"),
            .init(name: "testC", status: .failed, duration: 0.003, failureMessage: "different error"),
        ]
        let groups = XcodebuildOutputParser.groupFailuresByMessage(failures)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].displayMessage, "same error")
        XCTAssertEqual(groups[0].tests.count, 2)
        XCTAssertEqual(groups[1].displayMessage, "different error")
        XCTAssertEqual(groups[1].tests.count, 1)
    }

    // MARK: - trimXcodebuildNoise

    func testTrimXcodebuildNoise() {
        let output = """
        CompileSwift normal arm64 /Users/dev/Foo.swift
            cd /Users/dev/MyApp
            /usr/bin/swiftc -module-name MyApp
        Ld /Users/dev/Build/MyApp normal arm64
        /Users/dev/Foo.swift:10:5: error: type mismatch
        ** BUILD FAILED **
        """
        let trimmed = XcodebuildOutputParser.trimXcodebuildNoise(output)

        // Should keep the error line and BUILD FAILED
        XCTAssertTrue(trimmed.contains("error: type mismatch"))
        XCTAssertTrue(trimmed.contains("BUILD FAILED"))
        // Should strip compile/link noise
        XCTAssertFalse(trimmed.contains("CompileSwift"))
        XCTAssertFalse(trimmed.contains("cd /Users"))
        XCTAssertFalse(trimmed.contains("/usr/bin/swiftc"))
    }

    // MARK: - formatDuration

    func testFormatDurationSubSecond() {
        XCTAssertEqual(XcodebuildOutputParser.formatDuration(0.003), "0.003s")
    }

    func testFormatDurationSeconds() {
        XCTAssertEqual(XcodebuildOutputParser.formatDuration(5.5), "5.5s")
    }

    func testFormatDurationMinutes() {
        XCTAssertEqual(XcodebuildOutputParser.formatDuration(125.3), "2m 5.3s")
    }
}
