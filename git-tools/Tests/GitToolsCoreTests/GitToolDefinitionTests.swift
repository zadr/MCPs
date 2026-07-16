import XCTest
import MCP
@testable import GitToolsCore

final class GitToolDefinitionTests: XCTestCase {

    private var toolDefinition: Tool {
        GitTool.definition
    }

    private func schemaJSON() throws -> [String: Any] {
        let data = try JSONEncoder().encode(toolDefinition.inputSchema)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testToolNameConstant() {
        XCTAssertEqual(GitTool.name, "git-core")
    }

    func testDefinitionNameMatchesConstant() {
        XCTAssertEqual(GitTool.definition.name, GitTool.name)
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

    func testActionEnumContainsAllActions() throws {
        let json = try schemaJSON()
        let properties = json["properties"] as? [String: Any]
        let actionProp = properties?["action"] as? [String: Any]
        let enumValues = actionProp?["enum"] as? [String]

        let expected = [
            "init", "status", "log", "diff", "blame", "branch_info",
            "merge_analysis", "show", "tag", "remote", "add", "mv",
            "commit", "push", "pull", "checkout", "reset", "stash",
            "merge", "rebase", "cherry_pick", "branch_create",
            "branch_delete", "branch_rename", "worktree_list",
            "worktree_find_by_branch_name",
            "worktree_add", "worktree_remove", "worktree_prune",
            "branch_prune", "branch_find_duplicates",
        ]
        XCTAssertEqual(enumValues.map(Set.init), Set(expected))
        XCTAssertEqual(enumValues?.count, expected.count)
    }

    func testKeyPropertiesPresent() throws {
        let json = try schemaJSON()
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        for prop in ["action", "repoPath", "message", "branch", "files", "ref"] {
            XCTAssertNotNil(properties[prop], "schema should have property '\(prop)'")
        }
    }

    func testNotReadOnly() {
        XCTAssertEqual(toolDefinition.annotations.readOnlyHint, false)
        XCTAssertEqual(toolDefinition.annotations.openWorldHint, false)
    }
}
