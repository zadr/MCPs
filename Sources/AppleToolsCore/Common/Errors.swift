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
        switch self {
        case .sourceKitLSPNotFound:
            return "Could not find sourcekit-lsp. Ensure Xcode or Swift toolchain is installed."
        case .lspNotInitialized:
            return "LSP client is not initialized."
        case .invalidFilePath(let path):
            return "Invalid file path: \(path)"
        case .lspRequestFailed(let method, let message):
            return "LSP request '\(method)' failed: \(message)"
        case .jsonRPCError(let code, let message):
            return "JSON-RPC error \(code): \(message)"
        case .invalidArgument(let name, let expected):
            return "Invalid argument '\(name)': expected \(expected)"
        case .missingRequiredArgument(let name):
            return "Missing required argument: \(name)"
        case .processSpawnFailed(let reason):
            return "Failed to spawn process: \(reason)"
        case .processTimedOut(let reason):
            return "Process timed out: \(reason)"
        }
    }
}
