@preconcurrency import Foundation
import Logging

/// High-level service wrapping LSPClient with typed LSP method calls.
/// Handles lazy initialization, document tracking, and diagnostics caching.
public actor SourceKitLSPService {
    private let logger: Logger
    private var lspProcess: LSPProcess?
    private var lspClient: LSPClient?
    private var initialized = false
    private var openDocuments: Set<String> = []
    private var diagnosticsCache: [String: [Diagnostic]] = [:]
    private var knownWorkspaceRoots: Set<String> = []

    public init(logger: Logger) {
        self.logger = logger
        TraceLog.point("init")
    }

    // MARK: - Initialization

    /// Ensures the LSP server is started and initialized. Called lazily on first use.
    private func ensureInitialized() async throws {
        TraceLog.enter([("initialized", initialized)])
        guard !initialized else {
            TraceLog.point("already-initialized")
            return
        }

        let process = LSPProcess(logger: logger)
        let handles = try await process.start()
        TraceLog.point("process-started")

        let client = LSPClient(
            input: handles.input,
            output: handles.output,
            logger: logger
        )
        await client.startReading()
        TraceLog.point("reading-started")

        // Register diagnostics notification handler
        await client.onNotification("textDocument/publishDiagnostics") {
            [weak self] data in
            TraceLog.point("diagnostics-notification-closure", [("bytes", data.count)])
            guard let self = self else {
                TraceLog.point("self-deallocated-in-diag-closure")
                return
            }
            await self.handleDiagnosticsNotification(data)
        }
        TraceLog.point("handler-registered")

        // Send initialize request
        let initParams = InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            rootUri: nil,
            capabilities: ClientCapabilities(
                workspace: WorkspaceClientCapabilities(workspaceFolders: true)
            )
        )

        let _: InitializeResult = try await client.sendRequest(
            method: "initialize",
            params: initParams
        )
        TraceLog.point("initialize-response-received")

        // Send initialized notification
        try await client.sendNotification(
            method: "initialized",
            params: EmptyParams()
        )
        TraceLog.point("initialized-notification-sent")

        self.lspProcess = process
        self.lspClient = client
        self.initialized = true

        logger.info("SourceKit-LSP initialized successfully")
        TraceLog.exit()
    }

    /// Ensures a document is open in the LSP server.
    /// Reads the file content and sends textDocument/didOpen if not already open.
    private func ensureDocumentOpen(uri: String) async throws {
        TraceLog.enter([("uri", uri)])
        try await ensureInitialized()

        guard !openDocuments.contains(uri) else {
            TraceLog.point("already-open", [("uri", uri)])
            return
        }

        let path = FileURI.toPath(uri)

        guard FileManager.default.fileExists(atPath: path) else {
            TraceLog.point("file-not-found", [("path", path)])
            throw AppleToolsError.invalidFilePath(path)
        }

        // Ensure the workspace root for this file is registered with the server
        try await ensureWorkspaceRoot(forFileAt: path)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let languageId = Self.languageId(forPath: path)

        let params = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(
                uri: uri,
                languageId: languageId,
                version: 1,
                text: content
            )
        )

        try await requireClient().sendNotification(
            method: "textDocument/didOpen",
            params: params
        )

        openDocuments.insert(uri)
        logger.debug("Opened document: \(uri)")
        TraceLog.exit([("uri", uri), ("contentLength", content.count)])
    }

    // MARK: - LSP Methods

    /// Returns hover information for the given position in a document.
    func hover(uri: String, line: Int, character: Int) async throws -> HoverResult? {
        TraceLog.enter([("uri", uri), ("line", line), ("character", character)])
        try await ensureDocumentOpen(uri: uri)

        let params = TextDocumentPositionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )

        let result: HoverResult? = try await requireClient().sendRequestOptional(
            method: "textDocument/hover",
            params: params
        )
        TraceLog.exit([("hasResult", result != nil)])
        return result
    }

    /// Returns the definition location(s) for the symbol at the given position.
    func definition(uri: String, line: Int, character: Int) async throws -> [LSPLocation] {
        TraceLog.enter([("uri", uri), ("line", line), ("character", character)])
        try await ensureDocumentOpen(uri: uri)

        let params = TextDocumentPositionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )

        let client = try requireClient()

        // SourceKit-LSP can return a single Location, an array of Locations,
        // or an array of LocationLinks. Try array first, then single.
        do {
            let locations: [LSPLocation] = try await client.sendRequest(
                method: "textDocument/definition",
                params: params
            )
            TraceLog.exit([("branch", "array"), ("count", locations.count)])
            return locations
        } catch {
            TraceLog.point("array-decode-failed", [("error", String(describing: error))])
            // Try decoding as a single location
            do {
                let location: LSPLocation = try await client.sendRequest(
                    method: "textDocument/definition",
                    params: params
                )
                TraceLog.exit([("branch", "single"), ("count", 1)])
                return [location]
            } catch {
                // Result might be null/empty
                TraceLog.point("single-decode-failed", [("error", String(describing: error))])
                TraceLog.exit([("branch", "empty"), ("count", 0)])
                return []
            }
        }
    }

    /// Returns all references to the symbol at the given position.
    func references(
        uri: String,
        line: Int,
        character: Int,
        includeDeclaration: Bool = true
    ) async throws -> [LSPLocation] {
        TraceLog.enter([("uri", uri), ("line", line), ("character", character), ("includeDeclaration", includeDeclaration)])
        try await ensureDocumentOpen(uri: uri)

        let params = ReferenceParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character),
            context: ReferenceContext(includeDeclaration: includeDeclaration)
        )

        let result: [LSPLocation]? = try await requireClient().sendRequestOptional(
            method: "textDocument/references",
            params: params
        )
        TraceLog.point(result == nil ? "null-result" : "has-result", [("count", result?.count)])
        TraceLog.exit([("count", (result ?? []).count)])
        return result ?? []
    }

    /// Returns completions at the given position.
    func completion(uri: String, line: Int, character: Int) async throws -> CompletionList {
        TraceLog.enter([("uri", uri), ("line", line), ("character", character)])
        try await ensureDocumentOpen(uri: uri)

        let params = CompletionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )

        // Completion can return either CompletionList or [CompletionItem]
        do {
            let list: CompletionList = try await requireClient().sendRequest(
                method: "textDocument/completion",
                params: params
            )
            TraceLog.exit([("branch", "list"), ("count", list.items.count)])
            return list
        } catch {
            TraceLog.point("list-decode-failed", [("error", String(describing: error))])
            let items: [CompletionItem] = try await requireClient().sendRequest(
                method: "textDocument/completion",
                params: params
            )
            TraceLog.exit([("branch", "items"), ("count", items.count)])
            return CompletionList(isIncomplete: false, items: items)
        }
    }

    /// Returns cached diagnostics for the given URI.
    /// Diagnostics are delivered asynchronously via notifications.
    func diagnostics(uri: String) async throws -> [Diagnostic] {
        TraceLog.enter([("uri", uri)])
        try await ensureDocumentOpen(uri: uri)

        // Give the LSP server a moment to send diagnostics after opening
        // (diagnostics come as notifications, not request/response)
        TraceLog.point("before-sleep")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        TraceLog.point("after-sleep")

        let result = diagnosticsCache[uri] ?? []
        TraceLog.exit([("count", result.count)])
        return result
    }

    /// Returns document symbols (outline) for the given document.
    /// SourceKit-LSP can return either [DocumentSymbol] (hierarchical) or
    /// [SymbolInformation] (flat). This method tries hierarchical first, then
    /// falls back to flat and converts to DocumentSymbol for a uniform API.
    func documentSymbols(uri: String) async throws -> [DocumentSymbol] {
        TraceLog.enter([("uri", uri)])
        try await ensureDocumentOpen(uri: uri)

        let params = DocumentSymbolParams(
            textDocument: TextDocumentIdentifier(uri: uri)
        )

        let client = try requireClient()

        // Try hierarchical DocumentSymbol format first
        do {
            let symbols: [DocumentSymbol] = try await client.sendRequest(
                method: "textDocument/documentSymbol",
                params: params
            )
            TraceLog.exit([("branch", "hierarchical"), ("count", symbols.count)])
            return symbols
        } catch {
            TraceLog.point("hierarchical-decode-failed", [("error", String(describing: error))])
            // Fall back to flat SymbolInformation and convert
            do {
                let symbols: [SymbolInformation] = try await client.sendRequest(
                    method: "textDocument/documentSymbol",
                    params: params
                )
                TraceLog.exit([("branch", "flat"), ("count", symbols.count)])
                return symbols.map { sym in
                    DocumentSymbol(
                        name: sym.name,
                        kind: sym.kind,
                        range: sym.location.range,
                        selectionRange: sym.location.range,
                        children: nil
                    )
                }
            } catch {
                TraceLog.point("flat-decode-failed", [("error", String(describing: error))])
                TraceLog.exit([("branch", "empty"), ("count", 0)])
                return []
            }
        }
    }

    /// Searches for workspace symbols matching the given query.
    func workspaceSymbols(query: String) async throws -> [SymbolInformation] {
        TraceLog.enter([("query", query)])
        try await ensureInitialized()

        let params = WorkspaceSymbolParams(query: query)

        let result: [SymbolInformation]? = try await requireClient().sendRequestOptional(
            method: "workspace/symbol",
            params: params
        )
        TraceLog.point(result == nil ? "null-result" : "has-result", [("count", result?.count)])
        TraceLog.exit([("count", (result ?? []).count)])
        return result ?? []
    }

    /// Formats an entire document.
    func formatting(uri: String, tabSize: Int = 4, insertSpaces: Bool = true) async throws -> [TextEdit] {
        TraceLog.enter([("uri", uri), ("tabSize", tabSize), ("insertSpaces", insertSpaces)])
        try await ensureDocumentOpen(uri: uri)

        let params = DocumentFormattingParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            options: FormattingOptions(tabSize: tabSize, insertSpaces: insertSpaces)
        )

        let result: [TextEdit]? = try await requireClient().sendRequestOptional(
            method: "textDocument/formatting",
            params: params
        )
        TraceLog.point(result == nil ? "null-result" : "has-result", [("count", result?.count)])
        TraceLog.exit([("count", (result ?? []).count)])
        return result ?? []
    }

    /// Returns available code actions for the given range.
    func codeActions(
        uri: String,
        range: LSPRange,
        diagnostics: [Diagnostic] = []
    ) async throws -> [CodeAction] {
        TraceLog.enter([("uri", uri), ("diagnosticsCount", diagnostics.count)])
        try await ensureDocumentOpen(uri: uri)

        let params = CodeActionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            range: range,
            context: CodeActionContext(diagnostics: diagnostics)
        )

        let result: [CodeAction]? = try await requireClient().sendRequestOptional(
            method: "textDocument/codeAction",
            params: params
        )
        TraceLog.point(result == nil ? "null-result" : "has-result", [("count", result?.count)])
        TraceLog.exit([("count", (result ?? []).count)])
        return result ?? []
    }

    /// Renames the symbol at the given position.
    func rename(uri: String, line: Int, character: Int, newName: String) async throws -> WorkspaceEdit {
        TraceLog.enter([("uri", uri), ("line", line), ("character", character), ("newName", newName)])
        try await ensureDocumentOpen(uri: uri)

        let params = RenameParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character),
            newName: newName
        )

        let result: WorkspaceEdit? = try await requireClient().sendRequestOptional(
            method: "textDocument/rename",
            params: params
        )
        TraceLog.point(result == nil ? "null-result" : "has-result")
        TraceLog.exit([("hasResult", result != nil)])
        return result ?? WorkspaceEdit(changes: nil, documentChanges: nil)
    }

    // MARK: - Shutdown

    /// Gracefully shuts down the LSP server.
    func shutdown() async {
        TraceLog.enter([("initialized", initialized)])
        guard initialized, let client = lspClient else {
            TraceLog.point("not-initialized")
            return
        }

        do {
            // Send shutdown request
            let _: EmptyResult? = try await client.sendRequestOptional(
                method: "shutdown",
                params: EmptyParams()
            )
            TraceLog.point("shutdown-response-received")

            // Send exit notification
            try await client.sendNotification(method: "exit", params: EmptyParams())
            TraceLog.point("exit-notification-sent")
        } catch {
            TraceLog.point("shutdown-error", [("error", String(describing: error))])
            logger.warning("Error during LSP shutdown: \(error.localizedDescription)")
        }

        // Close all tracked documents and workspace roots
        openDocuments.removeAll()
        diagnosticsCache.removeAll()
        knownWorkspaceRoots.removeAll()

        // Stop the client and process
        await client.stop()
        if let process = lspProcess {
            await process.stop()
        }

        lspClient = nil
        lspProcess = nil
        initialized = false

        logger.info("SourceKit-LSP shut down")
        TraceLog.exit()
    }

    // MARK: - Workspace Root Discovery

    /// Walks up the directory tree from the given file path to find the nearest
    /// project root. A project root is a directory containing Package.swift,
    /// *.xcodeproj, *.xcworkspace, compile_commands.json, or .git.
    private func discoverProjectRoot(forFileAt path: String) -> String? {
        TraceLog.enter([("path", path)])
        let fileManager = FileManager.default
        var dir = (path as NSString).deletingLastPathComponent

        while dir != "/" && !dir.isEmpty {
            TraceLog.point("checking-dir", [("dir", dir)])
            // Check for well-known project root markers
            let markers = ["Package.swift", "compile_commands.json", ".git"]
            for marker in markers {
                let candidate = (dir as NSString).appendingPathComponent(marker)
                if fileManager.fileExists(atPath: candidate) {
                    TraceLog.exit([("root", dir), ("via", marker)])
                    return dir
                }
            }

            // Check for *.xcodeproj or *.xcworkspace directories
            if let contents = try? fileManager.contentsOfDirectory(atPath: dir) {
                for entry in contents {
                    if entry.hasSuffix(".xcodeproj") || entry.hasSuffix(".xcworkspace") {
                        TraceLog.exit([("root", dir), ("via", entry)])
                        return dir
                    }
                }
            }

            dir = (dir as NSString).deletingLastPathComponent
        }

        TraceLog.exit([("root", nil)])
        return nil
    }

    /// Discovers the project root for the given file and, if it is a new root,
    /// sends a workspace/didChangeWorkspaceFolders notification to the LSP server.
    private func ensureWorkspaceRoot(forFileAt path: String) async throws {
        TraceLog.enter([("path", path)])
        guard let root = discoverProjectRoot(forFileAt: path) else {
            TraceLog.point("no-root")
            return
        }

        let rootURI = FileURI.fromPath(root)

        guard !knownWorkspaceRoots.contains(rootURI) else {
            TraceLog.point("root-already-known", [("rootURI", rootURI)])
            return
        }

        knownWorkspaceRoots.insert(rootURI)

        let folderName = (root as NSString).lastPathComponent
        let params = DidChangeWorkspaceFoldersParams(
            event: WorkspaceFoldersChangeEvent(
                added: [WorkspaceFolder(uri: rootURI, name: folderName)],
                removed: []
            )
        )

        try await requireClient().sendNotification(
            method: "workspace/didChangeWorkspaceFolders",
            params: params
        )

        logger.info("Added workspace root: \(rootURI)")
        TraceLog.exit([("rootURI", rootURI)])
    }

    // MARK: - Helpers

    private func requireClient() throws -> LSPClient {
        TraceLog.enter()
        guard let client = lspClient else {
            TraceLog.point("client-missing")
            throw AppleToolsError.lspNotInitialized
        }
        TraceLog.exit()
        return client
    }

    private func handleDiagnosticsNotification(_ data: Data) {
        TraceLog.enter([("bytes", data.count)])
        do {
            let params = try JSONDecoder().decode(PublishDiagnosticsParams.self, from: data)
            diagnosticsCache[params.uri] = params.diagnostics
            logger.debug("Received \(params.diagnostics.count) diagnostics for \(params.uri)")
            TraceLog.exit([("uri", params.uri), ("count", params.diagnostics.count)])
        } catch {
            TraceLog.point("decode-failed", [("error", String(describing: error))])
            logger.warning("Failed to decode diagnostics notification: \(error.localizedDescription)")
        }
    }

    /// Determines the LSP language identifier from a file path.
    static func languageId(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        let id: String
        switch ext {
        case "swift": id = "swift"
        case "h": id = "objective-c"
        case "m": id = "objective-c"
        case "mm": id = "objective-cpp"
        case "c": id = "c"
        case "cc", "cpp", "cxx": id = "cpp"
        case "hpp", "hxx": id = "cpp"
        default: id = "swift"
        }
        TraceLog.point("resolved", [("ext", ext), ("id", id)])
        return id
    }
}

/// Empty result for requests like shutdown that return null/empty.
private struct EmptyResult: Codable, Sendable {}
