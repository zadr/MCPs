@preconcurrency import Foundation
import Darwin
import Logging
import os

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
        let invocation = "\(executable) \(arguments.joined(separator: " "))"
        let cwdSuffix = workingDirectory.map { " (cwd: \($0))" } ?? ""
        let timeoutSuffix = timeout.map { " (timeout: \(Int($0))s)" } ?? ""
        let start = Date()
        logger.info("shell: start \(invocation)\(cwdSuffix)\(timeoutSuffix)")

        // Separate stdout and stderr pipes so the child sees distinct fds for
        // 1 and 2, as a shell would. Some tools misbehave when both share a
        // backing pipe.
        var stdoutFDs: [Int32] = [-1, -1]
        var stderrFDs: [Int32] = [-1, -1]
        let stdoutPipeResult = stdoutFDs.withUnsafeMutableBufferPointer { ptr in pipe(ptr.baseAddress) }
        if stdoutPipeResult != 0 {
            throw GitToolsError.processSpawnFailed("pipe(stdout): \(String(cString: strerror(errno)))")
        }
        let stderrPipeResult = stderrFDs.withUnsafeMutableBufferPointer { ptr in pipe(ptr.baseAddress) }
        if stderrPipeResult != 0 {
            close(stdoutFDs[0]); close(stdoutFDs[1])
            throw GitToolsError.processSpawnFailed("pipe(stderr): \(String(cString: strerror(errno)))")
        }
        let stdoutReadFD = stdoutFDs[0]
        let stdoutWriteFD = stdoutFDs[1]
        let stderrReadFD = stderrFDs[0]
        let stderrWriteFD = stderrFDs[1]

        let devnullFD = open("/dev/null", O_RDWR | O_CLOEXEC)
        if devnullFD < 0 {
            close(stdoutReadFD); close(stdoutWriteFD); close(stderrReadFD); close(stderrWriteFD)
            throw GitToolsError.processSpawnFailed("open(/dev/null): \(String(cString: strerror(errno)))")
        }

        var fileActions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_adddup2(&fileActions, devnullFD, 0)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutWriteFD, 1)
        posix_spawn_file_actions_adddup2(&fileActions, stderrWriteFD, 2)

        if let workingDirectory {
            let chdirResult = workingDirectory.withCString { cstr in
                posix_spawn_file_actions_addchdir_np(&fileActions, cstr)
            }
            if chdirResult != 0 {
                close(stdoutReadFD); close(stdoutWriteFD)
                close(stderrReadFD); close(stderrWriteFD); close(devnullFD)
                throw GitToolsError.processSpawnFailed("addchdir(\(workingDirectory)): \(String(cString: strerror(chdirResult)))")
            }
        }

        var spawnAttr = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&spawnAttr)
        defer { posix_spawnattr_destroy(&spawnAttr) }

        // CLOEXEC_DEFAULT closes every fd at exec except those listed in file
        // actions — keeps JSON-RPC stdio, build locks, and other host fds out
        // of the child. SETSID makes the child its own session+pgroup leader
        // atomically. SETSIGMASK+SETSIGDEF normalize signal state.
        let flags: Int32 = Int32(POSIX_SPAWN_CLOEXEC_DEFAULT) | Int32(POSIX_SPAWN_SETSID)
            | Int32(POSIX_SPAWN_SETSIGMASK) | Int32(POSIX_SPAWN_SETSIGDEF)
        posix_spawnattr_setflags(&spawnAttr, Int16(flags))

        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigmask(&spawnAttr, &emptyMask)

        var fullMask = sigset_t()
        sigfillset(&fullMask)
        posix_spawnattr_setsigdefault(&spawnAttr, &fullMask)

        let argv: [UnsafeMutablePointer<CChar>?] =
            ([executable] + arguments).map { strdup($0) } + [nil]
        defer {
            for ptr in argv where ptr != nil { free(ptr) }
        }

        let envp: [UnsafeMutablePointer<CChar>?] =
            ProcessInfo.processInfo.environment.map { key, value in
                strdup("\(key)=\(value)")
            } + [nil]
        defer {
            for ptr in envp where ptr != nil { free(ptr) }
        }

        var pid: pid_t = 0
        let spawnResult = argv.withUnsafeBufferPointer { argvPtr in
            envp.withUnsafeBufferPointer { envpPtr in
                posix_spawn(
                    &pid,
                    executable,
                    &fileActions,
                    &spawnAttr,
                    UnsafeMutablePointer(mutating: argvPtr.baseAddress),
                    UnsafeMutablePointer(mutating: envpPtr.baseAddress)
                )
            }
        }

        // Parent must close its end of the pipe write fds so the read side
        // sees EOF when the child exits.
        close(stdoutWriteFD)
        close(stderrWriteFD)
        close(devnullFD)

        if spawnResult != 0 {
            close(stdoutReadFD)
            close(stderrReadFD)
            logger.error("shell: posix_spawn failed \(invocation): \(String(cString: strerror(spawnResult)))")
            throw GitToolsError.processSpawnFailed(
                "\(invocation): posix_spawn: \(String(cString: strerror(spawnResult)))"
            )
        }

        // Register pgid (== pid via SETSID) so the server shutdown handler
        // can reap if the host disconnects mid-call.
        ChildProcessRegistry.register(pid)
        defer { ChildProcessRegistry.unregister(pid) }
        logger.debug("shell: pid \(pid) (pgid \(pid)) running \(invocation)")
        EventLog.write(event: "shell_start", [
            ("child_pid", Int(pid)),
            ("child_pgid", Int(pid)),
            ("executable", executable),
            ("argc", arguments.count),
            ("cwd", workingDirectory ?? ""),
            ("timeout_seconds", timeout.map { Int($0) } as Any?),
        ])

        // Drain stdout and stderr via separate dispatch read sources into a
        // shared buffer. EOF requires both sources to signal closed.
        let buffer = OutputBuffer(expectedWriters: 2)

        func makeDrain(fd: Int32, label: String) -> DispatchSourceRead {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
            source.setEventHandler {
                let avail = Int(source.data)
                if avail <= 0 {
                    // Cancel on any zero/error reading. Leaving the source
                    // armed on a dead fd produces a 100%-CPU kevent storm.
                    source.cancel()
                    return
                }
                var chunk = Data(count: avail)
                let n = chunk.withUnsafeMutableBytes { rawPtr -> ssize_t in
                    guard let base = rawPtr.baseAddress else { return 0 }
                    return Darwin.read(fd, base, avail)
                }
                if n > 0 {
                    chunk.count = n
                    Task { await buffer.append(chunk) }
                } else {
                    source.cancel()
                }
            }
            source.setCancelHandler {
                close(fd)
                Task { await buffer.markWriterClosed() }
            }
            source.resume()
            return source
        }

        // Sources kept alive by the closures they own; assignments suppress
        // unused-let warnings.
        let stdoutDrain = makeDrain(fd: stdoutReadFD, label: "stdout")
        let stderrDrain = makeDrain(fd: stderrReadFD, label: "stderr")
        _ = stdoutDrain
        _ = stderrDrain

        // Watch child exit via kqueue NOTE_EXIT rather than blocking waitpid.
        // A blocking waitpid would pin a Swift Concurrency cooperative worker
        // for the lifetime of the child, starving timers and other awaits.
        let exitBox = ExitBox()
        let childPID = pid
        let exitSource = DispatchSource.makeProcessSource(
            identifier: childPID, eventMask: .exit, queue: .global()
        )
        exitSource.setEventHandler { [exitSource] in
            var status: Int32 = 0
            var result = waitpid(childPID, &status, WNOHANG)
            if result == 0 || (result < 0 && errno == EINTR) {
                result = waitpid(childPID, &status, 0)
            }
            let exitCode: Int32
            if result == childPID {
                if (status & 0x7f) == 0 {
                    exitCode = (status >> 8) & 0xff
                } else {
                    exitCode = 128 + (status & 0x7f)
                }
            } else {
                exitCode = -1
            }
            Task { await exitBox.set(exitCode) }
            exitSource.cancel()
        }
        exitSource.resume()
        _ = exitSource

        let capturedPID = pid

        // Watchdog timer outside Swift Concurrency that SIGKILLs the
        // descendant tree at timeout+5s. Guarantees cleanup even if the
        // cooperative pool is starved and the in-task timeout race never
        // resumes.
        let watchdog: DispatchSourceTimer?
        if let timeout {
            watchdog = makeDispatchTimer(seconds: timeout + 5) {
                let groups = descendantProcessGroupIDs(of: capturedPID)
                logger.warning("shell: watchdog firing at timeout+5s, killing \(groups.count) pgroup(s) for pid \(capturedPID)")
                for pgid in groups {
                    _ = kill(-pgid, SIGKILL)
                }
            }
        } else {
            watchdog = nil
        }
        defer { watchdog?.cancel() }

        // On task cancellation (e.g. host sent notifications/cancelled), kill
        // the descendant tree synchronously before the function unwinds —
        // otherwise the child stays alive holding locks.
        return try await withTaskCancellationHandler {
            try await runBody(
                pid: capturedPID,
                invocation: invocation,
                start: start,
                timeout: timeout,
                exitBox: exitBox,
                buffer: buffer
            )
        } onCancel: {
            let groups = descendantProcessGroupIDs(of: capturedPID)
            for pgid in groups {
                _ = kill(-pgid, SIGKILL)
            }
        }
    }

    private static func runBody(
        pid: pid_t,
        invocation: String,
        start: Date,
        timeout: TimeInterval?,
        exitBox: ExitBox,
        buffer: OutputBuffer
    ) async throws -> Result {
        let timedOut: Bool
        if let timeout {
            timedOut = await raceTimeout(seconds: timeout, exitBox: exitBox)
            if timedOut {
                // Snapshot pgids before SIGTERM: once the root dies, any
                // child that escaped into its own session/pgroup (e.g. via
                // setsid) is reparented to launchd and our walk loses it.
                let groups = descendantProcessGroupIDs(of: pid)
                logger.warning("shell: timeout after \(Int(timeout))s, terminating \(groups.count) pgroup(s) for \(invocation)")
                for pgid in groups {
                    _ = kill(-pgid, SIGTERM)
                }
                let stillRunning = await raceTimeout(seconds: 5, exitBox: exitBox)
                if stillRunning {
                    logger.warning("shell: \(groups.count) pgroup(s) ignored SIGTERM, sending SIGKILL")
                    for pgid in groups {
                        _ = kill(-pgid, SIGKILL)
                    }
                    _ = await raceTimeout(seconds: 5, exitBox: exitBox)
                }
            }
        } else {
            timedOut = false
            _ = await exitBox.wait()
        }

        // On the timeout path a surviving descendant may still hold the pipe
        // write end and prevent EOF; bound the wait.
        if timedOut {
            await waitForEOFBounded(buffer: buffer, seconds: 2)
        } else {
            await buffer.waitForEOF()
        }
        let data = await buffer.drain()
        let output = String(data: data, encoding: .utf8) ?? ""
        let elapsed = Date().timeIntervalSince(start)

        if timedOut {
            logger.error(
                "shell: timed out after \(String(format: "%.2fs", elapsed)) bytes=\(data.count) pid=\(pid) \(invocation)"
            )
            EventLog.write(event: "shell_timeout", [
                ("child_pid", Int(pid)),
                ("elapsed_seconds", elapsed),
                ("bytes", data.count),
                ("timeout_seconds", Int(timeout ?? 0)),
            ])
            throw GitToolsError.processTimedOut(
                "\(invocation) did not finish within \(Int(timeout ?? 0))s"
            )
        }

        let exitCode = await exitBox.wait()
        logger.info(
            "shell: exit \(exitCode) in \(String(format: "%.2fs", elapsed)) bytes=\(data.count) pid=\(pid) \(invocation)"
        )
        EventLog.write(event: "shell_exit", [
            ("child_pid", Int(pid)),
            ("exit_code", Int(exitCode)),
            ("elapsed_seconds", elapsed),
            ("bytes", data.count),
        ])

        return Result(output: output, exitCode: exitCode)
    }

    /// Wait for both pipe drains to signal EOF, giving up after `seconds`.
    /// Uses DispatchSourceTimer (not Task.sleep) so it isn't starved by
    /// cooperative-pool contention.
    private static func waitForEOFBounded(buffer: OutputBuffer, seconds: TimeInterval) async {
        let signal = AsyncSignal()
        let timer = makeDispatchTimer(seconds: seconds) {
            signal.fire()
        }
        defer { timer.cancel() }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await buffer.waitForEOF()
            }
            group.addTask {
                await signal.wait()
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Returns true if the timeout fired before the process exited.
    private static func raceTimeout(seconds: TimeInterval, exitBox: ExitBox) async -> Bool {
        let signal = AsyncSignal()
        let timer = makeDispatchTimer(seconds: seconds) {
            signal.fire()
        }
        defer { timer.cancel() }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await signal.wait()
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

    /// Dedicated queue for our timers. Must not be `.global()` — that pool
    /// is shared with Swift Concurrency's cooperative workers and can be
    /// starved; a dedicated queue gets its own libdispatch thread.
    private static let timerQueue = DispatchQueue(
        label: "apple-tools-mcp.shell.timer",
        qos: .userInitiated
    )

    /// One-shot DispatchSourceTimer that fires after `seconds`. Caller must
    /// `.cancel()` it (safe even after firing).
    private static func makeDispatchTimer(
        seconds: TimeInterval,
        handler: @escaping @Sendable () -> Void
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
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

/// One-shot async signal: `await wait()` blocks until any call to `fire()`.
/// Lock-based (not an actor) so `fire()` can be invoked synchronously from a
/// DispatchSource handler without needing a Swift Concurrency worker.
private final class AsyncSignal: @unchecked Sendable {
    private struct State {
        var fired = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func fire() {
        let toResume = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            if s.fired { return [] }
            s.fired = true
            let pending = s.waiters
            s.waiters.removeAll()
            return pending
        }
        for waiter in toResume {
            waiter.resume()
        }
    }

    func wait() async {
        let alreadyFired = state.withLock { s -> Bool in s.fired }
        if alreadyFired { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Re-check under lock: fire() may have raced after the fast path.
            let shouldResume = state.withLock { s -> Bool in
                if s.fired { return true }
                s.waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
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
    private var closedWriters = 0
    private let expectedWriters: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(expectedWriters: Int) {
        self.expectedWriters = expectedWriters
    }

    func append(_ chunk: Data) {
        data.append(chunk)
    }

    func markWriterClosed() {
        closedWriters += 1
        if closedWriters >= expectedWriters {
            let pending = waiters
            waiters.removeAll()
            for waiter in pending {
                waiter.resume()
            }
        }
    }

    func drain() -> Data {
        let out = data
        data = Data()
        return out
    }

    func waitForEOF() async {
        if closedWriters >= expectedWriters { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }
}
