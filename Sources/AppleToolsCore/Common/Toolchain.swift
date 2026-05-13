import Foundation

/// Resolves the active swift binary via `xcode-select -p`. Cached after first call.
/// Falls back to `/usr/bin/swift` if resolution fails.
enum Toolchain {
    private static let cachedSwiftPath: String = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return "/usr/bin/swift"
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return "/usr/bin/swift"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let developerDir = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !developerDir.isEmpty else {
            return "/usr/bin/swift"
        }

        let candidate = "\(developerDir)/usr/bin/swift"
        return FileManager.default.isExecutableFile(atPath: candidate)
            ? candidate
            : "/usr/bin/swift"
    }()

    static var swiftPath: String { cachedSwiftPath }
}
