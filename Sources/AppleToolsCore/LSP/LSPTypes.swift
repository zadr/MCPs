import Foundation

// MARK: - Core Position/Range Types

struct LSPPosition: Codable, Sendable {
    let line: Int
    let character: Int
}

struct LSPRange: Codable, Sendable {
    let start: LSPPosition
    let end: LSPPosition
}

struct LSPLocation: Codable, Sendable {
    let uri: String
    let range: LSPRange
}

// MARK: - Text Document Identifiers

struct TextDocumentIdentifier: Codable, Sendable {
    let uri: String
}

struct TextDocumentItem: Codable, Sendable {
    let uri: String
    let languageId: String
    let version: Int
    let text: String
}

struct TextDocumentPositionParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
}

// MARK: - Initialize

struct InitializeParams: Codable, Sendable {
    let processId: Int?
    let rootUri: String?
    let capabilities: ClientCapabilities
}

struct ClientCapabilities: Codable, Sendable {
    let workspace: WorkspaceClientCapabilities?

    init(workspace: WorkspaceClientCapabilities? = nil) {
        self.workspace = workspace
    }
}

struct WorkspaceClientCapabilities: Codable, Sendable {
    let workspaceFolders: Bool?
}

struct InitializeResult: Codable, Sendable {
    let capabilities: ServerCapabilities?
}

struct ServerCapabilities: Codable, Sendable {
    let textDocumentSync: TextDocumentSyncValue?
    let hoverProvider: Bool?
    let completionProvider: CompletionOptions?
    let definitionProvider: Bool?
    let referencesProvider: Bool?
    let documentSymbolProvider: Bool?
    let workspaceSymbolProvider: Bool?
    let codeActionProvider: CodeActionProviderValue?
    let documentFormattingProvider: FormattingProviderValue?
    let renameProvider: RenameProviderValue?

    enum CodingKeys: String, CodingKey {
        case textDocumentSync, hoverProvider, completionProvider
        case definitionProvider, referencesProvider, documentSymbolProvider
        case workspaceSymbolProvider, codeActionProvider, documentFormattingProvider
        case renameProvider
    }

    init(from decoder: Decoder) throws {
        TraceLog.enter()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textDocumentSync = try container.decodeIfPresent(TextDocumentSyncValue.self, forKey: .textDocumentSync)
        hoverProvider = try container.decodeIfPresent(Bool.self, forKey: .hoverProvider)
        completionProvider = try container.decodeIfPresent(CompletionOptions.self, forKey: .completionProvider)
        definitionProvider = try container.decodeIfPresent(Bool.self, forKey: .definitionProvider)
        referencesProvider = try container.decodeIfPresent(Bool.self, forKey: .referencesProvider)
        documentSymbolProvider = try container.decodeIfPresent(Bool.self, forKey: .documentSymbolProvider)
        workspaceSymbolProvider = try container.decodeIfPresent(Bool.self, forKey: .workspaceSymbolProvider)
        codeActionProvider = try container.decodeIfPresent(CodeActionProviderValue.self, forKey: .codeActionProvider)
        documentFormattingProvider = try container.decodeIfPresent(FormattingProviderValue.self, forKey: .documentFormattingProvider)
        renameProvider = try container.decodeIfPresent(RenameProviderValue.self, forKey: .renameProvider)
    }
}

// sourcekit-lsp sends textDocumentSync as either an Int or an object
enum TextDocumentSyncValue: Codable, Sendable {
    case kind(Int)
    case options(TextDocumentSyncOptions)

    struct TextDocumentSyncOptions: Codable, Sendable {
        let openClose: Bool?
        let change: Int?
    }

    init(from decoder: Decoder) throws {
        TraceLog.enter()
        let container = try decoder.singleValueContainer()
        if let kind = try? container.decode(Int.self) {
            TraceLog.point("decode-kind")
            self = .kind(kind)
        } else {
            TraceLog.point("decode-options")
            let options = try container.decode(TextDocumentSyncOptions.self)
            self = .options(options)
        }
    }

    func encode(to encoder: Encoder) throws {
        TraceLog.enter()
        var container = encoder.singleValueContainer()
        switch self {
        case .kind(let kind):
            TraceLog.point("encode-kind")
            try container.encode(kind)
        case .options(let options):
            TraceLog.point("encode-options")
            try container.encode(options)
        }
    }
}

// codeActionProvider can be Bool or object
enum CodeActionProviderValue: Codable, Sendable {
    case bool(Bool)
    case options(CodeActionOptions)

