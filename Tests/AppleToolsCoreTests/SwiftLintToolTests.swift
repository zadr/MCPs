import XCTest
import MCP
@testable import AppleToolsCore

final class SwiftLintToolTests: XCTestCase {

    // MARK: - Tool Definition

    func testToolName() {
        XCTAssertEqual(SwiftLintTool.name, "swiftlint")
    }

    func testDefinitionNameMatchesConstant() {
        XCTAssertEqual(SwiftLintTool.definition.name, SwiftLintTool.name)
    }

    func testDefinitionHasDescription() {
        let description = SwiftLintTool.definition.description ?? ""
        XCTAssertFalse(description.isEmpty)
    }

    func testDefinitionSchema() throws {
        let data = try JSONEncoder().encode(SwiftLintTool.definition.inputSchema)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let typeValue = json?["type"] as? String
        XCTAssertEqual(typeValue, "object")

        let properties = json?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["action"])
        XCTAssertNotNil(properties?["path"])
        XCTAssertNotNil(properties?["configPath"])
        XCTAssertNotNil(properties?["strict"])
        XCTAssertNotNil(properties?["ruleName"])
        XCTAssertNotNil(properties?["enabledOnly"])

        let required = json?["required"] as? [String]
        XCTAssertEqual(required, ["action"])
    }

    func testActionEnumValues() throws {
        let data = try JSONEncoder().encode(SwiftLintTool.definition.inputSchema)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let properties = json?["properties"] as? [String: Any]
        let actionProp = properties?["action"] as? [String: Any]
        let enumValues = actionProp?["enum"] as? [String]

        let expected = ["lint", "fix", "rules", "rule_config", "version"]
        XCTAssertEqual(enumValues, expected)
    }

    // MARK: - Missing Action

    func testHandleMissingAction() async {
        do {
            _ = try await SwiftLintTool.handle(nil)
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue("\(error)".contains("action"))
        }
    }

    func testHandleUnknownAction() async {
        do {
            _ = try await SwiftLintTool.handle(["action": .string("nope")])
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue("\(error)".contains("Unknown action"))
        }
    }

    // MARK: - Missing Path

    func testLintMissingPath() async {
        do {
            _ = try await SwiftLintTool.handle(["action": .string("lint")])
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue("\(error)".contains("path"))
        }
    }

    func testFixMissingPath() async {
        do {
            _ = try await SwiftLintTool.handle(["action": .string("fix")])
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue("\(error)".contains("path"))
        }
    }

    // MARK: - Missing Rule Name

    func testRuleConfigMissingRuleName() async {
        do {
            _ = try await SwiftLintTool.handle(["action": .string("rule_config")])
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue("\(error)".contains("ruleName"))
        }
    }
}
