import XCTest
@testable import AppleToolsCore

final class SwiftTestToolTests: XCTestCase {

    // MARK: - parseTestOutput: XCTest format

    func testXCTestAllPassed() {
        let output = """
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
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.testCases.count, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(result.testCases.allSatisfy { $0.status == .passed })

        // Check names
        XCTAssertEqual(result.testCases[0].name, "MyTests.FooTests.testAlpha")
        XCTAssertEqual(result.testCases[1].name, "MyTests.FooTests.testBeta")

        // Check durations
        XCTAssertEqual(result.testCases[0].duration, 0.003)
    }

    func testXCTestWithFailures() {
        let output = """
        Test Case '-[MyTests.FooTests testGood]' started.
        Test Case '-[MyTests.FooTests testGood]' passed (0.002 seconds).
        Test Case '-[MyTests.FooTests testBad]' started.
        /Users/dev/Tests/FooTests.swift:25: error: -[MyTests.FooTests testBad] : XCTAssertEqual failed: ("1") is not equal to ("2")
        Test Case '-[MyTests.FooTests testBad]' failed (0.001 seconds).
        Test Suite 'All tests' passed at 2026-01-01 00:00:00.012.
        \t Executed 2 tests, with 1 failures (1 unexpected) in 0.003 (0.012) seconds
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.testCases.count, 2)
        XCTAssertEqual(result.failedCount, 1)

