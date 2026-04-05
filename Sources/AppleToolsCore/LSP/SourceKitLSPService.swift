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
    }

    // MARK: - Initialization

    /// Ensures the LSP server is started and initialized. Called lazily on first use.
    private func ensureInitialized() async throws {
        guard !initialized else { return }

        let process = LSPProcess(logger: logger)
        let handles = try await process.start()

        let client = LSPClient(
            input: handles.input,
            output: handles.output,
            logger: logger
        )
        await client.startReading()

        // Register diagnostics notification handler
        await client.onNotification("textDocument/publishDiagnostics") {
            [weak self] data in
            guard let self = self else { return }
            await self.handleDiagnosticsNotification(data)
        }

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

        // Send initialized notification
        try await client.sendNotification(
            method: "initialized",
            params: EmptyParams()
        )

        self.lspProcess = process
        self.lspClient = client
        self.initialized = true

        logger.info("SourceKit-LSP initialized successfully")
    }

    /// Ensures a document is open in the LSP server.
    /// Reads the file content and sends textDocument/didOpen if not already open.
    private func ensureDocumentOpen(uri: String) async throws {
        try await ensureInitialized()

        guard !openDocuments.contains(uri) else { return }

        let path = FileURI.toPath(uri)

        guard FileManager.default.fileExists(atPath: path) else {
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
    }

    // MARK: - LSP Methods

    /// Returns hover information for the given position in a document.
    func hover(uri: String, line: Int, character: Int) async throws -> HoverResult? {
        try await ensureDocumentOpen(uri: uri)

        let params = TextDocumentPositionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )

        return try await requireClient().sendRequestOptional(
            method: "textDocument/hover",
            params: params
        )
    }

    /// Returns the definition location(s) for the symbol at the given position.
    func definition(uri: String, line: Int, character: Int) async throws -> [LSPLocation] {
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
            return locations
        } catch {
            // Try decoding as a single location
            do {
                let location: LSPLocation = try await client.sendRequest(
                    method: "textDocument/definition",
                    params: params
                )
                return [location]
            } catch {
                // Result might be null/empty
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
        return result ?? []
    }

    /// Returns completions at the given position.
    func completion(uri: String, line: Int, character: Int) async throws -> CompletionList {
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
            return list
        } catch {
            let items: [CompletionItem] = try await requireClient().sendRequest(
                method: "textDocument/completion",
                params: params
            )
            return CompletionList(isIncomplete: false, items: items)
        }
    }

    /// Returns cached diagnostics for the given URI.
    /// Diagnostics are delivered asynchronously via notifications.
    func diagnostics(uri: String) async throws -> [Diagnostic] {
        try await ensureDocumentOpen(uri: uri)

        // Give the LSP server a moment to send diagnostics after opening
        // (diagnostics come as notifications, not request/response)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        return diagnosticsCache[uri] ?? []
    }

    /// Returns document symbols (outline) for the given document.
    /// SourceKit-LSP can return either [DocumentSymbol] (hierarchical) or
    /// [SymbolInformation] (flat). This method tries hierarchical first, then
    /// falls back to flat and converts to DocumentSymbol for a uniform API.
    func documentSymbols(uri: String) async throws -> [DocumentSymbol] {
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
            return symbols
        } catch {
            // Fall back to flat SymbolInformation and convert
            do {
                let symbols: [SymbolInformation] = try await client.sendRequest(
                    method: "textDocument/documentSymbol",
                    params: params
                )
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
                return []
            }
        }
    }

    /// Searches for workspace symbols matching the given query.
    func workspaceSymbols(query: String) async throws -> [SymbolInformation] {
        try await ensureInitialized()

        let params = WorkspaceSymbolParams(query: query)

        let result: [SymbolInformation]? = try await requireClient().sendRequestOptional(
            method: "workspace/symbol",
            params: params
        )
        return result ?? []
    }

    /// Formats an entire document.
    func formatting(uri: String, tabSize: Int = 4, insertSpaces: Bool = true) async throws -> [TextEdit] {
        try await ensureDocumentOpen(uri: uri)

        let params = DocumentFormattingParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            options: FormattingOptions(tabSize: tabSize, insertSpaces: insertSpaces)
        )

        let result: [TextEdit]? = try await requireClient().sendRequestOptional(
            method: "textDocument/formatting",
            params: params
        )
        return result ?? []
    }

    /// Returns available code actions for the given range.
    func codeActions(
        uri: String,
        range: LSPRange,
        diagnostics: [Diagnostic] = []
    ) async throws -> [CodeAction] {
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
        return result ?? []
    }

    /// Renames the symbol at the given position.
    func rename(uri: String, line: Int, character: Int, newName: String) async throws -> WorkspaceEdit {
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
        return result ?? WorkspaceEdit(changes: nil, documentChanges: nil)
    }

    // MARK: - Shutdown

    /// Gracefully shuts down the LSP server.
    func shutdown() async {
        guard initialized, let client = lspClient else { return }

        do {
            // Send shutdown request
            let _: EmptyResult? = try await client.sendRequestOptional(
                method: "shutdown",
                params: EmptyParams()
            )

            // Send exit notification
            try await client.sendNotification(method: "exit", params: EmptyParams())
        } catch {
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
    }

    // MARK: - Workspace Root Discovery

    /// Walks up the directory tree from the given file path to find the nearest
    /// project root. A project root is a directory containing Package.swift,
    /// *.xcodeproj, *.xcworkspace, compile_commands.json, or .git.
    private func discoverProjectRoot(forFileAt path: String) -> String? {
        let fileManager = FileManager.default
        var dir = (path as NSString).deletingLastPathComponent

        while dir != "/" && !dir.isEmpty {
            // Check for well-known project root markers
            let markers = ["Package.swift", "compile_commands.json", ".git"]
            for marker in markers {
                let candidate = (dir as NSString).appendingPathComponent(marker)
                if fileManager.fileExists(atPath: candidate) {
                    return dir
                }
            }

            // Check for *.xcodeproj or *.xcworkspace directories
            if let contents = try? fileManager.contentsOfDirectory(atPath: dir) {
                for entry in contents {
                    if entry.hasSuffix(".xcodeproj") || entry.hasSuffix(".xcworkspace") {
                        return dir
                    }
                }
            }

            dir = (dir as NSString).deletingLastPathComponent
        }

        return nil
    }

    /// Discovers the project root for the given file and, if it is a new root,
    /// sends a workspace/didChangeWorkspaceFolders notification to the LSP server.
    private func ensureWorkspaceRoot(forFileAt path: String) async throws {
        guard let root = discoverProjectRoot(forFileAt: path) else {
            return
        }

        let rootURI = FileURI.fromPath(root)

        guard !knownWorkspaceRoots.contains(rootURI) else {
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
    }

    // MARK: - Helpers

    private func requireClient() throws -> LSPClient {
        guard let client = lspClient else {
            throw AppleToolsError.lspNotInitialized
        }
        return client
    }

    private func handleDiagnosticsNotification(_ data: Data) {
        do {
            let params = try JSONDecoder().decode(PublishDiagnosticsParams.self, from: data)
            diagnosticsCache[params.uri] = params.diagnostics
            logger.debug("Received \(params.diagnostics.count) diagnostics for \(params.uri)")
        } catch {
            logger.warning("Failed to decode diagnostics notification: \(error.localizedDescription)")
        }
    }

    /// Determines the LSP language identifier from a file path.
    static func languageId(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "h": return "objective-c"
        case "m": return "objective-c"
        case "mm": return "objective-cpp"
        case "c": return "c"
        case "cc", "cpp", "cxx": return "cpp"
        case "hpp", "hxx": return "cpp"
        default: return "swift"
        }
    }
}

/// Empty result for requests like shutdown that return null/empty.
private struct EmptyResult: Codable, Sendable {}
