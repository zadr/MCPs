import Foundation

/// Resolves the active swift binary via `xcode-select -p`. Cached after first call.
/// Falls back to `/usr/bin/swift` if resolution fails.
enum Toolchain {
    private static let cachedSwiftPath: String = {
        TraceLog.enter()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            TraceLog.point("run-failed", [("error", String(describing: error))])
            return "/usr/bin/swift"
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            TraceLog.point("nonzero-status", [("status", process.terminationStatus)])
            return "/usr/bin/swift"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let developerDir = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !developerDir.isEmpty else {
            TraceLog.point("empty-developerDir")
            return "/usr/bin/swift"
        }

        let candidate = "\(developerDir)/usr/bin/swift"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            TraceLog.point("candidate-executable", [("candidate", candidate)])
            return candidate
        } else {
            TraceLog.point("candidate-not-executable", [("candidate", candidate)])
            return "/usr/bin/swift"
        }
    }()

    static var swiftPath: String {
        TraceLog.enter()
        return cachedSwiftPath
    }
}
