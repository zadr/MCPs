import Foundation

// MARK: - JSON-RPC Framing (Content-Length Protocol)

enum JSONRPCFraming {
    /// Encodes a JSON body with Content-Length header for LSP transport.
    static func encode(_ body: Data) -> Data {
        let header = "Content-Length: \(body.count)\r\n\r\n"
        var framed = Data(header.utf8)
        framed.append(body)
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
    }

    /// Returns an async stream of complete JSON-RPC message bodies.
    func messages() -> AsyncThrowingStream<Data, Error> {
        let fd = self.fileDescriptor

        return AsyncThrowingStream { continuation in
            // Read from the file descriptor on a detached task to avoid blocking
            // the cooperative thread pool. We use POSIX read() instead of
            // FileHandle.availableData because the latter can trigger an
            // Objective-C exception (SIGTRAP) if the file handle is closed
            // concurrently, whereas POSIX read() safely returns -1 / EBADF.
            let task = Task.detached { [weak self] in
                let bufferSize = 4096
                let rawBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { rawBuffer.deallocate() }

                while !Task.isCancelled {
                    let bytesRead = Darwin.read(fd, rawBuffer, bufferSize)

                    if bytesRead <= 0 {
                        // 0 means EOF (pipe closed), negative means error
                        continuation.finish()
                        return
                    }

                    let chunk = Data(bytes: rawBuffer, count: bytesRead)

                    guard let reader = self else {
                        continuation.finish()
                        return
                    }

                    do {
                        let extracted = try await reader.appendAndExtract(chunk)
                        for message in extracted {
                            continuation.yield(message)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Appends a data chunk to the internal buffer and extracts any complete messages.
    private func appendAndExtract(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var messages: [Data] = []

        while let message = try extractOneMessage() {
            messages.append(message)
        }

        return messages
    }

    /// Attempts to extract a single complete message from the buffer.
    /// Returns nil if the buffer doesn't contain a complete message yet.
    private func extractOneMessage() throws -> Data? {
        // Look for the header/body separator: \r\n\r\n
        guard let separatorRange = buffer.range(of: headerSeparator) else {
            return nil
        }

        // Parse the headers (everything before the separator)
        let headerData = buffer[buffer.startIndex..<separatorRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw MessageFrameError.invalidHeader
        }

        // Extract Content-Length from headers
        guard let contentLength = parseContentLength(from: headerString) else {
            throw MessageFrameError.missingContentLength(headerString)
        }

        // Check if we have the full body
        let bodyStart = separatorRange.upperBound
        let availableBodyBytes = buffer.distance(from: bodyStart, to: buffer.endIndex)

        guard availableBodyBytes >= contentLength else {
            // Not enough data yet -- wait for more
            return nil
        }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)

        // Extract the body
        let body = Data(buffer[bodyStart..<bodyEnd])

        // Remove the consumed message from the buffer
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)

        return body
    }

    /// Parses the Content-Length value from the header block.
    private func parseContentLength(from headers: String) -> Int? {
        for line in headers.split(separator: "\r\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(contentLengthPrefix) {
                let valueStr = trimmed.dropFirst(contentLengthPrefix.count)
                return Int(valueStr)
            }
        }
        return nil
    }
}

// MARK: - Errors

enum MessageFrameError: Error, Sendable {
    case invalidHeader
    case missingContentLength(String)
}
