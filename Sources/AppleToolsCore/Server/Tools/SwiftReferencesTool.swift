import MCP

enum SwiftReferencesTool {
    static let name = "swift_references"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Find all references to a symbol at a position in a Swift file",
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
                    "includeDeclaration": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether to include the declaration itself in the results (default: true)"),
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
        TraceLog.enter([("arguments", String(describing: arguments))])
        guard let args = arguments,
              let filePath = args["filePath"]?.stringValue else {
            TraceLog.point("missing-filePath")
            throw MCPError.invalidParams("Missing required argument: filePath")
        }
        guard let line = args["line"]?.intValue ?? args["line"]?.doubleValue.map({ Int($0) }) else {
            TraceLog.point("missing-line")
            throw MCPError.invalidParams("Missing required argument: line")
        }
        guard let character = args["character"]?.intValue ?? args["character"]?.doubleValue.map({ Int($0) }) else {
            TraceLog.point("missing-character")
            throw MCPError.invalidParams("Missing required argument: character")
        }

        let includeDeclaration: Bool
        if let val = args["includeDeclaration"]?.boolValue {
            TraceLog.point("includeDeclaration-explicit", [("value", val)])
            includeDeclaration = val
        } else {
            TraceLog.point("includeDeclaration-default")
            includeDeclaration = true
        }

        let uri = FileURI.fromPath(filePath)
        let locations = try await lspService.references(
            uri: uri,
            line: line,
            character: character,
            includeDeclaration: includeDeclaration
        )

        let text: String
        if locations.isEmpty {
            TraceLog.point("locations-empty")
            text = "No references found at this position."
        } else {
            TraceLog.point("locations-present", [("count", locations.count)])
            let lines = locations.map { location -> String in
                let path = FileURI.toPath(location.uri)
                let startLine = location.range.start.line
                let startChar = location.range.start.character
                return "\(path):\(startLine):\(startChar)"
            }
            text = lines.joined(separator: "\n")
        }

        TraceLog.exit([("textLength", text.count)])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }
}
