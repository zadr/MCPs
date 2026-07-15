import MCP

public enum ToolRegistry {
    public static func registerAll(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            var tools = [
                GitTool.definition,
                GitStackTool.definition,
            ]
            // gh is optional: only advertise github-tools when it is installed.
            if GitHubTool.isAvailable {
                tools.append(GitHubTool.definition)
            }
            return ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case GitTool.name:
                return try await GitTool.handle(params.arguments)
            case GitStackTool.name:
                return try await GitStackTool.handle(params.arguments)
            case GitHubTool.name:
                return try await GitHubTool.handle(params.arguments)
            default:
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
        }
    }
}
