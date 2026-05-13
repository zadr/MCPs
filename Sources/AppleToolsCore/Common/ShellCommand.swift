@preconcurrency import Foundation
import Logging

enum ShellCommand {
    struct Result: Sendable {
        let output: String
        let exitCode: Int32
    }

    private static let logger = Logger(label: "apple-tools-mcp.shell")

    static func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval? = nil
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

        let buffer = OutputBuffer()
        let readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                Task { await buffer.markEOF() }
            } else {
                Task { await buffer.append(chunk) }
            }
        }

        let exitBox = ExitBox()
        process.terminationHandler = { proc in
            Task { await exitBox.set(proc.terminationStatus) }
        }

        let logger = Self.logger
        let invocation = "\(executable) \(arguments.joined(separator: " "))"
        let cwdSuffix = workingDirectory.map { " (cwd: \($0))" } ?? ""
        let timeoutSuffix = timeout.map { " (timeout: \(Int($0))s)" } ?? ""
        let start = Date()
        logger.info("shell: start \(invocation)\(cwdSuffix)\(timeoutSuffix)")

        do {
            try process.run()
        } catch {
            readHandle.readabilityHandler = nil
            logger.error("shell: spawn failed \(invocation): \(error.localizedDescription)")
            throw AppleToolsError.processSpawnFailed(
                "\(invocation): \(error.localizedDescription)"
            )
        }

        let pid = process.processIdentifier
        logger.debug("shell: pid \(pid) running \(invocation)")

        let timedOut: Bool
        if let timeout {
            timedOut = await raceTimeout(seconds: timeout, exitBox: exitBox)
            if timedOut {
                logger.warning("shell: timeout after \(Int(timeout))s, terminating pid \(pid) \(invocation)")
                process.terminate()
                // Grace period for SIGTERM, then SIGKILL.
                let killed = await raceTimeout(seconds: 5, exitBox: exitBox)
                if killed {
                    logger.warning("shell: pid \(pid) ignored SIGTERM, sending SIGKILL")
                    kill(pid, SIGKILL)
                    _ = await exitBox.wait()
                }
            }
        } else {
            timedOut = false
            _ = await exitBox.wait()
        }

        await buffer.waitForEOF()
        let data = await buffer.drain()
        let output = String(data: data, encoding: .utf8) ?? ""
        let elapsed = Date().timeIntervalSince(start)

        if timedOut {
            logger.error(
                "shell: timed out after \(String(format: "%.2fs", elapsed)) bytes=\(data.count) pid=\(pid) \(invocation)"
            )
            throw AppleToolsError.processTimedOut(
                "\(invocation) did not finish within \(Int(timeout ?? 0))s"
            )
        }

        let exitCode = await exitBox.wait()
        logger.info(
            "shell: exit \(exitCode) in \(String(format: "%.2fs", elapsed)) bytes=\(data.count) pid=\(pid) \(invocation)"
        )

        return Result(output: output, exitCode: exitCode)
    }

    /// Returns true if the timeout fired before the process exited.
    private static func raceTimeout(seconds: TimeInterval, exitBox: ExitBox) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return true   // timeout fired
            }
            group.addTask {
                _ = await exitBox.wait()
                return false  // process exited
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Convenience to run and return output, trimming trailing whitespace.
    static func runAndTrim(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Result {
        let result = try await run(
            executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        )
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

private actor ExitBox {
    private var value: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    func set(_ status: Int32) {
        if value != nil { return }
        value = status
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: status)
        }
    }

    func wait() async -> Int32 {
        if let value { return value }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            waiters.append(continuation)
        }
    }
}

private actor OutputBuffer {
    private var data = Data()
    private var eof = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func append(_ chunk: Data) {
        data.append(chunk)
    }

    func markEOF() {
        eof = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func drain() -> Data {
        let out = data
        data = Data()
        return out
    }

    func waitForEOF() async {
        if eof { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }
}
