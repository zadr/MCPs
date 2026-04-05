import Foundation

enum ShellCommand {
    struct Result: Sendable {
        let output: String
        let exitCode: Int32
    }

    static func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw AppleToolsError.processSpawnFailed(
                "\(executable) \(arguments.joined(separator: " ")): \(error.localizedDescription)"
            )
        }

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pipe.fileHandleForReading.readabilityHandler = nil
            let allData = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: allData)
        }

        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return Result(output: output, exitCode: process.terminationStatus)
    }

    /// Convenience to run and return output, trimming trailing whitespace.
    static func runAndTrim(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil
    ) async throws -> Result {
        let result = try await run(executable, arguments: arguments, workingDirectory: workingDirectory)
        return Result(
            output: result.output.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: result.exitCode
        )
    }

    /// Returns the last N lines of the output, useful for large build logs.
    static func tailLines(_ text: String, count: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count <= count {
            return text
        }
        let kept = lines.suffix(count)
        return "... (\(lines.count - count) lines truncated)\n" + kept.joined(separator: "\n")
    }
}
