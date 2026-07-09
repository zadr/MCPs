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
        self.inputFD = input
        self.outputFD = output
        self.logger = logger ?? Logger(label: "apple-tools-mcp.stdio-transport")

        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    public func connect() async throws {
        guard !connected else { return }

        // Non-blocking stdin so a single read can't block when the kernel
        // says ready but no data is actually available.
        let flags = fcntl(inputFD, F_GETFL)
        if flags >= 0 {
            _ = fcntl(inputFD, F_SETFL, flags | O_NONBLOCK)
        }

        connected = true

        let source = DispatchSource.makeReadSource(fileDescriptor: inputFD, queue: .global())
        let inputFD = self.inputFD
        let cont = self.messageContinuation!
        let logger = self.logger
        let actor = self

        source.setEventHandler { [weak source] in
            guard let source else { return }
            let avail = Int(source.data)
            if avail <= 0 {
                // Probe for EOF.
                var probe: UInt8 = 0
                let n = withUnsafeMutablePointer(to: &probe) { ptr in
                    Darwin.read(inputFD, ptr, 0)
                }
                if n == 0 {
                    logger.notice("stdio transport: EOF")
                    cont.finish()
                    source.cancel()
                }
                return
            }
            var buffer = [UInt8](repeating: 0, count: avail)
            let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> ssize_t in
                guard let base = ptr.baseAddress else { return 0 }
                return Darwin.read(inputFD, base, avail)
            }
            if bytesRead <= 0 {
                if bytesRead == 0 {
                    logger.notice("stdio transport: EOF on read")
                    cont.finish()
                    source.cancel()
                }
                return
            }
            let chunk = Data(buffer.prefix(bytesRead))
            Task { await actor.feed(chunk) }
        }
        source.setCancelHandler {
            cont.finish()
        }
        source.resume()
        self.readSource = source

        logger.debug("DispatchStdioTransport connected")
    }

    /// Buffer bytes and yield any complete newline-delimited messages.
    fileprivate func feed(_ chunk: Data) {
        pendingData.append(chunk)
        while let newlineIdx = pendingData.firstIndex(of: 0x0a) {
            let messageData = pendingData[..<newlineIdx]
            pendingData = pendingData[(newlineIdx + 1)...]
            if !messageData.isEmpty {
                messageContinuation.yield(Data(messageData))
            }
        }
    }

    public func disconnect() async {
        guard connected else { return }
        connected = false
        readSource?.cancel()
        readSource = nil
        messageContinuation.finish()
        logger.debug("DispatchStdioTransport disconnected")
    }

    public func send(_ data: Data) async throws {
        guard connected else {
            throw MCPError.transportError(POSIXError(.ENOTCONN))
        }
        var messageWithNewline = data
        messageWithNewline.append(0x0a)

        var written = 0
        let total = messageWithNewline.count
        while written < total {
            let n = messageWithNewline.withUnsafeBytes { rawBuf -> ssize_t in
                guard let base = rawBuf.baseAddress else { return -1 }
                return Darwin.write(outputFD, base.advanced(by: written), total - written)
            }
            if n > 0 {
                written += n
            } else if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    continue
                }
                throw MCPError.transportError(POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO))
            } else {
                throw MCPError.transportError(POSIXError(.EIO))
            }
        }
    }

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }
}
