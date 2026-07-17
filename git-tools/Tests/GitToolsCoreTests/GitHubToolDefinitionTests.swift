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

    func testActionEnumContainsListActivePRs() throws {
        let json = try schemaJSON()
        let properties = json["properties"] as? [String: Any]
        let actionProp = properties?["action"] as? [String: Any]
        let enumValues = actionProp?["enum"] as? [String]
        XCTAssertEqual(enumValues, ["list-active-prs"])
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

    // MARK: - Merge state

    private func decodePR(mergeStateStatus: String?) throws -> GitHubTool.PullRequest {
        let mergeField = mergeStateStatus.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"number":1001,"title":"t","isDraft":false,"state":"OPEN",
         "baseRefName":"main","statusCheckRollup":[],"mergeStateStatus":\(mergeField)}
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
}
