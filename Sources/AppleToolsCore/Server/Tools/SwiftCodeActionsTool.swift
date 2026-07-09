import MCP

enum SwiftCodeActionsTool {
    static let name = "swift_code_actions"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Get available code actions (quick fixes, refactorings) at a position or range in a Swift file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filePath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the Swift file"),
                    ]),
                    "startLine": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed start line number"),
                    ]),
                    "startCharacter": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed start character offset"),
                    ]),
                    "endLine": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed end line number (defaults to startLine)"),
                    ]),
                    "endCharacter": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed end character offset (defaults to startCharacter)"),
                    ]),
                ]),
                "required": .array([
                    .string("filePath"),
                    .string("startLine"),
                    .string("startCharacter"),
                ]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        )
    }

    static func handle(
        _ arguments: [String: Value]?,
        lspService: SourceKitLSPService
    ) async throws -> CallTool.Result {
        TraceLog.enter([("arguments", String(describing: arguments))])
        guard let args = arguments,
              let filePath = args["filePath"]?.stringValue else {
            TraceLog.point("missing-filePath")
            throw MCPError.invalidParams("Missing required argument: filePath")
        }
        guard let startLine = args["startLine"]?.intValue ?? args["startLine"]?.doubleValue.map({ Int($0) }) else {
            TraceLog.point("missing-startLine")
            throw MCPError.invalidParams("Missing required argument: startLine")
        }
        guard let startCharacter = args["startCharacter"]?.intValue ?? args["startCharacter"]?.doubleValue.map({ Int($0) }) else {
            TraceLog.point("missing-startCharacter")
            throw MCPError.invalidParams("Missing required argument: startCharacter")
        }

        let endLine = args["endLine"]?.intValue ?? args["endLine"]?.doubleValue.map({ Int($0) }) ?? startLine
        let endCharacter = args["endCharacter"]?.intValue ?? args["endCharacter"]?.doubleValue.map({ Int($0) }) ?? startCharacter
        TraceLog.point("range-resolved", [("startLine", startLine), ("startCharacter", startCharacter), ("endLine", endLine), ("endCharacter", endCharacter)])

        let uri = FileURI.fromPath(filePath)
        let range = LSPRange(
            start: LSPPosition(line: startLine, character: startCharacter),
            end: LSPPosition(line: endLine, character: endCharacter)
        )
        let actions = try await lspService.codeActions(uri: uri, range: range)

        let text: String
        if actions.isEmpty {
            TraceLog.point("actions-empty")
            text = "No code actions available at this position."
        } else {
            TraceLog.point("actions-present", [("count", actions.count)])
            var lines: [String] = []
            lines.append("Available code actions (\(actions.count)):")
            lines.append("")
            for action in actions {
                var entry = "- \(action.title)"
                if let kind = action.kind {
                    entry += " [\(kind)]"
                }
                let hasEdits = action.edit != nil
                if hasEdits {
                    entry += " (has workspace edits)"
                }
                lines.append(entry)
            }
            text = lines.joined(separator: "\n")
        }

        TraceLog.exit([("textLength", text.count)])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }
}
