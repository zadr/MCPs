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
        guard let args = arguments,
              let filePath = args["filePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: filePath")
        }

        let uri = FileURI.fromPath(filePath)
        let diagnostics = try await lspService.diagnostics(uri: uri)

        let text: String
        if diagnostics.isEmpty {
            text = "No diagnostics found. The file appears to be clean."
        } else {
            let lines = diagnostics.map { diagnostic -> String in
                let severity = severityName(diagnostic.severity)
                let line = diagnostic.range.start.line
                let character = diagnostic.range.start.character
                return "[\(severity)] \(line):\(character): \(diagnostic.message)"
            }
            text = "Found \(diagnostics.count) diagnostic(s):\n\n" + lines.joined(separator: "\n")
        }

        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func severityName(_ severity: Int?) -> String {
        switch severity {
        case 1: return "Error"
        case 2: return "Warning"
        case 3: return "Information"
        case 4: return "Hint"
        default: return "Unknown"
        }
    }
}
