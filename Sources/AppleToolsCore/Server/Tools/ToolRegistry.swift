import MCP

public enum ToolRegistry {
    public static func registerAll(on server: Server, lspService: SourceKitLSPService) async {
        TraceLog.enter()
        await server.withMethodHandler(ListTools.self) { _ in
            TraceLog.point("list-tools")
            return ListTools.Result(tools: [
                SwiftTool.definition,
                XcodebuildTool.definition,
                NotarytoolTool.definition,
                SwiftLintTool.definition,
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            TraceLog.point("call-tool", [("name", params.name)])
            switch params.name {
            case SwiftTool.name:
                TraceLog.point("dispatch:swift", [("name", params.name)])
                return try await SwiftTool.handle(params.arguments, lspService: lspService)
            case XcodebuildTool.name:
                TraceLog.point("dispatch:xcodebuild", [("name", params.name)])
                return try await XcodebuildTool.handle(params.arguments)
            case NotarytoolTool.name:
                TraceLog.point("dispatch:notarytool", [("name", params.name)])
                return try await NotarytoolTool.handle(params.arguments)
            case SwiftLintTool.name:
                TraceLog.point("dispatch:swiftlint", [("name", params.name)])
                return try await SwiftLintTool.handle(params.arguments)
            default:
                TraceLog.point("unknown-tool", [("name", params.name)])
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
        }
    }
}
