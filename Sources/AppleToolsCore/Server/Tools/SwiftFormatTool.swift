import MCP

enum SwiftFormatTool {
    static let name = "swift_format"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Format a Swift file and return the text edits",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filePath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the Swift file"),
                    ]),
                ]),
                "required": .array([.string("filePath")]),
            ]),
            annotations: .init(readOnlyHint: true, idempotentHint: true, openWorldHint: false)
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
        TraceLog.point("args-ok", [("filePath", filePath)])

        let uri = FileURI.fromPath(filePath)
        let edits = try await lspService.formatting(uri: uri)

        let text: String
        if edits.isEmpty {
            TraceLog.point("edits-empty")
            text = "File is already well-formatted."
        } else {
            TraceLog.point("edits-present", [("count", edits.count)])
            var lines: [String] = []
            lines.append("Formatting produced \(edits.count) edit(s):")
            lines.append("")
            for (index, edit) in edits.enumerated() {
                let startLine = edit.range.start.line
                let startChar = edit.range.start.character
                let endLine = edit.range.end.line
                let endChar = edit.range.end.character
                lines.append("Edit \(index + 1): [\(startLine):\(startChar) - \(endLine):\(endChar)]")
                if edit.newText.isEmpty {
                    lines.append("  Delete text in range")
                } else {
                    lines.append("  New text: \(edit.newText)")
                }
            }
            text = lines.joined(separator: "\n")
        }

        TraceLog.exit([("textLength", text.count)])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }
}
