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
    }

    /// Starts the sourcekit-lsp process and returns the stdin/stdout file handles for communication.
    func start() async throws -> (input: FileHandle, output: FileHandle) {
        let path = try await findSourceKitLSP()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = []

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Forward stderr to logger on a background thread
        let log = self.logger
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                log.debug("sourcekit-lsp stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        do {
            try process.run()
        } catch {
            throw AppleToolsError.processSpawnFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        logger.info("sourcekit-lsp started (pid: \(process.processIdentifier))")

        return (stdinPipe.fileHandleForWriting, stdoutPipe.fileHandleForReading)
    }

    /// Terminates the sourcekit-lsp process.
    func stop() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let process = process, process.isRunning {
            process.terminate()
            logger.info("sourcekit-lsp terminated")
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    /// Locates the sourcekit-lsp executable using xcrun.
    private func findSourceKitLSP() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "sourcekit-lsp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw AppleToolsError.sourceKitLSPNotFound
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppleToolsError.sourceKitLSPNotFound
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw AppleToolsError.sourceKitLSPNotFound
        }

        return path
    }
}
