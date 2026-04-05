import MCP

enum SwiftHoverTool {
    static let name = "swift_hover"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Get type information and documentation for a symbol at a position in a Swift file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filePath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the Swift file"),
                    ]),
                    "line": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed line number"),
                    ]),
                    "character": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed character offset in the line"),
                    ]),
                ]),
                "required": .array([.string("filePath"), .string("line"), .string("character")]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        )
    }

    static func handle(
        _ arguments: [String: Value]?,
        lspService: SourceKitLSPService
    ) async throws -> CallTool.Result {
        guard let args = arguments,
              let filePath = args["filePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: filePath")
        }
        guard let line = args["line"]?.intValue ?? args["line"]?.doubleValue.map({ Int($0) }) else {
            throw MCPError.invalidParams("Missing required argument: line")
        }
        guard let character = args["character"]?.intValue ?? args["character"]?.doubleValue.map({ Int($0) }) else {
            throw MCPError.invalidParams("Missing required argument: character")
        }

        let uri = FileURI.fromPath(filePath)
        let result = try await lspService.hover(uri: uri, line: line, character: character)

        let text: String
        if let result {
            text = Self.stripMarkdownFences(result.contents)
        } else {
            text = "No hover information available at this position."
        }

        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    /// Strips markdown code fences from LSP hover content.
    private static func stripMarkdownFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove opening ```swift or ``` and closing ```
        if result.hasPrefix("```") {
            // Drop first line (```swift or ```)
            if let newline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newline)...])
            }
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
