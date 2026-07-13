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
        TraceLog.enter([("arguments", String(describing: arguments))])
        guard let args = arguments,
              let filePath = args["filePath"]?.stringValue else {
            TraceLog.point("missing-filePath")
            throw MCPError.invalidParams("Missing required argument: filePath")
        }
        TraceLog.point("args-ok", [("filePath", filePath)])

        let uri = FileURI.fromPath(filePath)
        let symbols = try await lspService.documentSymbols(uri: uri)

        let text: String
        if symbols.isEmpty {
            TraceLog.point("symbols-empty")
            text = "No symbols found."
        } else {
            TraceLog.point("symbols-present", [("count", symbols.count)])
            var lines: [String] = []
            for symbol in symbols {
                formatSymbol(symbol, indent: 0, into: &lines)
            }
            text = lines.joined(separator: "\n")
        }

        TraceLog.exit([("textLength", text.count)])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func formatSymbol(_ symbol: DocumentSymbol, indent: Int, into lines: inout [String]) {
        TraceLog.enter([("name", symbol.name), ("indent", indent)])
        let kind = LSPSymbolKind(rawValue: symbol.kind)
        // Skip MARK/TODO comments (they show up as namespace kind with "- " prefix)
        if kind == .namespace {
            TraceLog.point("skip-namespace")
            return
        }

        let prefix = String(repeating: "  ", count: indent)
        let kindName = kind?.description.lowercased() ?? "unknown"
        let line = symbol.selectionRange.start.line
        lines.append("\(prefix)\(kindName) \(symbol.name) L\(line)")

        if let children = symbol.children {
            TraceLog.point("has-children", [("count", children.count)])
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
            TraceLog.point("children-grouped", [("groupCount", groups.count)])
            let childPrefix = String(repeating: "  ", count: indent + 1)
            let memberPrefix = String(repeating: "  ", count: indent + 2)
            for (groupKind, members) in groups {
                if members.count == 1 {
                    TraceLog.point("group-single", [("groupKind", groupKind)])
                    let m = members[0]
                    let mLine = m.selectionRange.start.line
                    lines.append("\(childPrefix)\(groupKind) \(m.name) L\(mLine)")
                    if let grandchildren = m.children, !grandchildren.isEmpty {
                        for gc in grandchildren {
                            formatSymbol(gc, indent: indent + 2, into: &lines)
                        }
                    }
                } else {
                    TraceLog.point("group-plural", [("groupKind", groupKind), ("memberCount", members.count)])
                    let plural = groupKind.hasSuffix("y")
                        ? String(groupKind.dropLast()) + "ies"
                        : groupKind + "s"
                    lines.append("\(childPrefix)\(plural):")
                    for m in members {
                        let mLine = m.selectionRange.start.line
                        lines.append("\(memberPrefix)\(m.name) L\(mLine)")
                        if let grandchildren = m.children, !grandchildren.isEmpty {
                            for gc in grandchildren {
                                formatSymbol(gc, indent: indent + 3, into: &lines)
                            }
                        }
                    }
                }
            }
        }
        TraceLog.exit([("name", symbol.name)])
    }
}
