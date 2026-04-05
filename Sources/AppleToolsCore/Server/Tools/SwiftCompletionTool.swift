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
        let completionList = try await lspService.completion(uri: uri, line: line, character: character)

        let items = completionList.items
        let text: String
        if items.isEmpty {
            text = "No completions available at this position."
        } else {
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
                lines.append("... \(items.count - 50) more")
            }
            text = lines.joined(separator: "\n")
        }

        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func completionItemKindName(_ kind: Int) -> String {
        switch kind {
        case 1: return "Text"
        case 2: return "Method"
        case 3: return "Function"
        case 4: return "Constructor"
        case 5: return "Field"
        case 6: return "Variable"
        case 7: return "Class"
        case 8: return "Interface"
        case 9: return "Module"
        case 10: return "Property"
        case 11: return "Unit"
        case 12: return "Value"
        case 13: return "Enum"
        case 14: return "Keyword"
        case 15: return "Snippet"
        case 16: return "Color"
        case 17: return "File"
        case 18: return "Reference"
        case 19: return "Folder"
        case 20: return "EnumMember"
        case 21: return "Constant"
        case 22: return "Struct"
        case 23: return "Event"
        case 24: return "Operator"
        case 25: return "TypeParameter"
        default: return "Unknown(\(kind))"
        }
    }
}