    struct CodeActionOptions: Codable, Sendable {
        let codeActionKinds: [String]?
    }

    init(from decoder: Decoder) throws {
        TraceLog.enter()
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            TraceLog.point("decode-bool")
            self = .bool(b)
        } else {
            TraceLog.point("decode-options")
            let opts = try container.decode(CodeActionOptions.self)
            self = .options(opts)
        }
    }

    func encode(to encoder: Encoder) throws {
        TraceLog.enter()
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let b):
            TraceLog.point("encode-bool")
            try container.encode(b)
        case .options(let opts):
            TraceLog.point("encode-options")
            try container.encode(opts)
        }
    }
}

// renameProvider can be Bool or object
enum RenameProviderValue: Codable, Sendable {
    case bool(Bool)
    case options(RenameOptions)

    struct RenameOptions: Codable, Sendable {
        let prepareProvider: Bool?
    }

    init(from decoder: Decoder) throws {
        TraceLog.enter()
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            TraceLog.point("decode-bool")
            self = .bool(b)
        } else {
            TraceLog.point("decode-options")
            let opts = try container.decode(RenameOptions.self)
            self = .options(opts)
        }
    }

    func encode(to encoder: Encoder) throws {
        TraceLog.enter()
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let b):
            TraceLog.point("encode-bool")
            try container.encode(b)
        case .options(let opts):
            TraceLog.point("encode-options")
            try container.encode(opts)
        }
    }
}

// documentFormattingProvider can be Bool or object
enum FormattingProviderValue: Codable, Sendable {
    case bool(Bool)
    case options(FormattingProviderOptions)

    struct FormattingProviderOptions: Codable, Sendable {}

    init(from decoder: Decoder) throws {
        TraceLog.enter()
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            TraceLog.point("decode-bool")
            self = .bool(b)
        } else {
            TraceLog.point("decode-options")
            let opts = try container.decode(FormattingProviderOptions.self)
            self = .options(opts)
        }
    }

    func encode(to encoder: Encoder) throws {
        TraceLog.enter()
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let b):
            TraceLog.point("encode-bool")
            try container.encode(b)
        case .options(let opts):
            TraceLog.point("encode-options")
            try container.encode(opts)
        }
    }
}

struct CompletionOptions: Codable, Sendable {
    let triggerCharacters: [String]?
    let resolveProvider: Bool?
}

// MARK: - Hover

/// HoverResult decodes the LSP Hover response. The `contents` field is normalized
/// to a plain String regardless of whether the server sends MarkupContent or a raw string.
struct HoverResult: Sendable {
    let contents: String
    let range: LSPRange?
}

extension HoverResult: Codable {
    enum CodingKeys: String, CodingKey {
        case contents, range
    }

    init(from decoder: Decoder) throws {
        TraceLog.enter()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decodeIfPresent(LSPRange.self, forKey: .range)

        // contents can be MarkupContent (object with kind+value) or a plain string
        if let markup = try? container.decode(MarkupContent.self, forKey: .contents) {
            TraceLog.point("contents-markup")
            contents = markup.value
        } else if let str = try? container.decode(String.self, forKey: .contents) {
            TraceLog.point("contents-string")
            contents = str
        } else {
            TraceLog.point("contents-empty")
            contents = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        TraceLog.enter()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MarkupContent(kind: "markdown", value: contents), forKey: .contents)
        try container.encodeIfPresent(range, forKey: .range)
    }
}

struct MarkupContent: Codable, Sendable {
    let kind: String
    let value: String
}

// MARK: - Completion

struct CompletionList: Codable, Sendable {
    let isIncomplete: Bool
    let items: [CompletionItem]
}

struct CompletionItem: Codable, Sendable {
    let label: String
    let kind: Int?
    let detail: String?
    let insertText: String?
    let documentation: CompletionDocumentation?
}

// documentation field can be a string or MarkupContent
enum CompletionDocumentation: Codable, Sendable {
    case string(String)
    case markup(MarkupContent)

    init(from decoder: Decoder) throws {
        TraceLog.enter()
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            TraceLog.point("decode-string")
            self = .string(s)
        } else {
            TraceLog.point("decode-markup")
            let m = try container.decode(MarkupContent.self)
            self = .markup(m)
        }
    }

    func encode(to encoder: Encoder) throws {
        TraceLog.enter()
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            TraceLog.point("encode-string")
            try container.encode(s)
        case .markup(let m):
            TraceLog.point("encode-markup")
            try container.encode(m)
        }
    }

    var value: String {
        switch self {
        case .string(let s): return s
        case .markup(let m): return m.value
        }
    }
}

