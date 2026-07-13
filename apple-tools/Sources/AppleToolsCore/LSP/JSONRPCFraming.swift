import Foundation

// MARK: - JSON-RPC Framing (Content-Length Protocol)

enum JSONRPCFraming {
    /// Encodes a JSON body with Content-Length header for LSP transport.
    static func encode(_ body: Data) -> Data {
        TraceLog.enter([("bodyCount", body.count)])
        let header = "Content-Length: \(body.count)\r\n\r\n"
        var framed = Data(header.utf8)
        framed.append(body)
        TraceLog.exit([("framedCount", framed.count)])
        return framed
    }
}

// MARK: - Message Frame Reader

/// Reads LSP JSON-RPC messages from a FileHandle, parsing Content-Length framing.
/// Messages arrive as: `Content-Length: N\r\n\r\n<N bytes of JSON body>`
actor MessageFrameReader {
    private let fileDescriptor: Int32
    private var buffer = Data()
    private let headerSeparator = Data("\r\n\r\n".utf8)
    private let contentLengthPrefix = "Content-Length: "

    init(fileHandle: FileHandle) {
        self.fileDescriptor = fileHandle.fileDescriptor
        TraceLog.point("init", [("fd", Int(fileHandle.fileDescriptor))])
    }

    /// Returns an async stream of complete JSON-RPC message bodies.
    func messages() -> AsyncThrowingStream<Data, Error> {
        TraceLog.enter([("fd", Int(fileDescriptor))])
        let fd = self.fileDescriptor

        return AsyncThrowingStream { continuation in
            // Read from the file descriptor on a detached task to avoid blocking
            // the cooperative thread pool. We use POSIX read() instead of
            // FileHandle.availableData because the latter can trigger an
            // Objective-C exception (SIGTRAP) if the file handle is closed
            // concurrently, whereas POSIX read() safely returns -1 / EBADF.
            let task = Task.detached { [weak self] in
                TraceLog.point("read-task-start", [("fd", Int(fd))])
                let bufferSize = 4096
                let rawBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { rawBuffer.deallocate() }

                while !Task.isCancelled {
                    let bytesRead = Darwin.read(fd, rawBuffer, bufferSize)
                    TraceLog.point("read-returned", [("bytesRead", bytesRead)])

                    if bytesRead <= 0 {
                        // 0 means EOF (pipe closed), negative means error
                        TraceLog.point("read-eof-or-error", [("bytesRead", bytesRead)])
                        continuation.finish()
                        return
                    }

                    let chunk = Data(bytes: rawBuffer, count: bytesRead)

                    guard let reader = self else {
                        TraceLog.point("reader-deallocated")
                        continuation.finish()
                        return
                    }

                    do {
                        let extracted = try await reader.appendAndExtract(chunk)
                        TraceLog.point("extracted-messages", [("count", extracted.count)])
                        for message in extracted {
                            continuation.yield(message)
                        }
                    } catch {
                        TraceLog.point("extract-error", [("error", String(describing: error))])
                        continuation.finish(throwing: error)
                        return
                    }
                }
                TraceLog.point("read-task-cancelled")
                continuation.finish()
            }

            continuation.onTermination = { _ in
                TraceLog.point("stream-terminated")
                task.cancel()
            }
        }
    }

    /// Appends a data chunk to the internal buffer and extracts any complete messages.
    private func appendAndExtract(_ chunk: Data) throws -> [Data] {
        TraceLog.enter([("chunkCount", chunk.count), ("bufferCount", buffer.count)])
        buffer.append(chunk)
        var messages: [Data] = []

        while let message = try extractOneMessage() {
            messages.append(message)
            TraceLog.point("extracted-one", [("index", messages.count)])
        }

        TraceLog.exit([("count", messages.count), ("bufferRemaining", buffer.count)])
        return messages
    }

    /// Attempts to extract a single complete message from the buffer.
    /// Returns nil if the buffer doesn't contain a complete message yet.
    private func extractOneMessage() throws -> Data? {
        TraceLog.enter([("bufferCount", buffer.count)])
        // Look for the header/body separator: \r\n\r\n
        guard let separatorRange = buffer.range(of: headerSeparator) else {
            TraceLog.point("no-separator")
            return nil
        }

        // Parse the headers (everything before the separator)
        let headerData = buffer[buffer.startIndex..<separatorRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            TraceLog.point("invalid-header")
            throw MessageFrameError.invalidHeader
        }

        // Extract Content-Length from headers
        guard let contentLength = parseContentLength(from: headerString) else {
            TraceLog.point("missing-content-length")
            throw MessageFrameError.missingContentLength(headerString)
        }
        TraceLog.point("content-length", [("contentLength", contentLength)])

        // Check if we have the full body
        let bodyStart = separatorRange.upperBound
        let availableBodyBytes = buffer.distance(from: bodyStart, to: buffer.endIndex)

        guard availableBodyBytes >= contentLength else {
            // Not enough data yet -- wait for more
            TraceLog.point("incomplete-body", [("available", availableBodyBytes), ("needed", contentLength)])
            return nil
        }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)

        // Extract the body
        let body = Data(buffer[bodyStart..<bodyEnd])

        // Remove the consumed message from the buffer
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)

        TraceLog.exit([("bodyCount", body.count)])
        return body
    }

    /// Parses the Content-Length value from the header block.
    private func parseContentLength(from headers: String) -> Int? {
        TraceLog.enter()
        for line in headers.split(separator: "\r\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(contentLengthPrefix) {
                let valueStr = trimmed.dropFirst(contentLengthPrefix.count)
                let parsed = Int(valueStr)
                TraceLog.exit([("parsed", parsed)])
                return parsed
            }
        }
        TraceLog.point("no-content-length-line")
        return nil
    }
}

// MARK: - Errors

enum MessageFrameError: Error, Sendable {
    case invalidHeader
    case missingContentLength(String)
}
