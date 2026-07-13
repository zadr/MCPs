import XCTest
import MCP
@testable import GitToolsCore

final class GitStackToolDefinitionTests: XCTestCase {

    private var toolDefinition: Tool {
        GitStackTool.definition
    }

    private func schemaJSON() throws -> [String: Any] {
        let data = try JSONEncoder().encode(toolDefinition.inputSchema)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testToolNameConstant() {
        XCTAssertEqual(GitStackTool.name, "git-stack")
    }

    func testDefinitionNameMatchesConstant() {
        XCTAssertEqual(GitStackTool.definition.name, GitStackTool.name)
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
            "stack_info", "ancestors", "children", "log",
            "set_base", "new", "adopt", "delete",
            "track", "split", "remove",
            "move", "restack", "reset",
            "save", "sync",
        ]
        XCTAssertEqual(enumValues.map(Set.init), Set(expected))
        XCTAssertEqual(enumValues?.count, expected.count)
    }

    func testKeyPropertiesPresent() throws {
        let json = try schemaJSON()
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        for prop in ["action", "repoPath", "branch", "name", "count", "message", "onto", "remote", "all", "push", "force"] {
            XCTAssertNotNil(properties[prop], "schema should have property '\(prop)'")
        }
    }

    func testNotReadOnly() {
        XCTAssertEqual(toolDefinition.annotations.readOnlyHint, false)
        XCTAssertEqual(toolDefinition.annotations.openWorldHint, false)
    }
}
