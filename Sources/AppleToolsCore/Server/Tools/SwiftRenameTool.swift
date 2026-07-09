import MCP

enum SwiftRenameTool {
    static let name = "swift_rename"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Preview renaming a symbol across the project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filePath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the Swift file containing the symbol"),
                    ]),
                    "line": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed line number of the symbol"),
                    ]),
                    "character": .object([
                        "type": .string("integer"),
                        "description": .string("0-indexed character offset of the symbol"),
                    ]),
                    "newName": .object([
                        "type": .string("string"),
                        "description": .string("The new name for the symbol"),
                    ]),
                ]),
                "required": .array([
                    .string("filePath"),
                    .string("line"),
                    .string("character"),
                    .string("newName"),
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
        guard let line = args["line"]?.intValue ?? args["line"]?.doubleValue.map({ Int($0) }) else {
            TraceLog.point("missing-line")
            throw MCPError.invalidParams("Missing required argument: line")
        }
        guard let character = args["character"]?.intValue ?? args["character"]?.doubleValue.map({ Int($0) }) else {
            TraceLog.point("missing-character")
            throw MCPError.invalidParams("Missing required argument: character")
        }
        guard let newName = args["newName"]?.stringValue else {
            TraceLog.point("missing-newName")
            throw MCPError.invalidParams("Missing required argument: newName")
        }
        TraceLog.point("args-ok", [("filePath", filePath), ("line", line), ("character", character), ("newName", newName)])

        let uri = FileURI.fromPath(filePath)
        let workspaceEdit = try await lspService.rename(
            uri: uri,
            line: line,
            character: character,
            newName: newName
        )

        let text: String
        if let changes = workspaceEdit.changes, !changes.isEmpty {
            TraceLog.point("changes-present", [("fileCount", changes.count)])
            var lines: [String] = []
            lines.append("Rename preview (symbol -> \"\(newName)\"):")
            lines.append("")

            for (fileUri, edits) in changes {
                let path = FileURI.toPath(fileUri)
                lines.append("File: \(path)")
                for edit in edits {
                    let startLine = edit.range.start.line
                    let startChar = edit.range.start.character
                    let endLine = edit.range.end.line
                    let endChar = edit.range.end.character
                    lines.append("  [\(startLine):\(startChar) - \(endLine):\(endChar)] -> \"\(edit.newText)\"")
                }
                lines.append("")
            }

            let totalEdits = changes.values.reduce(0) { $0 + $1.count }
            lines.append("Total: \(totalEdits) edit(s) across \(changes.count) file(s)")
            text = lines.joined(separator: "\n")
        } else if let documentChanges = workspaceEdit.documentChanges, !documentChanges.isEmpty {
            TraceLog.point("documentChanges-present", [("count", documentChanges.count)])
            var lines: [String] = []
            lines.append("Rename preview (symbol -> \"\(newName)\"):")
            lines.append("")

            var totalEdits = 0
            var fileCount = 0
            for change in documentChanges {
                let path = FileURI.toPath(change.textDocument.uri)
                lines.append("File: \(path)")
                for edit in change.edits {
                    let startLine = edit.range.start.line
                    let startChar = edit.range.start.character
                    let endLine = edit.range.end.line
                    let endChar = edit.range.end.character
                    lines.append("  [\(startLine):\(startChar) - \(endLine):\(endChar)] -> \"\(edit.newText)\"")
                    totalEdits += 1
                }
                fileCount += 1
                lines.append("")
            }

            lines.append("Total: \(totalEdits) edit(s) across \(fileCount) file(s)")
            text = lines.joined(separator: "\n")
        } else {
            TraceLog.point("no-changes")
            text = "No changes produced by rename. The symbol may not be renameable at this position."
        }

        TraceLog.exit([("textLength", text.count)])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }
}
