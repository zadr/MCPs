import MCP

enum SwiftDiagnosticsTool {
    static let name = "swift_diagnostics"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Get diagnostics (errors, warnings, notes) for a Swift file",
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
        let diagnostics = try await lspService.diagnostics(uri: uri)

        let text: String
        if diagnostics.isEmpty {
            TraceLog.point("diagnostics-empty")
            text = "No diagnostics found. The file appears to be clean."
        } else {
            TraceLog.point("diagnostics-present", [("count", diagnostics.count)])
            let lines = diagnostics.map { diagnostic -> String in
                let severity = severityName(diagnostic.severity)
                let line = diagnostic.range.start.line
                let character = diagnostic.range.start.character
                return "[\(severity)] \(line):\(character): \(diagnostic.message)"
            }
            text = "Found \(diagnostics.count) diagnostic(s):\n\n" + lines.joined(separator: "\n")
        }

        TraceLog.exit([("textLength", text.count)])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func severityName(_ severity: Int?) -> String {
        TraceLog.enter([("severity", severity)])
        let name: String
        switch severity {
        case 1: name = "Error"
        case 2: name = "Warning"
        case 3: name = "Information"
        case 4: name = "Hint"
        default: name = "Unknown"
        }
        TraceLog.exit([("name", name)])
        return name
    }
}
