import MCP

enum SwiftCompletionTool {
    static let name = "swift_completion"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Get code completions at a position in a Swift file",
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
        TraceLog.point("args-ok", [("filePath", filePath), ("line", line), ("character", character)])

        let uri = FileURI.fromPath(filePath)
        let completionList = try await lspService.completion(uri: uri, line: line, character: character)

        let items = completionList.items
        let text: String
        if items.isEmpty {
            TraceLog.point("items-empty")
            text = "No completions available at this position."
        } else {
            TraceLog.point("items-present", [("count", items.count)])
            let displayItems = items.prefix(50)
            var lines: [String] = []
            for item in displayItems {
                var entry = item.label
                if let detail = item.detail, !detail.isEmpty {
                    entry += " - \(detail)"
                }
                lines.append(entry)
            }
            if items.count > 50 {
                TraceLog.point("items-truncated", [("overflow", items.count - 50)])
                lines.append("... \(items.count - 50) more")
            }
            text = lines.joined(separator: "\n")
        }

        TraceLog.exit([("textLength", text.count)])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func completionItemKindName(_ kind: Int) -> String {
        TraceLog.enter([("kind", kind)])
        let name: String
        switch kind {
        case 1: name = "Text"
        case 2: name = "Method"
        case 3: name = "Function"
        case 4: name = "Constructor"
        case 5: name = "Field"
        case 6: name = "Variable"
        case 7: name = "Class"
        case 8: name = "Interface"
        case 9: name = "Module"
        case 10: name = "Property"
        case 11: name = "Unit"
        case 12: name = "Value"
        case 13: name = "Enum"
        case 14: name = "Keyword"
        case 15: name = "Snippet"
        case 16: name = "Color"
        case 17: name = "File"
        case 18: name = "Reference"
        case 19: name = "Folder"
        case 20: name = "EnumMember"
        case 21: name = "Constant"
        case 22: name = "Struct"
        case 23: name = "Event"
        case 24: name = "Operator"
        case 25: name = "TypeParameter"
        default: name = "Unknown(\(kind))"
        }
        TraceLog.exit([("name", name)])
        return name
    }
}
