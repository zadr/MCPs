import Foundation

enum AppleToolsError: LocalizedError, Sendable {
    case sourceKitLSPNotFound
    case lspNotInitialized
    case invalidFilePath(String)
    case lspRequestFailed(method: String, message: String)
    case jsonRPCError(code: Int, message: String)
    case invalidArgument(name: String, expected: String)
    case missingRequiredArgument(String)
    case processSpawnFailed(String)
    case processTimedOut(String)

    var errorDescription: String? {
        TraceLog.enter()
        switch self {
        case .sourceKitLSPNotFound:
            TraceLog.point("case-sourceKitLSPNotFound")
            return "Could not find sourcekit-lsp. Ensure Xcode or Swift toolchain is installed."
        case .lspNotInitialized:
            TraceLog.point("case-lspNotInitialized")
            return "LSP client is not initialized."
        case .invalidFilePath(let path):
            TraceLog.point("case-invalidFilePath")
            return "Invalid file path: \(path)"
        case .lspRequestFailed(let method, let message):
            TraceLog.point("case-lspRequestFailed")
            return "LSP request '\(method)' failed: \(message)"
        case .jsonRPCError(let code, let message):
            TraceLog.point("case-jsonRPCError")
            return "JSON-RPC error \(code): \(message)"
        case .invalidArgument(let name, let expected):
            TraceLog.point("case-invalidArgument")
            return "Invalid argument '\(name)': expected \(expected)"
        case .missingRequiredArgument(let name):
            TraceLog.point("case-missingRequiredArgument")
            return "Missing required argument: \(name)"
        case .processSpawnFailed(let reason):
            TraceLog.point("case-processSpawnFailed")
            return "Failed to spawn process: \(reason)"
        case .processTimedOut(let reason):
            TraceLog.point("case-processTimedOut")
            return "Process timed out: \(reason)"
        }
    }
}
