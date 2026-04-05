@preconcurrency import Foundation
import Logging

/// JSON-RPC 2.0 client for communicating with an LSP server over stdio.
actor LSPClient {
    private let inputHandle: FileHandle   // Write to LSP stdin
    private let outputHandle: FileHandle  // Read from LSP stdout
    private let logger: Logger

    private var nextRequestId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    private var notificationHandlers: [String: @Sendable (Data) async -> Void] = [:]
    private var readTask: Task<Void, Never>?

    init(input: FileHandle, output: FileHandle, logger: Logger) {
        self.inputHandle = input
        self.outputHandle = output
        self.logger = logger
    }

    // MARK: - Lifecycle

    /// Starts the background message reader loop.
    func startReading() {
        let reader = MessageFrameReader(fileHandle: outputHandle)
        readTask = Task { [weak self] in
            do {
                for try await messageData in await reader.messages() {
                    guard let self = self else { return }
                    await self.handleIncomingMessage(messageData)
                }
            } catch {
                guard let self = self else { return }
                await self.handleReadError(error)
            }
        }
    }

    /// Stops the background reader and cancels all pending requests.
    func stop() {
        readTask?.cancel()
        readTask = nil

        // Fail all pending requests
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: AppleToolsError.lspNotInitialized)
        }
    }

    // MARK: - Send Request

    /// Sends a JSON-RPC request and awaits the response.
    /// The response's `result` field is decoded as type `R`.
    /// Returns `nil` if the result is JSON `null`.
    func sendRequest<P: Encodable, R: Decodable>(
        method: String,
        params: P
    ) async throws -> R {
        let id = nextRequestId
        nextRequestId += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)
        let framed = JSONRPCFraming.encode(body)

        logger.debug("-> \(method) (id: \(id))")

        // Register continuation before writing to avoid race conditions
        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            // Write the framed message to the LSP process stdin
            do {
                try writeData(framed)
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }

        // Decode the result from the raw response
        return try decodeResult(from: responseData, method: method)
    }

    /// Sends a JSON-RPC request and awaits an optional response.
    /// Returns `nil` if the result is JSON `null`.
    func sendRequestOptional<P: Encodable, R: Decodable>(
        method: String,
        params: P
    ) async throws -> R? {
        let id = nextRequestId
        nextRequestId += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)
        let framed = JSONRPCFraming.encode(body)

        logger.debug("-> \(method) (id: \(id))")

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            do {
                try writeData(framed)
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }

        // Check if result is null
        if isNullResult(responseData) {
            return nil
        }

        return try decodeResult(from: responseData, method: method)
    }

    // MARK: - Send Notification

    /// Sends a JSON-RPC notification (no response expected).
    func sendNotification<P: Encodable>(method: String, params: P) throws {
        let notification = JSONRPCNotification(method: method, params: params)
        let encoder = JSONEncoder()
        let body = try encoder.encode(notification)
        let framed = JSONRPCFraming.encode(body)

        logger.debug("-> notification: \(method)")
        try writeData(framed)
    }

    // MARK: - Notification Handlers

    /// Registers a handler for server-initiated notifications.
    func onNotification(_ method: String, handler: @escaping @Sendable (Data) async -> Void) {
        notificationHandlers[method] = handler
    }

    // MARK: - Internal Message Handling

    private func handleIncomingMessage(_ data: Data) {
        // Try to decode minimally to determine message type
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("Failed to parse incoming JSON-RPC message")
            return
        }

        if let id = json["id"] as? Int {
            // This is a response to one of our requests
            handleResponse(id: id, json: json, rawData: data)
        } else if let method = json["method"] as? String {
            // This is a server-initiated notification
            handleServerNotification(method: method, data: data, json: json)
        } else {
            logger.debug("Received unrecognized JSON-RPC message")
        }
    }

    private func handleResponse(id: Int, json: [String: Any], rawData: Data) {
        guard let continuation = pendingRequests.removeValue(forKey: id) else {
            logger.warning("Received response for unknown request id: \(id)")
            return
        }

        // Check for JSON-RPC error
        if let errorObj = json["error"] as? [String: Any] {
            let code = errorObj["code"] as? Int ?? -1
            let message = errorObj["message"] as? String ?? "Unknown error"
            logger.debug("<- error (id: \(id)): \(message)")
            continuation.resume(throwing: AppleToolsError.jsonRPCError(code: code, message: message))
            return
        }

        logger.debug("<- response (id: \(id))")
        // Resume with the raw response data -- the caller will decode the result
        continuation.resume(returning: rawData)
    }

    private func handleServerNotification(method: String, data: Data, json: [String: Any]) {
        logger.debug("<- notification: \(method)")

        guard let handler = notificationHandlers[method] else {
            return
        }

        // Extract the params portion and re-encode it for the handler
        if let params = json["params"] {
            if let paramsData = try? JSONSerialization.data(withJSONObject: params) {
                Task {
                    await handler(paramsData)
                }
            }
        } else {
            Task {
                await handler(Data())
            }
        }
    }

    private func handleReadError(_ error: Error) {
        if !Task.isCancelled {
            logger.error("LSP message reader error: \(error.localizedDescription)")
        }

        // Fail all pending requests
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Helpers

    private func writeData(_ data: Data) throws {
        inputHandle.write(data)
    }

    /// Decodes the `result` field from a raw JSON-RPC response.
    private func decodeResult<R: Decodable>(from responseData: Data, method: String) throws -> R {
        let decoder = JSONDecoder()
        do {
            let wrapper = try decoder.decode(ResponseWrapper<R>.self, from: responseData)
            return wrapper.result
        } catch {
            let preview = String(data: responseData.prefix(500), encoding: .utf8) ?? "<binary>"
            throw AppleToolsError.lspRequestFailed(
                method: method,
                message: "Failed to decode response as \(R.self): \(error)\nRaw: \(preview)"
            )
        }
    }

    /// Checks if the `result` field in the response is JSON null.
    private func isNullResult(_ responseData: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return false
        }
        // Check if result key exists and is NSNull
        if let result = json["result"] {
            return result is NSNull
        }
        // No result key at all -- treat as null
        return true
    }
}

// MARK: - Internal JSON-RPC Types

private struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: Params
}

private struct JSONRPCNotification<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params
}

/// Used to decode the `result` field from a JSON-RPC response.
private struct ResponseWrapper<R: Decodable>: Decodable {
    let result: R
}
