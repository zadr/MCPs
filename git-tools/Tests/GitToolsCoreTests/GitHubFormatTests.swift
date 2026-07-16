import XCTest
import MCP
@testable import GitToolsCore

final class GitHubFormatTests: XCTestCase {

    private func format(_ json: String) throws -> String {
        let pr = try JSONDecoder().decode(GitHubTool.PullRequest.self, from: Data(json.utf8))
        return GitHubTool.format(pr: pr)
    }

    private func pr(rollup: String) -> String {
        #"{"number":1,"title":"t","isDraft":false,"state":"OPEN","baseRefName":"main","statusCheckRollup":\#(rollup)}"#
    }

    func testAllRunningReportsPendingCount() throws {
        let rollup = """
        [{"__typename":"CheckRun","status":"QUEUED","conclusion":""},
         {"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""},
         {"__typename":"CheckRun","status":"QUEUED","conclusion":""}]
        """
        let out = try format(pr(rollup: rollup))
        XCTAssertTrue(out.contains("checks: pending (3 running)"), out)
        XCTAssertFalse(out.contains("passing"), out)
    }

    func testMixedPassingAndPendingReportsPending() throws {
        let rollup = """
        [{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},
         {"__typename":"CheckRun","status":"QUEUED","conclusion":""}]
        """
        let out = try format(pr(rollup: rollup))
        XCTAssertTrue(out.contains("checks: pending (1 running)"), out)
    }

    func testFailingTakesPrecedenceOverPending() throws {
        let rollup = """
        [{"__typename":"CheckRun","name":"Build","status":"COMPLETED","conclusion":"FAILURE"},
         {"__typename":"CheckRun","name":"Lint","status":"QUEUED","conclusion":""}]
        """
        let out = try format(pr(rollup: rollup))
        XCTAssertTrue(out.contains("failing checks:"), out)
        XCTAssertTrue(out.contains("- Build"), out)
        XCTAssertFalse(out.contains("pending"), out)
    }

    func testAllPassing() throws {
        let rollup = """
        [{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},
         {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]
        """
        let out = try format(pr(rollup: rollup))
        XCTAssertTrue(out.contains("checks: passing"), out)
    }

    func testNoChecks() throws {
        let out = try format(pr(rollup: "[]"))
        XCTAssertTrue(out.contains("checks: none"), out)
    }
}
