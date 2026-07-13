@preconcurrency import Foundation
import Logging

/// Manages the sourcekit-lsp subprocess lifecycle.
actor LSPProcess {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
        TraceLog.point("init")
    }

    /// Starts the sourcekit-lsp process and returns the stdin/stdout file handles for communication.
    func start() async throws -> (input: FileHandle, output: FileHandle) {
        TraceLog.enter()
        let path = try await findSourceKitLSP()
        TraceLog.point("found-path", [("path", path)])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = []

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        TraceLog.point("pipes-configured")

        // Forward stderr to logger on a background thread
        let log = self.logger
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                TraceLog.point("stderr-data", [("length", text.count)])
                log.debug("sourcekit-lsp stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        do {
            try process.run()
            TraceLog.point("process-run-succeeded")
        } catch {
            TraceLog.point("process-run-failed", [("error", String(describing: error))])
            throw AppleToolsError.processSpawnFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        logger.info("sourcekit-lsp started (pid: \(process.processIdentifier))")
        TraceLog.exit([("pid", Int(process.processIdentifier))])

        return (stdinPipe.fileHandleForWriting, stdoutPipe.fileHandleForReading)
    }

    /// Terminates the sourcekit-lsp process.
    func stop() {
        TraceLog.enter()
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let process = process, process.isRunning {
            TraceLog.point("terminating", [("pid", Int(process.processIdentifier))])
            process.terminate()
            logger.info("sourcekit-lsp terminated")
        } else {
            TraceLog.point("not-running")
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        TraceLog.exit()
    }

    /// Locates the sourcekit-lsp executable using xcrun.
    private func findSourceKitLSP() async throws -> String {
        TraceLog.enter()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "sourcekit-lsp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            TraceLog.point("xcrun-run-succeeded")
        } catch {
            TraceLog.point("xcrun-run-failed", [("error", String(describing: error))])
            throw AppleToolsError.sourceKitLSPNotFound
        }

        process.waitUntilExit()
        TraceLog.point("xcrun-exited", [("status", Int(process.terminationStatus))])

        guard process.terminationStatus == 0 else {
            TraceLog.point("nonzero-status", [("status", Int(process.terminationStatus))])
            throw AppleToolsError.sourceKitLSPNotFound
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            TraceLog.point("empty-path")
            throw AppleToolsError.sourceKitLSPNotFound
        }

        TraceLog.exit([("path", path)])
        return path
    }
}