        let failed = result.testCases.filter { $0.status == .failed }
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].name, "MyTests.FooTests.testBad")

        // Should capture the assertion failure message
        XCTAssertNotNil(failed[0].failureMessage)
        XCTAssertTrue(failed[0].failureMessage?.contains("XCTAssertEqual failed") ?? false)
    }

    func testXCTestSummaryLineParsing() {
        let output = """
        Test Case '-[A.B testC]' passed (0.001 seconds).
        \t Executed 42 tests, with 3 failures (2 unexpected) in 1.234 (1.500) seconds
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 1)

        // Should pick up summary counts
        XCTAssertEqual(result.totalCount, 42)
        XCTAssertEqual(result.failedCount, 3)
        XCTAssertEqual(result.duration, 1.234)
    }

    // MARK: - parseTestOutput: parallel format

    func testParallelAllPassed() {
        let output = """
        Building for debugging...
        Build complete! (0.18s)
        [1/5] Testing MyTests.FooTests/testAlpha
        [2/5] Testing MyTests.FooTests/testBeta
        [3/5] Testing MyTests.BarTests/testGamma
        [4/5] Testing MyTests.BarTests/testDelta
        [5/5] Testing MyTests.BarTests/testEpsilon
        \u{100F48}  Test run started.
        \u{100453}  Testing Library Version: 1743
        \u{100453}  Target Platform: arm64e-apple-macos14.0
        \u{10007B}  Test run with 0 tests in 0 suites passed after 0.001 seconds.
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.totalCount, 5)
        XCTAssertEqual(result.failedCount, 0)
    }

    func testParallelUsesLastTotal() {
        // The [N/M] lines may have different M values across test targets;
        // the parser should pick the largest.
        let output = """
        [1/3] Testing A.FooTests/testA
        [2/3] Testing A.FooTests/testB
        [3/3] Testing A.FooTests/testC
        [1/2] Testing B.BarTests/testX
        [2/2] Testing B.BarTests/testY
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        // Should use the max total seen (3), not the last (2)
        XCTAssertEqual(result.totalCount, 3)
    }

    func testParallelWithFailure() {
        let output = """
        [1/3] Testing MyTests.FooTests/testAlpha
        [2/3] Testing MyTests.FooTests/testBeta
        [3/3] Testing MyTests.FooTests/testGamma
        \u{10007B}  Test run with 0 tests in 0 suites passed after 0.001 seconds.
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.totalCount, 3)
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
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 0)

        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.duration, 0.003)
    }

    // MARK: - parseTestOutput: Swift Testing format

    func testSwiftTestingAllPassed() {
        let output = """
        ◇ Test testFoo() started.
        ✔ Test testFoo() passed after 0.001 seconds.
        ◇ Test testBar() started.
        ✔ Test testBar() passed after 0.002 seconds.
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.testCases.count, 2)
        XCTAssertTrue(result.testCases.allSatisfy { $0.status == .passed })
        XCTAssertEqual(result.testCases[0].name, "testFoo()")
        XCTAssertEqual(result.testCases[1].name, "testBar()")
    }

    func testSwiftTestingWithFailure() {
        let output = """
        ◇ Test testFoo() started.
        ✔ Test testFoo() passed after 0.001 seconds.
        ◇ Test testBroken() started.
        Expectation failed: (1) == (2)
        ✘ Test testBroken() failed after 0.002 seconds.
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        let failed = result.testCases.filter { $0.status == .failed }
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].name, "testBroken()")
    }

    // MARK: - parseTestOutput: Swift Testing SF Symbol format (v1743+)

    func testSwiftTestingSFSymbolsPassed() {
        // Newer Swift Testing uses SF Symbols instead of ✔✘◆◇
        let output = """
        \u{100F48}  Test run started.
        \u{100453}  Testing Library Version: 1743
        \u{100453}  Target Platform: arm64e-apple-macos14.0
        \u{100F48}  Suite "My Suite" started.
        \u{100F48}  Test "TickClock start and stop lifecycle" started.
        \u{10105B}  Test "TickClock start and stop lifecycle" passed after 0.053 seconds.
        \u{10105B}  Suite "My Suite" passed after 0.054 seconds.
        \u{10105B}  Test run with 1 test in 1 suite passed after 0.054 seconds.
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.testCases.count, 1)
        XCTAssertEqual(result.testCases[0].name, "TickClock start and stop lifecycle")
        XCTAssertEqual(result.testCases[0].status, .passed)
        XCTAssertEqual(result.testCases[0].duration, 0.053)
        XCTAssertEqual(result.totalCount, 1)
    }

    func testSwiftTestingSFSymbolsSummaryCount() {
        // "Test run with N tests in M suites passed" should contribute to totalCount
        let output = """
        \u{10105B}  Test run with 5 tests in 2 suites passed after 1.234 seconds.
        """
        let result = SwiftTestTool.parseTestOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.totalCount, 5)
    }

    // MARK: - formatTestResult

    func testFormatAllPassed() {
        let result = SwiftTestTool.TestResult(
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
        let formatted = SwiftTestTool.formatTestResult(result)

        // Should be short -- just a summary
        XCTAssertTrue(formatted.contains("2 tests passed."))
        XCTAssertFalse(formatted.contains("Failures:"))
    }

    func testFormatWithFailures() {
        let result = SwiftTestTool.TestResult(
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
        let formatted = SwiftTestTool.formatTestResult(result)

        XCTAssertTrue(formatted.contains("1 passed, 1 failed"))
        XCTAssertTrue(formatted.contains("Failures:"))
        XCTAssertTrue(formatted.contains("FAIL testBad"))
        XCTAssertTrue(formatted.contains("XCTAssertEqual failed"))
    }

    func testFormatFallbackWhenNothingParsed() {
        let result = SwiftTestTool.TestResult(
            succeeded: false,
            testCases: [],
            totalCount: 0,
            failedCount: 0,
            duration: nil,
            rawOutput: "error: no tests were run\nSome other error details"
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        XCTAssertTrue(formatted.contains("Raw output:"))
        XCTAssertTrue(formatted.contains("no tests were run"))
    }

    func testFormatFallbackStripsBuildNoise() {
        let result = SwiftTestTool.TestResult(
            succeeded: false,
            testCases: [],
            totalCount: 0,
            failedCount: 0,
            duration: nil,
            rawOutput: """
            Building for debugging...
            [1/50] Compiling MyApp Foo.swift
            [2/50] Compiling MyApp Bar.swift
            Linking MyAppTests
            Build complete! (2.3s)
            error: fatalError hit in testSomething
            some useful details here
            """
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        XCTAssertTrue(formatted.contains("error: fatalError hit in testSomething"))
        XCTAssertTrue(formatted.contains("some useful details here"))
        XCTAssertFalse(formatted.contains("Building for"))
        XCTAssertFalse(formatted.contains("Compiling"))
        XCTAssertFalse(formatted.contains("Linking"))
        XCTAssertFalse(formatted.contains("Build complete"))
    }

    func testFormatDurationMinutes() {
        let result = SwiftTestTool.TestResult(
            succeeded: true,
            testCases: [],
            totalCount: 100,
            failedCount: 0,
            duration: 125.3,
            rawOutput: ""
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        // Duration should not be included in formatted output
        XCTAssertTrue(formatted.contains("100 tests passed."))
        XCTAssertFalse(formatted.contains("2m 5.3s"))
    }

    func testFormatSingularTest() {
        let result = SwiftTestTool.TestResult(
            succeeded: true,
            testCases: [
                .init(name: "testOnly", status: .passed, duration: 0.001, failureMessage: nil),
            ],
            totalCount: 1,
            failedCount: 0,
            duration: 0.001,
            rawOutput: ""
        )
        let formatted = SwiftTestTool.formatTestResult(result)
        XCTAssertTrue(formatted.contains("1 test passed."))
        XCTAssertFalse(formatted.contains("1 tests"))
    }

    // MARK: - normalizeFailureMessage

    func testNormalizeStripsFilePathPrefix() {
        let msg = "/Users/dev/Tests/FooTests.swift:25: XCTAssertEqual failed: (1) is not equal to (2)"
        let normalized = SwiftTestTool.normalizeFailureMessage(msg)
        XCTAssertEqual(normalized, "XCTAssertEqual failed: (1) is not equal to (2)")
    }

    func testNormalizeStripsXCTestErrorPrefix() {
        let msg = "/Users/dev/Tests/FooTests.swift:25: error: -[MyTests.FooTests testBad] : XCTAssertEqual failed: (1) is not equal to (2)"
        let normalized = SwiftTestTool.normalizeFailureMessage(msg)
        XCTAssertEqual(normalized, "XCTAssertEqual failed: (1) is not equal to (2)")
    }

    func testNormalizeTrimsWhitespace() {
        let msg = "   XCTAssertEqual failed   "
        let normalized = SwiftTestTool.normalizeFailureMessage(msg)
        XCTAssertEqual(normalized, "XCTAssertEqual failed")
    }

    func testNormalizeNilReturnsUnknown() {
        XCTAssertEqual(SwiftTestTool.normalizeFailureMessage(nil), "Unknown failure")
    }

    func testNormalizeEmptyReturnsUnknown() {
        XCTAssertEqual(SwiftTestTool.normalizeFailureMessage(""), "Unknown failure")
    }

    func testNormalizeMultilineStripsPathsFromEachLine() {
        let msg = """
        /Users/dev/Tests/FooTests.swift:10: XCTAssertEqual failed: (1) is not equal to (2)
        /Users/dev/Tests/FooTests.swift:11: Additional context
        """
        let normalized = SwiftTestTool.normalizeFailureMessage(msg)
        XCTAssertEqual(normalized, "XCTAssertEqual failed: (1) is not equal to (2)\nAdditional context")
    }

    // MARK: - groupFailuresByMessage

    func testGroupFailuresByMessageGroupsSameMessages() {
        let failures: [SwiftTestTool.TestCase] = [
            .init(name: "testA", status: .failed, duration: 0.001, failureMessage: "same error"),
            .init(name: "testB", status: .failed, duration: 0.002, failureMessage: "same error"),
            .init(name: "testC", status: .failed, duration: 0.003, failureMessage: "different error"),
        ]
        let groups = SwiftTestTool.groupFailuresByMessage(failures)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].displayMessage, "same error")
        XCTAssertEqual(groups[0].tests.count, 2)
        XCTAssertEqual(groups[0].tests[0].name, "testA")
        XCTAssertEqual(groups[0].tests[1].name, "testB")
        XCTAssertEqual(groups[1].displayMessage, "different error")
        XCTAssertEqual(groups[1].tests.count, 1)
    }

    func testGroupFailuresByMessageGroupsNilMessagesAsUnknown() {
        let failures: [SwiftTestTool.TestCase] = [
            .init(name: "testA", status: .failed, duration: 0.001, failureMessage: nil),
            .init(name: "testB", status: .failed, duration: 0.002, failureMessage: nil),
        ]
        let groups = SwiftTestTool.groupFailuresByMessage(failures)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].displayMessage, "Unknown failure")
        XCTAssertEqual(groups[0].tests.count, 2)
    }

    func testGroupFailuresNormalizesDifferentPaths() {
        // Same assertion from different files should group together
        let failures: [SwiftTestTool.TestCase] = [
            .init(name: "testA", status: .failed, duration: 0.001,
                  failureMessage: "/Users/dev/Tests/FooTests.swift:25: XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
            .init(name: "testB", status: .failed, duration: 0.002,
                  failureMessage: "/Users/dev/Tests/BarTests.swift:40: XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
        ]
        let groups = SwiftTestTool.groupFailuresByMessage(failures)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tests.count, 2)
        XCTAssertEqual(groups[0].displayMessage, "XCTAssertEqual failed: (nil) is not equal to (Optional(42))")
    }

    // MARK: - formatTestResult: grouped output

    func testFormatGroupedFailures() {
        // Multiple tests share the same failure message -> grouped format
        let result = SwiftTestTool.TestResult(
            succeeded: false,
            testCases: [
                .init(name: "FooTests.testBar", status: .failed, duration: 0.001,
                      failureMessage: "XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "FooTests.testBaz", status: .failed, duration: 0.002,
                      failureMessage: "XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "FooTests.testQux", status: .failed, duration: 0.001,
                      failureMessage: "XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "BarTests.testOne", status: .failed, duration: 0.002,
                      failureMessage: "Expected true but got false"),
                .init(name: "BarTests.testTwo", status: .failed, duration: 0.001,
                      failureMessage: "Expected true but got false"),
                .init(name: "SlowTests.testHeavy", status: .failed, duration: 30.0,
                      failureMessage: "Timeout exceeded"),
            ],
            totalCount: 42,
            failedCount: 6,
            duration: 2.3,
            rawOutput: ""
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        // Should use grouped format
        XCTAssertTrue(formatted.contains("Failures:"))
        // Group headers with counts
        XCTAssertTrue(formatted.contains("\"XCTAssertEqual failed: (nil) is not equal to (Optional(42))\" (3 tests):"))
        XCTAssertTrue(formatted.contains("\"Expected true but got false\" (2 tests):"))
        XCTAssertTrue(formatted.contains("\"Timeout exceeded\" (1 test):"))
        // Test names as list items (without duration)
        XCTAssertTrue(formatted.contains("  - FooTests.testBar"))
        XCTAssertTrue(formatted.contains("  - FooTests.testBaz"))
        XCTAssertTrue(formatted.contains("  - BarTests.testOne"))
        XCTAssertTrue(formatted.contains("  - SlowTests.testHeavy"))
        // Should NOT have duration in output
        XCTAssertFalse(formatted.contains("0.001s"))
        XCTAssertFalse(formatted.contains("30.0s"))
        // Should NOT have "FAIL" prefix (that's the individual format)
        XCTAssertFalse(formatted.contains("FAIL"))
    }

    func testFormatAllUniqueFailuresUsesIndividualFormat() {
        // All failures have unique messages -> individual format
        let result = SwiftTestTool.TestResult(
            succeeded: false,
            testCases: [
                .init(name: "FooTests.testBar", status: .failed, duration: 0.001,
                      failureMessage: "XCTAssertEqual failed: (1) is not equal to (2)"),
                .init(name: "FooTests.testBaz", status: .failed, duration: 0.002,
                      failureMessage: "Expected array to be empty but had 3 elements"),
                .init(name: "FooTests.testQux", status: .failed, duration: 0.003,
                      failureMessage: "Forced unwrap of nil value"),
            ],
            totalCount: 42,
            failedCount: 3,
            duration: 1.2,
            rawOutput: ""
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        // Should use individual format
        XCTAssertTrue(formatted.contains("Failures:"))
        XCTAssertTrue(formatted.contains("FAIL FooTests.testBar"))
        XCTAssertTrue(formatted.contains("XCTAssertEqual failed: (1) is not equal to (2)"))
        XCTAssertTrue(formatted.contains("FAIL FooTests.testBaz"))
        XCTAssertTrue(formatted.contains("Expected array to be empty but had 3 elements"))
        XCTAssertTrue(formatted.contains("FAIL FooTests.testQux"))
        XCTAssertTrue(formatted.contains("Forced unwrap of nil value"))
        // Should NOT have group-style headers
        XCTAssertFalse(formatted.contains("(1 test):"))
        XCTAssertFalse(formatted.contains("  - "))
    }

    func testFormatMixedGroupedAndIndividualFailures() {
        // Some failures share a message, one is unique -> grouped format
        let result = SwiftTestTool.TestResult(
            succeeded: false,
            testCases: [
                .init(name: "FooTests.testA", status: .failed, duration: 0.001,
                      failureMessage: "XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "FooTests.testB", status: .failed, duration: 0.002,
                      failureMessage: "XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "BarTests.testUnique", status: .failed, duration: 0.003,
                      failureMessage: "Some unique error"),
            ],
            totalCount: 10,
            failedCount: 3,
            duration: 0.5,
            rawOutput: ""
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        // Should use grouped format because at least one group has >1 test
        XCTAssertTrue(formatted.contains("\"XCTAssertEqual failed: (nil) is not equal to (Optional(42))\" (2 tests):"))
        XCTAssertTrue(formatted.contains("  - FooTests.testA"))
        XCTAssertTrue(formatted.contains("  - FooTests.testB"))
        // The unique failure should appear as a single-test group
        XCTAssertTrue(formatted.contains("\"Some unique error\" (1 test):"))
        XCTAssertTrue(formatted.contains("  - BarTests.testUnique"))
        // Should NOT have duration in output
        XCTAssertFalse(formatted.contains("0.001s"))
        XCTAssertFalse(formatted.contains("0.003s"))
        // Should NOT use "FAIL" format
        XCTAssertFalse(formatted.contains("FAIL"))
    }

    func testFormatGroupedWithFilePathNormalization() {
        // Same assertion from different files should group together
        let result = SwiftTestTool.TestResult(
            succeeded: false,
            testCases: [
                .init(name: "FooTests.testA", status: .failed, duration: 0.001,
                      failureMessage: "/Users/dev/Tests/FooTests.swift:25: XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
                .init(name: "BarTests.testB", status: .failed, duration: 0.002,
                      failureMessage: "/Users/dev/Tests/BarTests.swift:40: XCTAssertEqual failed: (nil) is not equal to (Optional(42))"),
            ],
            totalCount: 10,
            failedCount: 2,
            duration: 0.5,
            rawOutput: ""
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        // Both should be grouped under the normalized message
        XCTAssertTrue(formatted.contains("\"XCTAssertEqual failed: (nil) is not equal to (Optional(42))\" (2 tests):"))
        XCTAssertTrue(formatted.contains("  - FooTests.testA"))
        XCTAssertTrue(formatted.contains("  - BarTests.testB"))
    }

    func testFormatGroupedWithNilFailureMessages() {
        // Tests with no failure message should group as "Unknown failure"
        let result = SwiftTestTool.TestResult(
            succeeded: false,
            testCases: [
                .init(name: "FooTests.testA", status: .failed, duration: 0.001, failureMessage: nil),
                .init(name: "FooTests.testB", status: .failed, duration: 0.002, failureMessage: nil),
            ],
            totalCount: 5,
            failedCount: 2,
            duration: 0.5,
            rawOutput: ""
        )
        let formatted = SwiftTestTool.formatTestResult(result)

        XCTAssertTrue(formatted.contains("\"Unknown failure\" (2 tests):"))
        XCTAssertTrue(formatted.contains("  - FooTests.testA"))
        XCTAssertTrue(formatted.contains("  - FooTests.testB"))
    }
}
