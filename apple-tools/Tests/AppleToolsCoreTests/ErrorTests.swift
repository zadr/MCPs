import XCTest
@testable import AppleToolsCore

final class ErrorTests: XCTestCase {

    func testSourceKitLSPNotFoundHasDescription() {
        let error = AppleToolsError.sourceKitLSPNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testLspNotInitializedHasDescription() {
        let error = AppleToolsError.lspNotInitialized
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testInvalidFilePathHasDescription() {
        let error = AppleToolsError.invalidFilePath("/bad/path")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/bad/path"))
    }

    func testLspRequestFailedHasDescription() {
        let error = AppleToolsError.lspRequestFailed(method: "textDocument/hover", message: "timeout")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("textDocument/hover"))
        XCTAssertTrue(error.errorDescription!.contains("timeout"))
    }

    func testJsonRPCErrorHasDescription() {
        let error = AppleToolsError.jsonRPCError(code: -32600, message: "Invalid Request")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("-32600"))
        XCTAssertTrue(error.errorDescription!.contains("Invalid Request"))
    }

    func testInvalidArgumentHasDescription() {
        let error = AppleToolsError.invalidArgument(name: "line", expected: "integer")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("line"))
        XCTAssertTrue(error.errorDescription!.contains("integer"))
    }

    func testMissingRequiredArgumentHasDescription() {
        let error = AppleToolsError.missingRequiredArgument("filePath")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("filePath"))
    }

    func testProcessSpawnFailedHasDescription() {
        let error = AppleToolsError.processSpawnFailed("Permission denied")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Permission denied"))
    }

    func testAllErrorCasesHaveNonNilDescription() {
        let allErrors: [AppleToolsError] = [
            .sourceKitLSPNotFound,
            .lspNotInitialized,
            .invalidFilePath("/test"),
            .lspRequestFailed(method: "test", message: "test"),
            .jsonRPCError(code: 0, message: "test"),
            .invalidArgument(name: "test", expected: "test"),
            .missingRequiredArgument("test"),
            .processSpawnFailed("test"),
        ]

        for error in allErrors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a non-nil errorDescription")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) should have a non-empty errorDescription")
        }
    }

    func testErrorConformsToLocalizedError() {
        // Verify that AppleToolsError conforms to LocalizedError
        let error: LocalizedError = AppleToolsError.sourceKitLSPNotFound
        XCTAssertNotNil(error.errorDescription)
    }
}
