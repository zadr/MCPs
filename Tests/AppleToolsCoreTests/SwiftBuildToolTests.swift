import XCTest
@testable import AppleToolsCore

final class SwiftBuildToolTests: XCTestCase {

    // MARK: - parseBuildOutput

    func testCleanBuildSucceeded() {
        let output = """
        Building for debugging...
        [1/5] Compiling MyApp main.swift
        [2/5] Compiling MyApp Utils.swift
        [3/5] Linking MyApp
        Build complete! (1.23s)
        """
        let result = SwiftBuildTool.parseBuildOutput(output, exitCode: 0)

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.notes.isEmpty)
    }

    func testBuildWithErrors() {
        let output = """
        Building for debugging...
        /Users/dev/MyApp/Sources/Foo.swift:42:10: error: cannot find 'bar' in scope
        /Users/dev/MyApp/Sources/Foo.swift:43:5: error: missing return in global function expected to return 'Int'
        """
        let result = SwiftBuildTool.parseBuildOutput(output, exitCode: 1)

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
        Build complete! (0.50s)
        """
        let result = SwiftBuildTool.parseBuildOutput(output, exitCode: 0)

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
        """
        let result = SwiftBuildTool.parseBuildOutput(output, exitCode: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].message, "did you mean 'baz'?")
    }

    func testBuildMixedDiagnostics() {
        let output = """
        /path/A.swift:1:1: error: something broke
        /path/A.swift:2:1: warning: this is fishy
        /path/A.swift:3:1: note: see here
        /path/B.swift:10:5: error: another issue
        /path/B.swift:11:5: warning: also fishy
        """
        let result = SwiftBuildTool.parseBuildOutput(output, exitCode: 1)

        XCTAssertEqual(result.errors.count, 2)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertEqual(result.notes.count, 1)
    }

    // MARK: - formatBuildResult

    func testFormatCleanBuild() {
        let result = SwiftBuildTool.BuildResult(
            succeeded: true, errors: [], warnings: [], notes: [], rawOutput: ""
        )
        let formatted = SwiftBuildTool.formatBuildResult(result)
        XCTAssertEqual(formatted, "Build succeeded.")
    }

    func testFormatBuildWithWarningsOnly() {
        let result = SwiftBuildTool.BuildResult(
            succeeded: true,
            errors: [],
            warnings: [
                .init(file: "/path/A.swift", line: 1, column: 1, severity: .warning, message: "unused var")
            ],
            notes: [],
            rawOutput: ""
        )
        let formatted = SwiftBuildTool.formatBuildResult(result)
        XCTAssertTrue(formatted.contains("Build succeeded with 1 warning."))
        XCTAssertTrue(formatted.contains("Warnings:"))
        XCTAssertTrue(formatted.contains("unused var"))
    }

    func testFormatBuildFailedWithErrors() {
        let result = SwiftBuildTool.BuildResult(
            succeeded: false,
            errors: [
                .init(file: "/path/A.swift", line: 10, column: 5, severity: .error, message: "type mismatch"),
                .init(file: "/path/B.swift", line: 20, column: 3, severity: .error, message: "undeclared"),
            ],
            warnings: [
                .init(file: "/path/A.swift", line: 5, column: 1, severity: .warning, message: "unused")
            ],
            notes: [],
            rawOutput: ""
        )
        let formatted = SwiftBuildTool.formatBuildResult(result)
        XCTAssertTrue(formatted.hasPrefix("Build failed: 2 errors, 1 warning."))
        XCTAssertTrue(formatted.contains("Errors:"))
        XCTAssertTrue(formatted.contains("type mismatch"))
        XCTAssertTrue(formatted.contains("Warnings:"))
    }

    func testFormatBuildFailedLinkerError() {
        // Linker errors don't match the diagnostic pattern, so raw output should appear
        let rawOutput = "ld: library 'sqlite3' not found\nclang: error: linker command failed"
        let result = SwiftBuildTool.BuildResult(
            succeeded: false, errors: [], warnings: [], notes: [], rawOutput: rawOutput
        )
        let formatted = SwiftBuildTool.formatBuildResult(result)
        XCTAssertTrue(formatted.contains("Build failed."))
        XCTAssertTrue(formatted.contains("Raw output:"))
        XCTAssertTrue(formatted.contains("library 'sqlite3' not found"))
    }

    func testFormatSingularCounts() {
        let result = SwiftBuildTool.BuildResult(
            succeeded: false,
            errors: [
                .init(file: "/path/A.swift", line: 1, column: 1, severity: .error, message: "oops")
            ],
            warnings: [],
            notes: [],
            rawOutput: ""
        )
        let formatted = SwiftBuildTool.formatBuildResult(result)
        XCTAssertTrue(formatted.contains("1 error"))
        XCTAssertFalse(formatted.contains("1 errors"))
    }
}
