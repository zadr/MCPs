import MCP

public enum ToolRegistry {
    public static func registerAll(on server: Server, lspService: SourceKitLSPService) async {
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                SwiftTool.definition,
                XcodebuildTool.definition,
                NotarytoolTool.definition,
                GitTool.definition,
                SwiftLintTool.definition,
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case SwiftTool.name:
                return try await SwiftTool.handle(params.arguments, lspService: lspService)
            case XcodebuildTool.name:
                return try await XcodebuildTool.handle(params.arguments)
            case NotarytoolTool.name:
                return try await NotarytoolTool.handle(params.arguments)
            case GitTool.name:
                return try await GitTool.handle(params.arguments)
            case SwiftLintTool.name:
                return try await SwiftLintTool.handle(params.arguments)
            default:
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
        }
    }
}
