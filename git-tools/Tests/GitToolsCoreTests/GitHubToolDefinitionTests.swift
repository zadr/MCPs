import XCTest
import MCP
@testable import GitToolsCore

final class GitHubToolDefinitionTests: XCTestCase {

    private var toolDefinition: Tool {
        GitHubTool.definition
    }

    private func schemaJSON() throws -> [String: Any] {
        let data = try JSONEncoder().encode(toolDefinition.inputSchema)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testToolNameConstant() {
        XCTAssertEqual(GitHubTool.name, "github-tools")
    }

    func testDefinitionNameMatchesConstant() {
        XCTAssertEqual(GitHubTool.definition.name, GitHubTool.name)
    }

    func testToolHasDescription() {
        XCTAssertFalse((toolDefinition.description ?? "").isEmpty)
    }

    func testInputSchemaIsObjectWithProperties() throws {
        let json = try schemaJSON()
        XCTAssertEqual(json["type"] as? String, "object")
        let properties = json["properties"] as? [String: Any]
        XCTAssertNotNil(properties)
        XCTAssertFalse(properties?.isEmpty ?? true)
    }

    func testRequiredFields() throws {
        let json = try schemaJSON()
        let required = json["required"] as? [String]
        XCTAssertEqual(required.map(Set.init), ["action", "repoPath"])
    }

    func testActionEnumValues() throws {
        let json = try schemaJSON()
        let properties = json["properties"] as? [String: Any]
        let actionProp = properties?["action"] as? [String: Any]
        let enumValues = actionProp?["enum"] as? [String]
        XCTAssertEqual(enumValues, ["list-active-prs", "pr-status", "wait-for-checks"])
    }

    func testSchemaExposesWaitForChecksProperties() throws {
        let json = try schemaJSON()
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        for key in ["pr", "pollSeconds"] {
            XCTAssertNotNil(properties[key], "missing property: \(key)")
        }
    }

    func testReadOnlyOpenWorld() {
        XCTAssertEqual(toolDefinition.annotations.readOnlyHint, true)
        XCTAssertEqual(toolDefinition.annotations.openWorldHint, true)
    }

    // MARK: - Argument validation (no network)

    func testMissingActionThrows() async {
        do {
            _ = try await GitHubTool.handle(["repoPath": .string("/tmp")])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("action"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMissingRepoPathThrows() async {
        do {
            _ = try await GitHubTool.handle(["action": .string("list-active-prs")])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("repoPath"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUnknownActionThrows() async {
        do {
            _ = try await GitHubTool.handle([
                "action": .string("bogus"),
                "repoPath": .string("/tmp"),
            ])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("Unknown action"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testWaitForChecksMissingPRThrows() async {
        do {
            _ = try await GitHubTool.handle([
                "action": .string("wait-for-checks"),
                "repoPath": .string("/tmp"),
            ])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("pr"), "\(error)")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPRStatusMissingPRThrows() async {
        do {
            _ = try await GitHubTool.handle([
                "action": .string("pr-status"),
                "repoPath": .string("/tmp"),
            ])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("pr"), "\(error)")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Merge state

    private func decodePR(mergeStateStatus: String?) throws -> GitHubTool.PullRequest {
        try decodePR(mergeStateStatus: mergeStateStatus, statusCheckRollup: "[]")
    }

    /// `statusCheckRollup` is spliced in verbatim as a JSON array literal.
    private func decodePR(
        mergeStateStatus: String?,
        statusCheckRollup: String
    ) throws -> GitHubTool.PullRequest {
        let mergeField = mergeStateStatus.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"number":1001,"title":"t","isDraft":false,"state":"OPEN",
         "baseRefName":"main","statusCheckRollup":\(statusCheckRollup),"mergeStateStatus":\(mergeField)}
        """
        return try JSONDecoder().decode(GitHubTool.PullRequest.self, from: Data(json.utf8))
    }

    func testMergeStateMapping() throws {
        XCTAssertEqual(try decodePR(mergeStateStatus: "DIRTY").mergeState, .conflicting)
        XCTAssertEqual(try decodePR(mergeStateStatus: "BEHIND").mergeState, .behind)
        XCTAssertEqual(try decodePR(mergeStateStatus: "CLEAN").mergeState, .clean)
        XCTAssertEqual(try decodePR(mergeStateStatus: "BLOCKED").mergeState, .clean)
        XCTAssertEqual(try decodePR(mergeStateStatus: nil).mergeState, .unknown)
    }

    func testFormatReportsConflicting() throws {
        let output = GitHubTool.format(pr: try decodePR(mergeStateStatus: "DIRTY"))
        XCTAssertTrue(output.contains("merge: conflicting"), output)
    }

    func testFormatReportsClean() throws {
        let output = GitHubTool.format(pr: try decodePR(mergeStateStatus: "CLEAN"))
        XCTAssertTrue(output.contains("merge: clean"), output)
    }

    // MARK: - Wait verdict

    private static let passingCheck = """
    {"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://ci/1"}
    """
    private static let failingCheck = """
    {"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://ci/1"}
    """
    private static let runningCheck = """
    {"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":"","detailsUrl":"https://ci/1"}
    """

    func testWaitVerdictPassing() throws {
        let pr = try decodePR(mergeStateStatus: "CLEAN", statusCheckRollup: "[\(Self.passingCheck)]")
        let output = GitHubTool.waitVerdict(pr: pr)
        XCTAssertTrue(output.contains("checks complete: passing"), output)
    }

    func testWaitVerdictFailing() throws {
        let pr = try decodePR(mergeStateStatus: "CLEAN", statusCheckRollup: "[\(Self.failingCheck)]")
        let output = GitHubTool.waitVerdict(pr: pr)
        XCTAssertTrue(output.contains("checks complete: failing"), output)
    }

    func testWaitVerdictNone() throws {
        let pr = try decodePR(mergeStateStatus: "CLEAN", statusCheckRollup: "[]")
        let output = GitHubTool.waitVerdict(pr: pr)
        XCTAssertTrue(output.contains("checks complete: none"), output)
    }

    // A running check classifies as pending — this is the predicate the poll
    // loop blocks on, so waitVerdict is never reached while it holds.
    func testRunningCheckIsPending() throws {
        let pr = try decodePR(mergeStateStatus: "CLEAN", statusCheckRollup: "[\(Self.runningCheck)]")
        let rollup = try XCTUnwrap(pr.statusCheckRollup)
        XCTAssertTrue(rollup.contains { $0.outcome == .pending })
    }

    // classifyWatch is the exit-code + stderr contract the appear-poll loop
    // turns on. The overloaded case is exit 1: "no checks reported" means retry,
    // anything else at exit 1 means a real failing terminal state.
    func testClassifyNoChecksRetriesRegardlessOfExitCode() {
        let stderr = "no checks reported on the 'my-branch' branch"
        // gh has emitted this at both exit 1 and exit 8 across versions; neither
        // may be mistaken for a terminal state.
        XCTAssertEqual(GitHubTool.classifyWatch(exitCode: 1, stderr: stderr), .noChecksYet)
        XCTAssertEqual(GitHubTool.classifyWatch(exitCode: 8, stderr: stderr), .noChecksYet)
    }

    func testClassifyAllPassSettles() {
        XCTAssertEqual(GitHubTool.classifyWatch(exitCode: 0, stderr: ""), .settled)
    }

    func testClassifyPendingSettles() {
        // Exit 8 with checks present: gh watched to a terminal render.
        XCTAssertEqual(GitHubTool.classifyWatch(exitCode: 8, stderr: ""), .settled)
    }

    func testClassifyFailingSettles() {
        // Exit 1 without the no-checks string is a genuine failing state.
        XCTAssertEqual(GitHubTool.classifyWatch(exitCode: 1, stderr: ""), .settled)
    }

    func testClassifyAuthError() {
        let stderr = "gh auth login required"
        XCTAssertEqual(GitHubTool.classifyWatch(exitCode: 4, stderr: stderr), .authError)
    }

    func testClassifyOtherError() {
        XCTAssertEqual(GitHubTool.classifyWatch(exitCode: 2, stderr: "boom"), .otherError("boom"))
    }
}
