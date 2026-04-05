import XCTest
import MCP
@testable import AppleToolsCore

final class ToolDefinitionTests: XCTestCase {

    // MARK: - Helpers

    private var toolDefinition: Tool {
        SwiftTool.definition
    }

    // MARK: - Tool count

    func testSingleToolIsRegistered() {
        // We now have exactly 1 consolidated tool
        XCTAssertEqual(SwiftTool.name, "swift")
    }

    // MARK: - Non-empty name

    func testToolHasNonEmptyName() {
        XCTAssertFalse(toolDefinition.name.isEmpty, "Tool name should not be empty")
    }

    // MARK: - Description

    func testToolHasDescription() {
        let description = toolDefinition.description ?? ""
        XCTAssertFalse(description.isEmpty, "Tool should have a non-empty description")
    }

    // MARK: - Input schema validity

    func testToolHasValidInputSchema() throws {
        let encoder = JSONEncoder()
        let schema = toolDefinition.inputSchema

        let data = try encoder.encode(schema)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json, "inputSchema should be a valid JSON object")

        // Should have "type": "object"
        let typeValue = json?["type"] as? String
        XCTAssertEqual(typeValue, "object", "inputSchema should have type 'object'")

        // Should have "properties"
        let properties = json?["properties"] as? [String: Any]
        XCTAssertNotNil(properties, "inputSchema should have 'properties'")
        XCTAssertFalse(properties?.isEmpty ?? true, "properties should not be empty")

        // Should have "action" property
        let actionProp = properties?["action"] as? [String: Any]
        XCTAssertNotNil(actionProp, "inputSchema should have an 'action' property")

        // Action should have enum values
        let enumValues = actionProp?["enum"] as? [String]
        XCTAssertNotNil(enumValues, "action property should have enum values")
        XCTAssertEqual(enumValues?.count, 12, "action enum should have 12 values")
    }

    // MARK: - Tool name

    func testToolNameConstant() {
        XCTAssertEqual(SwiftTool.name, "swift")
    }

    // MARK: - Tool definition name matches static name constant

    func testToolDefinitionNameMatchesConstant() {
        XCTAssertEqual(SwiftTool.definition.name, SwiftTool.name)
    }

    // MARK: - Required fields

    func testToolHasRequiredFields() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(toolDefinition.inputSchema)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let required = json?["required"] as? [String]
        XCTAssertNotNil(required, "Tool should have a 'required' field")
        XCTAssertTrue(required?.contains("action") ?? false, "action should be required")
    }

    // MARK: - Action enum completeness

    func testActionEnumContainsAllActions() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(toolDefinition.inputSchema)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let properties = json?["properties"] as? [String: Any]
        let actionProp = properties?["action"] as? [String: Any]
        let enumValues = actionProp?["enum"] as? [String]

        let expectedActions = [
            "hover", "definition", "references", "completion",
            "diagnostics", "document_symbols", "workspace_symbols",
            "format", "code_actions", "rename", "build", "test",
        ]

        for action in expectedActions {
            XCTAssertTrue(
                enumValues?.contains(action) ?? false,
                "action enum should contain '\(action)'"
            )
        }
    }

    // MARK: - All properties present

    func testAllPropertiesPresent() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(toolDefinition.inputSchema)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let properties = json?["properties"] as? [String: Any]

        let expectedProperties = [
            "action", "filePath", "line", "character",
            "query", "newName", "includeDeclaration",
            "startLine", "startCharacter", "endLine", "endCharacter",
            "packagePath", "configuration", "target", "filter", "parallel",
        ]

        for prop in expectedProperties {
            XCTAssertNotNil(
                properties?[prop],
                "inputSchema should have property '\(prop)'"
            )
        }
    }

    // MARK: - Legacy tools still have handle methods

    func testLegacyToolHandleMethodsExist() {
        // Verify that the individual tool types still exist and have their name constants
        // (they are still used as delegates from SwiftTool.handle)
        XCTAssertEqual(SwiftHoverTool.name, "swift_hover")
        XCTAssertEqual(SwiftDefinitionTool.name, "swift_definition")
        XCTAssertEqual(SwiftReferencesTool.name, "swift_references")
        XCTAssertEqual(SwiftCompletionTool.name, "swift_completion")
        XCTAssertEqual(SwiftDiagnosticsTool.name, "swift_diagnostics")
        XCTAssertEqual(SwiftDocumentSymbolsTool.name, "swift_document_symbols")
        XCTAssertEqual(SwiftWorkspaceSymbolsTool.name, "swift_workspace_symbols")
        XCTAssertEqual(SwiftFormatTool.name, "swift_format")
        XCTAssertEqual(SwiftCodeActionsTool.name, "swift_code_actions")
        XCTAssertEqual(SwiftRenameTool.name, "swift_rename")
    }
}
