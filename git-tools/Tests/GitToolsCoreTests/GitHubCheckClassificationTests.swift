import XCTest
import MCP
@testable import GitToolsCore

final class GitHubCheckClassificationTests: XCTestCase {

    private func outcome(_ json: String) throws -> GitHubTool.CheckOutcome {
        let check = try JSONDecoder().decode(GitHubTool.Check.self, from: Data(json.utf8))
        return check.outcome
    }

    // CheckRun: gh leaves conclusion "" until the run concludes.

    func testQueuedCheckRunIsPending() throws {
        // The PR 971 case.
        try XCTAssertEqual(outcome(#"{"__typename":"CheckRun","status":"QUEUED","conclusion":""}"#), .pending)
    }

    func testInProgressCheckRunIsPending() throws {
        try XCTAssertEqual(outcome(#"{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""}"#), .pending)
    }

    func testSuccessfulCheckRunIsPassing() throws {
        try XCTAssertEqual(outcome(#"{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}"#), .passing)
    }

    func testFailedCheckRunIsFailing() throws {
        try XCTAssertEqual(outcome(#"{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}"#), .failing)
    }

    func testTimedOutCheckRunIsFailing() throws {
        try XCTAssertEqual(outcome(#"{"__typename":"CheckRun","status":"COMPLETED","conclusion":"TIMED_OUT"}"#), .failing)
    }

    // StatusContext: legacy commit statuses carry result in `state`.

    func testPendingStatusContextIsPending() throws {
        try XCTAssertEqual(outcome(#"{"__typename":"StatusContext","state":"PENDING"}"#), .pending)
    }

    func testSuccessStatusContextIsPassing() throws {
        try XCTAssertEqual(outcome(#"{"__typename":"StatusContext","state":"SUCCESS"}"#), .passing)
    }

    func testErrorStatusContextIsFailing() throws {
        try XCTAssertEqual(outcome(#"{"__typename":"StatusContext","state":"ERROR"}"#), .failing)
    }
}
