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
        TraceLog.point("init")
    }

    // MARK: - Lifecycle

    /// Starts the background message reader loop.
    func startReading() {
        TraceLog.enter()
        let reader = MessageFrameReader(fileHandle: outputHandle)
        readTask = Task { [weak self] in
            TraceLog.point("reader-loop-start")
            do {
                for try await messageData in await reader.messages() {
                    let byteCount = messageData.count
                    TraceLog.point("message-received", [("bytes", byteCount)])
                    guard let self = self else {
                        TraceLog.point("self-deallocated-in-loop")
                        return
                    }
                    await self.handleIncomingMessage(messageData)
                }
                TraceLog.point("reader-loop-ended")
            } catch {
                TraceLog.point("reader-loop-catch", [("error", String(describing: error))])
                guard let self = self else {
                    TraceLog.point("self-deallocated-in-catch")
                    return
                }
                await self.handleReadError(error)
            }
        }
        TraceLog.exit()
    }

    /// Stops the background reader and cancels all pending requests.
    func stop() {
        TraceLog.enter([("pendingCount", pendingRequests.count)])
        readTask?.cancel()
        readTask = nil

        // Fail all pending requests
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (id, continuation) in pending {
            TraceLog.point("failing-pending", [("id", id)])
            continuation.resume(throwing: AppleToolsError.lspNotInitialized)
        }
        TraceLog.exit()
    }

    // MARK: - Send Request

    /// Sends a JSON-RPC request and awaits the response.
    /// The response's `result` field is decoded as type `R`.
    /// Returns `nil` if the result is JSON `null`.
    func sendRequest<P: Encodable, R: Decodable>(
        method: String,
        params: P
    ) async throws -> R {
        TraceLog.enter([("method", method), ("paramsType", String(describing: P.self)), ("resultType", String(describing: R.self))])
        let id = nextRequestId
        nextRequestId += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)
        let framed = JSONRPCFraming.encode(body)

        logger.debug("-> \(method) (id: \(id))")
        TraceLog.point("framed", [("id", id), ("bodyCount", body.count)])

        // Register continuation before writing to avoid race conditions
        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            TraceLog.point("register-continuation", [("id", id)])
            pendingRequests[id] = continuation

            // Write the framed message to the LSP process stdin
            do {
                try writeData(framed)
                TraceLog.point("write-succeeded", [("id", id)])
            } catch {
                TraceLog.point("write-error", [("id", id), ("error", String(describing: error))])
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
        TraceLog.point("continuation-resumed", [("id", id), ("bytes", responseData.count)])

        // Decode the result from the raw response
        let result: R = try decodeResult(from: responseData, method: method)
        TraceLog.exit([("id", id)])
        return result
    }

    /// Sends a JSON-RPC request and awaits an optional response.
    /// Returns `nil` if the result is JSON `null`.
    func sendRequestOptional<P: Encodable, R: Decodable>(
        method: String,
        params: P
    ) async throws -> R? {
        TraceLog.enter([("method", method), ("paramsType", String(describing: P.self)), ("resultType", String(describing: R.self))])
        let id = nextRequestId
        nextRequestId += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()
        let body = try encoder.encode(request)
        let framed = JSONRPCFraming.encode(body)

        logger.debug("-> \(method) (id: \(id))")
        TraceLog.point("framed", [("id", id), ("bodyCount", body.count)])

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            TraceLog.point("register-continuation", [("id", id)])
            pendingRequests[id] = continuation

            do {
                try writeData(framed)
                TraceLog.point("write-succeeded", [("id", id)])
            } catch {
                TraceLog.point("write-error", [("id", id), ("error", String(describing: error))])
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
        TraceLog.point("continuation-resumed", [("id", id), ("bytes", responseData.count)])

        // Check if result is null
        if isNullResult(responseData) {
            TraceLog.exit([("id", id), ("null", true)])
            return nil
        }

        let result: R = try decodeResult(from: responseData, method: method)
        TraceLog.exit([("id", id), ("null", false)])
        return result
    }

    // MARK: - Send Notification

    /// Sends a JSON-RPC notification (no response expected).
    func sendNotification<P: Encodable>(method: String, params: P) throws {
        TraceLog.enter([("method", method), ("paramsType", String(describing: P.self))])
        let notification = JSONRPCNotification(method: method, params: params)
        let encoder = JSONEncoder()
        let body = try encoder.encode(notification)
        let framed = JSONRPCFraming.encode(body)

        logger.debug("-> notification: \(method)")
        try writeData(framed)
        TraceLog.exit([("method", method), ("bodyCount", body.count)])
    }

    // MARK: - Notification Handlers

    /// Registers a handler for server-initiated notifications.
    func onNotification(_ method: String, handler: @escaping @Sendable (Data) async -> Void) {
        TraceLog.enter([("method", method)])
        notificationHandlers[method] = handler
        TraceLog.exit([("method", method)])
    }

    // MARK: - Internal Message Handling

    private func handleIncomingMessage(_ data: Data) {
        TraceLog.enter([("bytes", data.count)])
        // Try to decode minimally to determine message type
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            TraceLog.point("parse-failed")
            logger.warning("Failed to parse incoming JSON-RPC message")
            return
        }

        if let id = json["id"] as? Int {
            // This is a response to one of our requests
            TraceLog.point("is-response", [("id", id)])
            handleResponse(id: id, json: json, rawData: data)
        } else if let method = json["method"] as? String {
            // This is a server-initiated notification
            TraceLog.point("is-notification", [("method", method)])
            handleServerNotification(method: method, data: data, json: json)
        } else {
            TraceLog.point("unrecognized")
            logger.debug("Received unrecognized JSON-RPC message")
        }
        TraceLog.exit()
    }

    private func handleResponse(id: Int, json: [String: Any], rawData: Data) {
        TraceLog.enter([("id", id), ("bytes", rawData.count)])
        guard let continuation = pendingRequests.removeValue(forKey: id) else {
            TraceLog.point("unknown-id", [("id", id)])
            logger.warning("Received response for unknown request id: \(id)")
            return
        }

        // Check for JSON-RPC error
        if let errorObj = json["error"] as? [String: Any] {
            let code = errorObj["code"] as? Int ?? -1
            let message = errorObj["message"] as? String ?? "Unknown error"
            TraceLog.point("error-object", [("id", id), ("code", code), ("message", message)])
            logger.debug("<- error (id: \(id)): \(message)")
            continuation.resume(throwing: AppleToolsError.jsonRPCError(code: code, message: message))
            return
        }

        TraceLog.point("success", [("id", id)])
        logger.debug("<- response (id: \(id))")
        // Resume with the raw response data -- the caller will decode the result
        continuation.resume(returning: rawData)
        TraceLog.exit([("id", id)])
    }

    private func handleServerNotification(method: String, data: Data, json: [String: Any]) {
        TraceLog.enter([("method", method)])
        logger.debug("<- notification: \(method)")

        guard let handler = notificationHandlers[method] else {
            TraceLog.point("handler-missing", [("method", method)])
            return
        }

        // Extract the params portion and re-encode it for the handler
        if let params = json["params"] {
            TraceLog.point("params-present", [("method", method)])
            if let paramsData = try? JSONSerialization.data(withJSONObject: params) {
                let paramsCount = paramsData.count
                TraceLog.point("dispatch-handler", [("method", method), ("bytes", paramsCount)])
                Task {
                    TraceLog.point("handler-task-start", [("method", method)])
                    await handler(paramsData)
                    TraceLog.point("handler-task-end", [("method", method)])
                }
            }
        } else {
            TraceLog.point("params-absent", [("method", method)])
            Task {
                TraceLog.point("handler-task-start", [("method", method)])
                await handler(Data())
                TraceLog.point("handler-task-end", [("method", method)])
            }
        }
        TraceLog.exit([("method", method)])
    }

    private func handleReadError(_ error: Error) {
        TraceLog.enter([("error", String(describing: error)), ("pendingCount", pendingRequests.count)])
        if !Task.isCancelled {
            TraceLog.point("not-cancelled")
            logger.error("LSP message reader error: \(error.localizedDescription)")
        }

        // Fail all pending requests
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (id, continuation) in pending {
            TraceLog.point("failing-pending", [("id", id)])
            continuation.resume(throwing: error)
        }
        TraceLog.exit()
    }

    // MARK: - Helpers

    private func writeData(_ data: Data) throws {
        TraceLog.enter([("bytes", data.count)])
        inputHandle.write(data)
        TraceLog.exit()
    }

    /// Decodes the `result` field from a raw JSON-RPC response.
    private func decodeResult<R: Decodable>(from responseData: Data, method: String) throws -> R {
        TraceLog.enter([("method", method), ("resultType", String(describing: R.self)), ("bytes", responseData.count)])
        let decoder = JSONDecoder()
        do {
            let wrapper = try decoder.decode(ResponseWrapper<R>.self, from: responseData)
            TraceLog.exit([("method", method), ("decoded", true)])
            return wrapper.result
        } catch {
            TraceLog.point("decode-failed", [("method", method), ("error", String(describing: error))])
            let preview = String(data: responseData.prefix(500), encoding: .utf8) ?? "<binary>"
            throw AppleToolsError.lspRequestFailed(
                method: method,
                message: "Failed to decode response as \(R.self): \(error)\nRaw: \(preview)"
            )
        }
    }

    /// Checks if the `result` field in the response is JSON null.
    private func isNullResult(_ responseData: Data) -> Bool {
        TraceLog.enter([("bytes", responseData.count)])
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            TraceLog.point("parse-failed")
            return false
        }
        // Check if result key exists and is NSNull
        if let result = json["result"] {
            let isNull = result is NSNull
            TraceLog.exit([("hasResultKey", true), ("isNull", isNull)])
            return isNull
        }
        // No result key at all -- treat as null
        TraceLog.exit([("hasResultKey", false), ("isNull", true)])
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
