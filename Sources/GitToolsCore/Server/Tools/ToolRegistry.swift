import MCP

public enum ToolRegistry {
    public static func registerAll(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                GitTool.definition,
                GitStackTool.definition,
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case GitTool.name:
                return try await GitTool.handle(params.arguments)
            case GitStackTool.name:
                return try await GitStackTool.handle(params.arguments)
            default:
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
        }
    }
}
