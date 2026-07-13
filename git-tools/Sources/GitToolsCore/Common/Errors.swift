import Foundation

enum GitToolsError: LocalizedError, Sendable {
    case processSpawnFailed(String)
    case processTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .processSpawnFailed(let reason):
            return "Failed to spawn process: \(reason)"
        case .processTimedOut(let reason):
            return "Process timed out: \(reason)"
        }
    }
}
