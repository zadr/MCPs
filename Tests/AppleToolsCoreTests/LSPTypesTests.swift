import XCTest
@testable import AppleToolsCore

final class LSPTypesTests: XCTestCase {

    // MARK: - LSPPosition

    func testLSPPositionEncoding() throws {
        let position = LSPPosition(line: 10, character: 5)
        let data = try JSONEncoder().encode(position)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["line"] as? Int, 10)
        XCTAssertEqual(json?["character"] as? Int, 5)
    }

    func testLSPPositionDecoding() throws {
        let json = """
        {"line": 42, "character": 7}
        """
        let position = try JSONDecoder().decode(LSPPosition.self, from: Data(json.utf8))
        XCTAssertEqual(position.line, 42)
        XCTAssertEqual(position.character, 7)
    }

    func testLSPPositionRoundTrip() throws {
        let original = LSPPosition(line: 100, character: 25)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LSPPosition.self, from: data)
        XCTAssertEqual(decoded.line, original.line)
        XCTAssertEqual(decoded.character, original.character)
    }

    // MARK: - LSPRange

    func testLSPRangeEncoding() throws {
        let range = LSPRange(
            start: LSPPosition(line: 1, character: 0),
            end: LSPPosition(line: 1, character: 10)
        )
        let data = try JSONEncoder().encode(range)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let start = json?["start"] as? [String: Any]
        let end = json?["end"] as? [String: Any]
        XCTAssertEqual(start?["line"] as? Int, 1)
        XCTAssertEqual(start?["character"] as? Int, 0)
        XCTAssertEqual(end?["line"] as? Int, 1)
        XCTAssertEqual(end?["character"] as? Int, 10)
    }

    func testLSPRangeDecoding() throws {
        let json = """
        {
            "start": {"line": 5, "character": 3},
            "end": {"line": 5, "character": 15}
        }
        """
        let range = try JSONDecoder().decode(LSPRange.self, from: Data(json.utf8))
        XCTAssertEqual(range.start.line, 5)
        XCTAssertEqual(range.start.character, 3)
        XCTAssertEqual(range.end.line, 5)
        XCTAssertEqual(range.end.character, 15)
    }

    // MARK: - HoverResult

    func testHoverResultDecodingMarkupContent() throws {
        let json = """
        {
            "contents": {
                "kind": "markdown",
                "value": "func hello() -> String"
            },
            "range": {
                "start": {"line": 0, "character": 5},
                "end": {"line": 0, "character": 10}
            }
        }
        """
        let result = try JSONDecoder().decode(HoverResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.contents, "func hello() -> String")
        XCTAssertNotNil(result.range)
        XCTAssertEqual(result.range?.start.line, 0)
        XCTAssertEqual(result.range?.start.character, 5)
    }

    func testHoverResultDecodingRawString() throws {
        let json = """
        {
            "contents": "Some hover text"
        }
        """
        let result = try JSONDecoder().decode(HoverResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.contents, "Some hover text")
        XCTAssertNil(result.range)
    }

    func testHoverResultDecodingNoRange() throws {
        let json = """
        {
            "contents": {
                "kind": "plaintext",
                "value": "Int"
            }
        }
        """
        let result = try JSONDecoder().decode(HoverResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.contents, "Int")
        XCTAssertNil(result.range)
    }

    // MARK: - CompletionItem

    func testCompletionItemDecoding() throws {
        let json = """
        {
            "label": "myFunction",
            "kind": 3,
            "detail": "() -> Void",
            "insertText": "myFunction()"
        }
        """
        let item = try JSONDecoder().decode(CompletionItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.label, "myFunction")
        XCTAssertEqual(item.kind, 3)
        XCTAssertEqual(item.detail, "() -> Void")
        XCTAssertEqual(item.insertText, "myFunction()")
    }

    func testCompletionItemMinimal() throws {
        let json = """
        {
            "label": "someVar"
        }
        """
        let item = try JSONDecoder().decode(CompletionItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.label, "someVar")
        XCTAssertNil(item.kind)
        XCTAssertNil(item.detail)
        XCTAssertNil(item.insertText)
    }

    func testCompletionItemWithStringDocumentation() throws {
        let json = """
        {
            "label": "print",
            "kind": 3,
            "documentation": "Prints to stdout"
        }
        """
        let item = try JSONDecoder().decode(CompletionItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.label, "print")
        if case .string(let doc) = item.documentation {
            XCTAssertEqual(doc, "Prints to stdout")
        } else {
            XCTFail("Expected string documentation")
        }
    }

    func testCompletionItemWithMarkupDocumentation() throws {
        let json = """
        {
            "label": "print",
            "kind": 3,
            "documentation": {"kind": "markdown", "value": "**Prints** to stdout"}
        }
        """
        let item = try JSONDecoder().decode(CompletionItem.self, from: Data(json.utf8))
        if case .markup(let mc) = item.documentation {
            XCTAssertEqual(mc.value, "**Prints** to stdout")
            XCTAssertEqual(mc.kind, "markdown")
        } else {
            XCTFail("Expected markup documentation")
        }
    }

    // MARK: - Diagnostic

    func testDiagnosticDecoding() throws {
        let json = """
        {
            "range": {
                "start": {"line": 10, "character": 0},
                "end": {"line": 10, "character": 5}
            },
            "severity": 1,
            "message": "Use of unresolved identifier 'foo'",
            "source": "swift"
        }
        """
        let diag = try JSONDecoder().decode(Diagnostic.self, from: Data(json.utf8))
        XCTAssertEqual(diag.range.start.line, 10)
        XCTAssertEqual(diag.range.start.character, 0)
        XCTAssertEqual(diag.severity, 1)
        XCTAssertEqual(diag.message, "Use of unresolved identifier 'foo'")
        XCTAssertEqual(diag.source, "swift")
    }

    func testDiagnosticDecodingMinimal() throws {
        let json = """
        {
            "range": {
                "start": {"line": 0, "character": 0},
                "end": {"line": 0, "character": 0}
            },
            "message": "some warning"
        }
        """
        let diag = try JSONDecoder().decode(Diagnostic.self, from: Data(json.utf8))
        XCTAssertEqual(diag.message, "some warning")
        XCTAssertNil(diag.severity)
        XCTAssertNil(diag.source)
    }

    // MARK: - DocumentSymbol

    func testDocumentSymbolDecoding() throws {
        let json = """
        {
            "name": "MyClass",
            "kind": 5,
            "range": {
                "start": {"line": 0, "character": 0},
                "end": {"line": 20, "character": 1}
            },
            "selectionRange": {
                "start": {"line": 0, "character": 6},
                "end": {"line": 0, "character": 13}
            }
        }
        """
        let symbol = try JSONDecoder().decode(DocumentSymbol.self, from: Data(json.utf8))
        XCTAssertEqual(symbol.name, "MyClass")
        XCTAssertEqual(symbol.kind, 5)
        XCTAssertEqual(symbol.range.start.line, 0)
        XCTAssertEqual(symbol.range.end.line, 20)
        XCTAssertNil(symbol.children)
    }

    func testDocumentSymbolWithChildren() throws {
        let json = """
        {
            "name": "MyClass",
            "kind": 5,
            "range": {
                "start": {"line": 0, "character": 0},
                "end": {"line": 20, "character": 1}
            },
            "selectionRange": {
                "start": {"line": 0, "character": 6},
                "end": {"line": 0, "character": 13}
            },
            "children": [
                {
                    "name": "init",
                    "kind": 9,
                    "range": {
                        "start": {"line": 1, "character": 4},
                        "end": {"line": 3, "character": 5}
                    },
                    "selectionRange": {
                        "start": {"line": 1, "character": 4},
                        "end": {"line": 1, "character": 8}
                    }
                },
                {
                    "name": "name",
                    "kind": 7,
                    "range": {
                        "start": {"line": 5, "character": 4},
                        "end": {"line": 5, "character": 30}
                    },
                    "selectionRange": {
                        "start": {"line": 5, "character": 8},
                        "end": {"line": 5, "character": 12}
                    }
                }
            ]
        }
        """
        let symbol = try JSONDecoder().decode(DocumentSymbol.self, from: Data(json.utf8))
        XCTAssertEqual(symbol.name, "MyClass")
        XCTAssertNotNil(symbol.children)
        XCTAssertEqual(symbol.children?.count, 2)
        XCTAssertEqual(symbol.children?[0].name, "init")
        XCTAssertEqual(symbol.children?[0].kind, 9)
        XCTAssertEqual(symbol.children?[1].name, "name")
        XCTAssertEqual(symbol.children?[1].kind, 7)
    }

    // MARK: - WorkspaceEdit

    func testWorkspaceEditDecodingWithChanges() throws {
        let json = """
        {
            "changes": {
                "file:///path/to/file.swift": [
                    {
                        "range": {
                            "start": {"line": 5, "character": 10},
                            "end": {"line": 5, "character": 15}
                        },
                        "newText": "newName"
                    }
                ]
            }
        }
        """
        let edit = try JSONDecoder().decode(WorkspaceEdit.self, from: Data(json.utf8))
        XCTAssertNotNil(edit.changes)
        XCTAssertEqual(edit.changes?.count, 1)
        let fileEdits = edit.changes?["file:///path/to/file.swift"]
        XCTAssertEqual(fileEdits?.count, 1)
        XCTAssertEqual(fileEdits?[0].newText, "newName")
        XCTAssertEqual(fileEdits?[0].range.start.line, 5)
        XCTAssertNil(edit.documentChanges)
    }

    func testWorkspaceEditDecodingWithDocumentChanges() throws {
        let json = """
        {
            "documentChanges": [
                {
                    "textDocument": {"uri": "file:///path/to/file.swift", "version": 1},
                    "edits": [
                        {
                            "range": {
                                "start": {"line": 0, "character": 0},
                                "end": {"line": 0, "character": 5}
                            },
                            "newText": "hello"
                        }
                    ]
                }
            ]
        }
        """
        let edit = try JSONDecoder().decode(WorkspaceEdit.self, from: Data(json.utf8))
        XCTAssertNotNil(edit.documentChanges)
        XCTAssertEqual(edit.documentChanges?.count, 1)
        XCTAssertEqual(edit.documentChanges?[0].textDocument.uri, "file:///path/to/file.swift")
        XCTAssertEqual(edit.documentChanges?[0].edits.count, 1)
        XCTAssertEqual(edit.documentChanges?[0].edits[0].newText, "hello")
    }

    func testWorkspaceEditDecodingEmpty() throws {
        let json = """
        {}
        """
        let edit = try JSONDecoder().decode(WorkspaceEdit.self, from: Data(json.utf8))
        XCTAssertNil(edit.changes)
        XCTAssertNil(edit.documentChanges)
    }

    // MARK: - LSPSymbolKind

    func testLSPSymbolKindDescriptions() {
        XCTAssertEqual(LSPSymbolKind.file.description, "File")
        XCTAssertEqual(LSPSymbolKind.module.description, "Module")
        XCTAssertEqual(LSPSymbolKind.namespace.description, "Namespace")
        XCTAssertEqual(LSPSymbolKind.package.description, "Package")
        XCTAssertEqual(LSPSymbolKind.class.description, "Class")
        XCTAssertEqual(LSPSymbolKind.method.description, "Method")
        XCTAssertEqual(LSPSymbolKind.property.description, "Property")
        XCTAssertEqual(LSPSymbolKind.field.description, "Field")
        XCTAssertEqual(LSPSymbolKind.constructor.description, "Constructor")
        XCTAssertEqual(LSPSymbolKind.enum.description, "Enum")
        XCTAssertEqual(LSPSymbolKind.interface.description, "Interface")
        XCTAssertEqual(LSPSymbolKind.function.description, "Function")
        XCTAssertEqual(LSPSymbolKind.variable.description, "Variable")
        XCTAssertEqual(LSPSymbolKind.constant.description, "Constant")
        XCTAssertEqual(LSPSymbolKind.string.description, "String")
        XCTAssertEqual(LSPSymbolKind.number.description, "Number")
        XCTAssertEqual(LSPSymbolKind.boolean.description, "Boolean")
        XCTAssertEqual(LSPSymbolKind.array.description, "Array")
        XCTAssertEqual(LSPSymbolKind.object.description, "Object")
        XCTAssertEqual(LSPSymbolKind.key.description, "Key")
        XCTAssertEqual(LSPSymbolKind.null.description, "Null")
        XCTAssertEqual(LSPSymbolKind.enumMember.description, "EnumMember")
        XCTAssertEqual(LSPSymbolKind.struct.description, "Struct")
        XCTAssertEqual(LSPSymbolKind.event.description, "Event")
        XCTAssertEqual(LSPSymbolKind.operator.description, "Operator")
        XCTAssertEqual(LSPSymbolKind.typeParameter.description, "TypeParameter")
    }

    func testLSPSymbolKindRawValues() {
        XCTAssertEqual(LSPSymbolKind(rawValue: 1), .file)
        XCTAssertEqual(LSPSymbolKind(rawValue: 5), .class)
        XCTAssertEqual(LSPSymbolKind(rawValue: 12), .function)
        XCTAssertEqual(LSPSymbolKind(rawValue: 23), .struct)
        XCTAssertEqual(LSPSymbolKind(rawValue: 26), .typeParameter)
        XCTAssertNil(LSPSymbolKind(rawValue: 0))
        XCTAssertNil(LSPSymbolKind(rawValue: 27))
        XCTAssertNil(LSPSymbolKind(rawValue: -1))
    }

    // MARK: - CompletionList

    func testCompletionListDecoding() throws {
        let json = """
        {
            "isIncomplete": true,
            "items": [
                {"label": "foo", "kind": 6},
                {"label": "bar", "kind": 3}
            ]
        }
        """
        let list = try JSONDecoder().decode(CompletionList.self, from: Data(json.utf8))
        XCTAssertTrue(list.isIncomplete)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].label, "foo")
        XCTAssertEqual(list.items[1].label, "bar")
    }

    // MARK: - SymbolInformation

    func testSymbolInformationDecoding() throws {
        let json = """
        {
            "name": "MyFunc",
            "kind": 12,
            "location": {
                "uri": "file:///path/to/file.swift",
                "range": {
                    "start": {"line": 10, "character": 0},
                    "end": {"line": 15, "character": 1}
                }
            },
            "containerName": "MyClass"
        }
        """
        let info = try JSONDecoder().decode(SymbolInformation.self, from: Data(json.utf8))
        XCTAssertEqual(info.name, "MyFunc")
        XCTAssertEqual(info.kind, 12)
        XCTAssertEqual(info.location.uri, "file:///path/to/file.swift")
        XCTAssertEqual(info.containerName, "MyClass")
    }

    // MARK: - LSPLocation

    func testLSPLocationDecoding() throws {
        let json = """
        {
            "uri": "file:///test.swift",
            "range": {
                "start": {"line": 0, "character": 0},
                "end": {"line": 0, "character": 10}
            }
        }
        """
        let location = try JSONDecoder().decode(LSPLocation.self, from: Data(json.utf8))
        XCTAssertEqual(location.uri, "file:///test.swift")
        XCTAssertEqual(location.range.start.line, 0)
        XCTAssertEqual(location.range.end.character, 10)
    }

    // MARK: - CodeAction

    func testCodeActionDecoding() throws {
        let json = """
        {
            "title": "Add missing import",
            "kind": "quickfix",
            "edit": {
                "changes": {
                    "file:///test.swift": [
                        {
                            "range": {
                                "start": {"line": 0, "character": 0},
                                "end": {"line": 0, "character": 0}
                            },
                            "newText": "import Foundation\\n"
                        }
                    ]
                }
            }
        }
        """
        let action = try JSONDecoder().decode(CodeAction.self, from: Data(json.utf8))
        XCTAssertEqual(action.title, "Add missing import")
        XCTAssertEqual(action.kind, "quickfix")
        XCTAssertNotNil(action.edit)
        XCTAssertNotNil(action.edit?.changes)
    }

    func testCodeActionMinimal() throws {
        let json = """
        {
            "title": "Refactor"
        }
        """
        let action = try JSONDecoder().decode(CodeAction.self, from: Data(json.utf8))
        XCTAssertEqual(action.title, "Refactor")
        XCTAssertNil(action.kind)
        XCTAssertNil(action.edit)
        XCTAssertNil(action.diagnostics)
    }

    // MARK: - TextEdit

    func testTextEditRoundTrip() throws {
        let edit = TextEdit(
            range: LSPRange(
                start: LSPPosition(line: 3, character: 0),
                end: LSPPosition(line: 3, character: 20)
            ),
            newText: "let x = 42"
        )
        let data = try JSONEncoder().encode(edit)
        let decoded = try JSONDecoder().decode(TextEdit.self, from: data)
        XCTAssertEqual(decoded.newText, "let x = 42")
        XCTAssertEqual(decoded.range.start.line, 3)
        XCTAssertEqual(decoded.range.end.character, 20)
    }
}
