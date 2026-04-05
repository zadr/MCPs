import AppleToolsCore
import MCP
import Logging
import Foundation

LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardError(label: label)
    handler.logLevel = .info
    return handler
}
let logger = Logger(label: "apple-tools-mcp")

let lspService = SourceKitLSPService(logger: logger)

let server = Server(
    name: "apple-tools-mcp",
    version: "0.1.0",
    instructions: "Provides access to Apple developer tools. Currently supports Swift language intelligence via SourceKit-LSP. Tools require absolute file paths and 0-indexed line/character positions.",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

await ToolRegistry.registerAll(on: server, lspService: lspService)

let transport = StdioTransport(logger: logger)

logger.info("apple-tools-mcp starting")

try await server.start(transport: transport)

// Keep alive — server.start returns when the transport disconnects,
// but add a fallback sleep in case it returns early.
while !Task.isCancelled {
    try await Task.sleep(for: .seconds(60 * 60 * 24))
}
