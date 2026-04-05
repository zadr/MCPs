import MCP

enum SwiftTool {
    static let name = "swift"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Swift language intelligence via SourceKit-LSP and Swift Package Manager. Provides hover info, go-to-definition, find references, completions, diagnostics, symbols, formatting, code actions, rename, build, and test.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("hover"),
                            .string("definition"),
                            .string("references"),
                            .string("completion"),
                            .string("diagnostics"),
                            .string("document_symbols"),
                            .string("workspace_symbols"),
                            .string("format"),
                            .string("code_actions"),
                            .string("rename"),
                            .string("build"),
                            .string("test"),
                        ]),
                        "description": .string("The action to perform. One of: hover, definition, references, completion, diagnostics, document_symbols, workspace_symbols, format, code_actions, rename, build, test"),
                    ]),
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
                        "description": .string("0-indexed character offset"),
                    ]),
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search query (for workspace_symbols)"),
                    ]),
                    "newName": .object([
                        "type": .string("string"),
                        "description": .string("New name (for rename)"),
                    ]),
                    "includeDeclaration": .object([
                        "type": .string("boolean"),
                        "description": .string("Include declaration in references (default: true)"),
                    ]),
                    "startLine": .object([
                        "type": .string("integer"),
                        "description": .string("Start line for code_actions range"),
                    ]),
                    "startCharacter": .object([
                        "type": .string("integer"),
                        "description": .string("Start character for code_actions range"),
                    ]),
                    "endLine": .object([
                        "type": .string("integer"),
                        "description": .string("End line for code_actions range (defaults to startLine)"),
                    ]),
                    "endCharacter": .object([
                        "type": .string("integer"),
                        "description": .string("End character for code_actions range (defaults to startCharacter)"),
                    ]),
                    "packagePath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to directory containing Package.swift (for build, test)"),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration: \"debug\" or \"release\" (default: \"debug\", for build)"),
                    ]),
                    "target": .object([
                        "type": .string("string"),
                        "description": .string("Specific target to build (for build)"),
                    ]),
                    "filter": .object([
                        "type": .string("string"),
                        "description": .string("Test filter, e.g. \"MyTests.testFoo\" (for test)"),
                    ]),
                    "parallel": .object([
                        "type": .string("boolean"),
                        "description": .string("Run tests in parallel (default: true, for test)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(readOnlyHint: false, openWorldHint: false)
        )
    }

    static func handle(
        _ arguments: [String: Value]?,
        lspService: SourceKitLSPService
    ) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: action")
        }

        switch action {
        case "hover":
            return try await SwiftHoverTool.handle(arguments, lspService: lspService)
        case "definition":
            return try await SwiftDefinitionTool.handle(arguments, lspService: lspService)
        case "references":
            return try await SwiftReferencesTool.handle(arguments, lspService: lspService)
        case "completion":
            return try await SwiftCompletionTool.handle(arguments, lspService: lspService)
        case "diagnostics":
            return try await SwiftDiagnosticsTool.handle(arguments, lspService: lspService)
        case "document_symbols":
            return try await SwiftDocumentSymbolsTool.handle(arguments, lspService: lspService)
        case "workspace_symbols":
            return try await SwiftWorkspaceSymbolsTool.handle(arguments, lspService: lspService)
        case "format":
            return try await SwiftFormatTool.handle(arguments, lspService: lspService)
        case "code_actions":
            return try await SwiftCodeActionsTool.handle(arguments, lspService: lspService)
        case "rename":
            return try await SwiftRenameTool.handle(arguments, lspService: lspService)
        case "build":
            return try await SwiftBuildTool.handle(arguments)
        case "test":
            return try await SwiftTestTool.handle(arguments)
        default:
            throw MCPError.invalidParams("Unknown action: \(action). Valid actions: hover, definition, references, completion, diagnostics, document_symbols, workspace_symbols, format, code_actions, rename, build, test")
        }
    }
}
