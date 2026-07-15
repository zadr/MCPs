import GitToolsCore
import MCP
import Logging
import Foundation
import Dispatch

LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardError(label: label)
    handler.logLevel = .info
    return handler
}
let logger = Logger(label: "git-tools-mcp")

// Install signal handlers before any child can be spawned so shutdown
// always reaps. SIG_IGN keeps the default disposition from killing us
// before DispatchSourceSignal observes the signal.
let shutdownSignals: [Int32] = [SIGTERM, SIGINT, SIGHUP]
var signalSources: [DispatchSourceSignal] = []
for sig in shutdownSignals {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    source.setEventHandler {
        let count = ChildProcessRegistry.snapshot().count
        logger.warning("git-tools-mcp received signal \(sig); reaping \(count) child process group(s)")
        EventLog.write(event: "server_shutdown", [
            ("reason", "signal"),
            ("signal", Int(sig)),
            ("inflight_children", count),
        ])
        terminateAllChildProcessGroups()
        // _exit, not exit: atexit handlers can deadlock when stderr is gone.
        _exit(0)
    }
    source.resume()
    signalSources.append(source)
}

let server = Server(
    name: "git-tools-mcp",
    version: "0.1.0",
    instructions: "Provides git version control operations. The git-core tool is a comprehensive low-level git frontend; the git-stack tool manages stacked-branch workflows (parent/child topology tracked in git config); the github-tools tool wraps the gh CLI for GitHub pull request operations.",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

await ToolRegistry.registerAll(on: server)

// Custom transport — the SDK's StdioTransport polls stdin with Task.sleep
// on EAGAIN and saturates the cooperative pool. See DispatchStdioTransport.
let transport = DispatchStdioTransport(logger: logger)

logger.info("git-tools-mcp starting")
EventLog.write(event: "server_started", [
    ("version", "0.1.0"),
    ("argv0", CommandLine.arguments.first ?? ""),
])

do {
    try await server.start(transport: transport)
} catch {
    logger.error("git-tools-mcp server.start threw: \(error)")
    EventLog.write(event: "server_shutdown", [
        ("reason", "server_start_threw"),
        ("error", String(describing: error)),
    ])
    terminateAllChildProcessGroups()
    _exit(1)
}

// server.start() returns once the transport is wired; waitUntilCompleted
// blocks until the SDK's receive loop exits (transport EOF, error, stop()).
await server.waitUntilCompleted()

logger.info("git-tools-mcp transport completed; shutting down")
let inflight = ChildProcessRegistry.snapshot().count
if inflight > 0 {
    logger.warning("git-tools-mcp shutting down with \(inflight) child process group(s) still running; reaping")
    terminateAllChildProcessGroups()
}
EventLog.write(event: "server_shutdown", [
    ("reason", "transport_completed"),
    ("inflight_children", inflight),
])
_exit(0)
