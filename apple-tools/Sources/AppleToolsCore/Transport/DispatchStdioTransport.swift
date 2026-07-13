import Foundation
import Darwin
import Logging
import MCP

/// Stdio `Transport` driven by a kqueue read source rather than a polling
/// loop. The SDK's bundled `StdioTransport` retries `read(EAGAIN)` with
/// `Task.sleep(10ms)`, which saturates the cooperative pool and starves
/// every other Task in the process — including our timeout continuations.
public actor DispatchStdioTransport: Transport {
    public let logger: Logger

    private let inputFD: Int32
    private let outputFD: Int32

    private var connected = false
    private var readSource: DispatchSourceRead?
    private var pendingData = Data()

    private var messageStream: AsyncThrowingStream<Data, Swift.Error>!
    private var messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!

    public init(
        input: Int32 = STDIN_FILENO,
        output: Int32 = STDOUT_FILENO,
        logger: Logger? = nil
    ) {
        TraceLog.enter([("input", Int(input)), ("output", Int(output))])
        self.inputFD = input
        self.outputFD = output
        self.logger = logger ?? Logger(label: "apple-tools-mcp.stdio-transport")

        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
        TraceLog.exit()
    }

    public func connect() async throws {
        TraceLog.enter([("connected", connected)])
        guard !connected else {
            TraceLog.point("already-connected")
            TraceLog.exit()
            return
        }

        // Non-blocking stdin so a single read can't block when the kernel
        // says ready but no data is actually available.
        let flags = fcntl(inputFD, F_GETFL)
        if flags >= 0 {
            TraceLog.point("fcntl-set-nonblock", [("flags", Int(flags))])
            _ = fcntl(inputFD, F_SETFL, flags | O_NONBLOCK)
        } else {
            TraceLog.point("fcntl-getfl-failed", [("flags", Int(flags))])
        }

        connected = true

        let source = DispatchSource.makeReadSource(fileDescriptor: inputFD, queue: .global())
        let inputFD = self.inputFD
        let cont = self.messageContinuation!
        let logger = self.logger
        let actor = self

        source.setEventHandler { [weak source] in
            TraceLog.point("eventHandler-fire")
            guard let source else {
                TraceLog.point("eventHandler-source-nil")
                return
            }
            let avail = Int(source.data)
            if avail <= 0 {
                TraceLog.point("avail<=0", [("avail", avail)])
                // Probe for EOF.
                var probe: UInt8 = 0
                let n = withUnsafeMutablePointer(to: &probe) { ptr in
                    Darwin.read(inputFD, ptr, 0)
                }
                if n == 0 {
                    TraceLog.point("eof-probe-zero", [("n", n)])
                    logger.notice("stdio transport: EOF")
                    cont.finish()
                    source.cancel()
                } else {
                    TraceLog.point("eof-probe-nonzero", [("n", n)])
                }
                return
            }
            var buffer = [UInt8](repeating: 0, count: avail)
            let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> ssize_t in
                guard let base = ptr.baseAddress else { return 0 }
                return Darwin.read(inputFD, base, avail)
            }
            if bytesRead <= 0 {
                TraceLog.point("bytesRead<=0", [("bytesRead", bytesRead)])
                if bytesRead == 0 {
                    TraceLog.point("eof-on-read", [("bytesRead", bytesRead)])
                    logger.notice("stdio transport: EOF on read")
                    cont.finish()
                    source.cancel()
                }
                return
            }
            TraceLog.point("read-chunk", [("bytesRead", bytesRead)])
            let chunk = Data(buffer.prefix(bytesRead))
            Task {
                TraceLog.point("feed-task", [("bytes", bytesRead)])
                await actor.feed(chunk)
            }
        }
        source.setCancelHandler {
            TraceLog.point("cancelHandler-fire")
            cont.finish()
        }
        source.resume()
        self.readSource = source

        logger.debug("DispatchStdioTransport connected")
        TraceLog.exit()
    }

    /// Buffer bytes and yield any complete newline-delimited messages.
    fileprivate func feed(_ chunk: Data) {
        TraceLog.enter([("chunkBytes", chunk.count), ("pendingBefore", pendingData.count)])
        pendingData.append(chunk)
        while let newlineIdx = pendingData.firstIndex(of: 0x0a) {
            TraceLog.point("newline-found", [("newlineIdx", newlineIdx), ("pending", pendingData.count)])
            let messageData = pendingData[..<newlineIdx]
            pendingData = pendingData[(newlineIdx + 1)...]
            if !messageData.isEmpty {
                TraceLog.point("yield-message", [("bytes", messageData.count)])
                messageContinuation.yield(Data(messageData))
            } else {
                TraceLog.point("empty-message")
            }
        }
        TraceLog.exit([("pendingAfter", pendingData.count)])
    }

    public func disconnect() async {
        TraceLog.enter([("connected", connected)])
        guard connected else {
            TraceLog.point("already-disconnected")
            TraceLog.exit()
            return
        }
        connected = false
        readSource?.cancel()
        readSource = nil
        messageContinuation.finish()
        logger.debug("DispatchStdioTransport disconnected")
        TraceLog.exit()
    }

    public func send(_ data: Data) async throws {
        TraceLog.enter([("bytes", data.count), ("connected", connected)])
        guard connected else {
            TraceLog.point("not-connected-throw")
            throw MCPError.transportError(POSIXError(.ENOTCONN))
        }
        var messageWithNewline = data
        messageWithNewline.append(0x0a)

        var written = 0
        let total = messageWithNewline.count
        while written < total {
            TraceLog.point("write-loop", [("written", written), ("total", total)])
            let n = messageWithNewline.withUnsafeBytes { rawBuf -> ssize_t in
                guard let base = rawBuf.baseAddress else { return -1 }
                return Darwin.write(outputFD, base.advanced(by: written), total - written)
            }
            if n > 0 {
                TraceLog.point("wrote", [("n", n)])
                written += n
            } else if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    TraceLog.point("eagain", [("errno", Int(errno))])
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    continue
                }
                TraceLog.point("write-error-throw", [("errno", Int(errno))])
                throw MCPError.transportError(POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO))
            } else {
                TraceLog.point("wrote-zero-throw", [("n", n)])
                throw MCPError.transportError(POSIXError(.EIO))
            }
        }
        TraceLog.exit([("written", written)])
    }

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        TraceLog.enter()
        TraceLog.exit()
        return messageStream
    }
}
