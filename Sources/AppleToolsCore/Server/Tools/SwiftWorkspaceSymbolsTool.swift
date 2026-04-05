import Foundation
import MCP

enum SwiftWorkspaceSymbolsTool {
    static let name = "swift_workspace_symbols"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Search for symbols across the workspace by name",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search query to match symbol names against"),
                    ]),
                ]),
                "required": .array([.string("query")]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        )
    }

    static func handle(
        _ arguments: [String: Value]?,
        lspService: SourceKitLSPService
    ) async throws -> CallTool.Result {
        guard let args = arguments,
              let query = args["query"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: query")
        }

        let symbols = try await lspService.workspaceSymbols(query: query)

        let text: String
        if symbols.isEmpty {
            text = "No symbols found matching \"\(query)\"."
        } else {
            var lines: [String] = []
            for symbol in symbols {
                let kindName = LSPSymbolKind(rawValue: symbol.kind)?.description ?? "Unknown"
                let file = (FileURI.toPath(symbol.location.uri) as NSString).lastPathComponent
                var entry = "\(kindName) \(symbol.name) (\(file):\(symbol.location.range.start.line))"
                if let container = symbol.containerName, !container.isEmpty {
                    entry += " in \(container)"
                }
                lines.append(entry)
            }
            text = lines.joined(separator: "\n")
        }

        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }
}
