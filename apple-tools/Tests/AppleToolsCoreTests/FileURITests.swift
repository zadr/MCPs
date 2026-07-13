import XCTest
@testable import AppleToolsCore

final class FileURITests: XCTestCase {

    // MARK: - fromPath

    func testFromPathAbsolutePath() {
        let uri = FileURI.fromPath("/usr/local/bin/swift")
        XCTAssertEqual(uri, "file:///usr/local/bin/swift")
    }

    func testFromPathRootPath() {
        let uri = FileURI.fromPath("/")
        XCTAssertEqual(uri, "file:///")
    }

    func testFromPathWithSpaces() {
        let uri = FileURI.fromPath("/Users/test user/my file.swift")
        XCTAssertEqual(uri, "file:///Users/test user/my file.swift")
    }

    func testFromPathRelativePathGetsPrefixed() {
        // Relative paths should get the current directory prepended
        let uri = FileURI.fromPath("relative/path.swift")
        let cwd = FileManager.default.currentDirectoryPath
        XCTAssertEqual(uri, "file://\(cwd)/relative/path.swift")
    }

    func testFromPathAlreadyAbsolute() {
        let uri = FileURI.fromPath("/some/absolute/path.swift")
        XCTAssertTrue(uri.hasPrefix("file:///"))
        XCTAssertEqual(uri, "file:///some/absolute/path.swift")
    }

    // MARK: - toPath

    func testToPathFileURI() {
        let path = FileURI.toPath("file:///usr/local/bin/swift")
        XCTAssertEqual(path, "/usr/local/bin/swift")
    }

    func testToPathPlainPath() {
        // If the string doesn't have file:// prefix, it should be returned as-is
        let path = FileURI.toPath("/usr/local/bin/swift")
        XCTAssertEqual(path, "/usr/local/bin/swift")
    }

    func testToPathWithSpaces() {
        let path = FileURI.toPath("file:///Users/test user/my file.swift")
        XCTAssertEqual(path, "/Users/test user/my file.swift")
    }

    func testToPathNonFileURI() {
        // Non-file URIs should be returned as-is
        let path = FileURI.toPath("https://example.com/file.swift")
        XCTAssertEqual(path, "https://example.com/file.swift")
    }

    // MARK: - Round-trip

    func testRoundTripFromPathToPath() {
        let originalPath = "/Users/developer/Projects/MyApp/Sources/main.swift"
        let uri = FileURI.fromPath(originalPath)
        let recoveredPath = FileURI.toPath(uri)
        XCTAssertEqual(recoveredPath, originalPath)
    }

    func testRoundTripWithSpaces() {
        let originalPath = "/Users/My User/My Project/My File.swift"
        let uri = FileURI.fromPath(originalPath)
        let recoveredPath = FileURI.toPath(uri)
        XCTAssertEqual(recoveredPath, originalPath)
    }

    func testRoundTripWithSpecialCharacters() {
        let originalPath = "/tmp/test-file_v2.0.swift"
        let uri = FileURI.fromPath(originalPath)
        let recoveredPath = FileURI.toPath(uri)
        XCTAssertEqual(recoveredPath, originalPath)
    }
}
