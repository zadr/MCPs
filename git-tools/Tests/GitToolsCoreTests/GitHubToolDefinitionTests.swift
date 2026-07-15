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
}