// MARK: - Diagnostics

struct PublishDiagnosticsParams: Codable, Sendable {
    let uri: String
    let diagnostics: [Diagnostic]
}

struct Diagnostic: Codable, Sendable {
    let range: LSPRange
    let severity: Int?
    let message: String
    let source: String?
}

// MARK: - Document Symbols

struct DocumentSymbol: Codable, Sendable {
    let name: String
    let kind: Int
    let range: LSPRange
    let selectionRange: LSPRange
    let children: [DocumentSymbol]?
}

struct SymbolInformation: Codable, Sendable {
    let name: String
    let kind: Int
    let location: LSPLocation
    let containerName: String?
}

struct DocumentSymbolParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
}

struct WorkspaceSymbolParams: Codable, Sendable {
    let query: String
}

// MARK: - Formatting

struct TextEdit: Codable, Sendable {
    let range: LSPRange
    let newText: String
}

struct DocumentFormattingParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let options: FormattingOptions
}

struct FormattingOptions: Codable, Sendable {
    let tabSize: Int
    let insertSpaces: Bool
}

// MARK: - Code Actions

struct CodeActionParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let range: LSPRange
    let context: CodeActionContext
}

struct CodeActionContext: Codable, Sendable {
    let diagnostics: [Diagnostic]
}

struct CodeAction: Codable, Sendable {
    let title: String
    let kind: String?
    let edit: WorkspaceEdit?
    let diagnostics: [Diagnostic]?
}

struct WorkspaceEdit: Codable, Sendable {
    let changes: [String: [TextEdit]]?
    let documentChanges: [TextDocumentEdit]?
}

struct TextDocumentEdit: Codable, Sendable {
    let textDocument: VersionedTextDocumentIdentifier
    let edits: [TextEdit]
}

struct VersionedTextDocumentIdentifier: Codable, Sendable {
    let uri: String
    let version: Int?
}

// MARK: - Rename

struct RenameParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
    let newName: String
}

// MARK: - References

struct ReferenceParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
    let context: ReferenceContext
}

struct ReferenceContext: Codable, Sendable {
    let includeDeclaration: Bool
}

// MARK: - Document Lifecycle Notifications

struct DidOpenTextDocumentParams: Codable, Sendable {
    let textDocument: TextDocumentItem
}

struct DidCloseTextDocumentParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
}

// MARK: - Workspace Folders

struct WorkspaceFolder: Codable, Sendable {
    let uri: String
    let name: String
}

struct WorkspaceFoldersChangeEvent: Codable, Sendable {
    let added: [WorkspaceFolder]
    let removed: [WorkspaceFolder]
}

struct DidChangeWorkspaceFoldersParams: Codable, Sendable {
    let event: WorkspaceFoldersChangeEvent
}

// MARK: - Empty Params

struct EmptyParams: Codable, Sendable {
    // Used for notifications like "initialized" and "exit" that have no params
}

// MARK: - Completion Params

struct CompletionParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
}

// MARK: - Symbol Kind

enum LSPSymbolKind: Int, Sendable {
    case file = 1
    case module = 2
    case namespace = 3
    case package = 4
    case `class` = 5
    case method = 6
    case property = 7
    case field = 8
    case constructor = 9
    case `enum` = 10
    case interface = 11
    case function = 12
    case variable = 13
    case constant = 14
    case string = 15
    case number = 16
    case boolean = 17
    case array = 18
    case object = 19
    case key = 20
    case null = 21
    case enumMember = 22
    case `struct` = 23
    case event = 24
    case `operator` = 25
    case typeParameter = 26

    var description: String {
        switch self {
        case .file: return "File"
        case .module: return "Module"
        case .namespace: return "Namespace"
        case .package: return "Package"
        case .class: return "Class"
        case .method: return "Method"
        case .property: return "Property"
        case .field: return "Field"
        case .constructor: return "Constructor"
        case .enum: return "Enum"
        case .interface: return "Interface"
        case .function: return "Function"
        case .variable: return "Variable"
        case .constant: return "Constant"
        case .string: return "String"
        case .number: return "Number"
        case .boolean: return "Boolean"
        case .array: return "Array"
        case .object: return "Object"
        case .key: return "Key"
        case .null: return "Null"
        case .enumMember: return "Case"
        case .struct: return "Struct"
        case .event: return "Event"
        case .operator: return "Operator"
        case .typeParameter: return "TypeParameter"
        }
    }
}
