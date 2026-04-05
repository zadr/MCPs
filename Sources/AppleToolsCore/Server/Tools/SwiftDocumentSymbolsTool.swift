import MCP

enum SwiftDocumentSymbolsTool {
    static let name = "swift_document_symbols"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Get all symbols (functions, types, properties, etc.) in a Swift file",
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

        let uri = FileURI.fromPath(filePath)
        let symbols = try await lspService.documentSymbols(uri: uri)

        let text: String
        if symbols.isEmpty {
            text = "No symbols found."
        } else {
            var lines: [String] = []
            for symbol in symbols {
                formatSymbol(symbol, indent: 0, into: &lines)
            }
            text = lines.joined(separator: "\n")
        }

        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func formatSymbol(_ symbol: DocumentSymbol, indent: Int, into lines: inout [String]) {
        let kind = LSPSymbolKind(rawValue: symbol.kind)
        // Skip MARK/TODO comments (they show up as namespace kind with "- " prefix)
        if kind == .namespace { return }

        let prefix = String(repeating: "  ", count: indent)
        let kindName = kind?.description.lowercased() ?? "unknown"
        lines.append("\(prefix)\(kindName) \(symbol.name)")

        if let children = symbol.children {
            // Group children by kind
            var groups: [(String, [DocumentSymbol])] = []
            for child in children {
                let childKind = LSPSymbolKind(rawValue: child.kind)
                if childKind == .namespace { continue }
                let childKindName = childKind?.description.lowercased() ?? "unknown"
                if let last = groups.last, last.0 == childKindName {
                    groups[groups.count - 1].1.append(child)
                } else {
                    groups.append((childKindName, [child]))
                }
            }
            let childPrefix = String(repeating: "  ", count: indent + 1)
            let memberPrefix = String(repeating: "  ", count: indent + 2)
            for (groupKind, members) in groups {
                if members.count == 1 {
                    // Single member — inline the kind
                    let m = members[0]
                    lines.append("\(childPrefix)\(groupKind) \(m.name)")
                    if let grandchildren = m.children, !grandchildren.isEmpty {
                        for gc in grandchildren {
                            formatSymbol(gc, indent: indent + 2, into: &lines)
                        }
                    }
                } else {
                    let plural = groupKind.hasSuffix("y")
                        ? String(groupKind.dropLast()) + "ies"
                        : groupKind + "s"
                    lines.append("\(childPrefix)\(plural):")
                    for m in members {
                        lines.append("\(memberPrefix)\(m.name)")
                        if let grandchildren = m.children, !grandchildren.isEmpty {
                            for gc in grandchildren {
                                formatSymbol(gc, indent: indent + 3, into: &lines)
                            }
                        }
                    }
                }
            }
        }
    }
}
