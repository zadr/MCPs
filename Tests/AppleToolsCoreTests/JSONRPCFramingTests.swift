import XCTest
@testable import AppleToolsCore

final class JSONRPCFramingTests: XCTestCase {

    // MARK: - JSONRPCFraming.encode

    func testEncodeProducesCorrectContentLength() throws {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"method":"test"}"#.utf8)
        let framed = JSONRPCFraming.encode(body)
        let framedString = String(data: framed, encoding: .utf8)!

        // Should start with Content-Length header
        XCTAssertTrue(framedString.hasPrefix("Content-Length: "))

        // Parse the content length
        let headerEnd = framedString.range(of: "\r\n\r\n")!
        let headerLine = String(framedString[framedString.startIndex..<headerEnd.lowerBound])
        let lengthStr = headerLine.replacingOccurrences(of: "Content-Length: ", with: "")
        let length = Int(lengthStr)!

        XCTAssertEqual(length, body.count)
    }

    func testEncodeProducesValidFramedMessage() throws {
        let body = Data(#"{"hello":"world"}"#.utf8)
        let framed = JSONRPCFraming.encode(body)
        let framedString = String(data: framed, encoding: .utf8)!

        // Check the full format: "Content-Length: N\r\n\r\n<body>"
        let expected = "Content-Length: \(body.count)\r\n\r\n{\"hello\":\"world\"}"
        XCTAssertEqual(framedString, expected)
    }

    func testEncodeEmptyBody() throws {
        let body = Data()
        let framed = JSONRPCFraming.encode(body)
        let framedString = String(data: framed, encoding: .utf8)!
        XCTAssertEqual(framedString, "Content-Length: 0\r\n\r\n")
    }

    func testEncodeContentLengthMatchesBodySize() throws {
        // Test with various body sizes
        let bodies = [
            Data("{}".utf8),
            Data(#"{"a":"b"}"#.utf8),
            Data(String(repeating: "x", count: 1000).utf8),
        ]

        for body in bodies {
            let framed = JSONRPCFraming.encode(body)
            let framedString = String(data: framed, encoding: .utf8)!
            let headerEnd = framedString.range(of: "\r\n\r\n")!
            let headerLine = String(framedString[framedString.startIndex..<headerEnd.lowerBound])
            let lengthStr = headerLine.replacingOccurrences(of: "Content-Length: ", with: "")
            let length = Int(lengthStr)!
            XCTAssertEqual(length, body.count, "Content-Length should match body size for body of size \(body.count)")
        }
    }

    func testEncodeFrameStructure() throws {
        let body = Data(#"{"test":true}"#.utf8)
        let framed = JSONRPCFraming.encode(body)

        // Verify the header separator \r\n\r\n exists
        let separator = Data("\r\n\r\n".utf8)
        XCTAssertNotNil(framed.range(of: separator), "Framed message should contain \\r\\n\\r\\n separator")

        // Extract parts
        let separatorRange = framed.range(of: separator)!
        let headerPart = framed[framed.startIndex..<separatorRange.lowerBound]
        let bodyPart = framed[separatorRange.upperBound..<framed.endIndex]

        // Verify body matches
        XCTAssertEqual(Data(bodyPart), body)

        // Verify header
        let headerString = String(data: Data(headerPart), encoding: .utf8)!
        XCTAssertTrue(headerString.hasPrefix("Content-Length: "))
    }

    func testEncodeUnicodeBody() throws {
        let body = Data(#"{"emoji":"🎉","text":"héllo"}"#.utf8)
        let framed = JSONRPCFraming.encode(body)
        let framedString = String(data: framed, encoding: .utf8)!

        // Content-Length should be byte count, not character count
        let headerEnd = framedString.range(of: "\r\n\r\n")!
        let headerLine = String(framedString[framedString.startIndex..<headerEnd.lowerBound])
        let lengthStr = headerLine.replacingOccurrences(of: "Content-Length: ", with: "")
        let length = Int(lengthStr)!
        XCTAssertEqual(length, body.count)
    }

    // MARK: - MessageFrameReader (parsing via pipe)

    // These tests use Pipe + MessageFrameReader to verify that the actor-based
    // frame reader correctly parses Content-Length framed messages. Each test
    // writes data to the pipe, then closes the write end so the reader finishes.

    func testMessageFrameReaderSingleMessage() async throws {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"result":null}"#.utf8)
        let framed = JSONRPCFraming.encode(body)

        let pipe = Pipe()
        let reader = MessageFrameReader(fileHandle: pipe.fileHandleForReading)

        // Write framed data and close immediately so the reader sees EOF
        pipe.fileHandleForWriting.write(framed)
        pipe.fileHandleForWriting.closeFile()

        var messages: [Data] = []
        for try await message in await reader.messages() {
            messages.append(message)
        }

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], body)
    }

    func testMessageFrameReaderMultipleMessages() async throws {
        let body1 = Data(#"{"id":1,"result":"first"}"#.utf8)
        let body2 = Data(#"{"id":2,"result":"second"}"#.utf8)
        let body3 = Data(#"{"id":3,"result":"third"}"#.utf8)

        let framed1 = JSONRPCFraming.encode(body1)
        let framed2 = JSONRPCFraming.encode(body2)
        let framed3 = JSONRPCFraming.encode(body3)

        var allData = Data()
        allData.append(framed1)
        allData.append(framed2)
        allData.append(framed3)

        let pipe = Pipe()
        let reader = MessageFrameReader(fileHandle: pipe.fileHandleForReading)

        pipe.fileHandleForWriting.write(allData)
        pipe.fileHandleForWriting.closeFile()

        var messages: [Data] = []
        for try await message in await reader.messages() {
            messages.append(message)
        }

        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0], body1)
        XCTAssertEqual(messages[1], body2)
        XCTAssertEqual(messages[2], body3)
    }

    func testMessageFrameReaderSplitAcrossChunks() async throws {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"result":"hello"}"#.utf8)
        let framed = JSONRPCFraming.encode(body)

        // Split the framed message roughly in the middle so the header and part
        // of the body arrive in the first chunk and the rest in the second.
        let splitPoint = framed.count / 2
        let chunk1 = Data(framed[framed.startIndex..<framed.index(framed.startIndex, offsetBy: splitPoint)])
        let chunk2 = Data(framed[framed.index(framed.startIndex, offsetBy: splitPoint)..<framed.endIndex])

        // Use raw POSIX pipe so we fully control file descriptor lifetimes
        // without Foundation's Pipe/FileHandle trying to double-close.
        var fds: [Int32] = [0, 0]
        let pipeResult = Darwin.pipe(&fds)
        precondition(pipeResult == 0, "pipe() failed")
        let readFD = fds[0]
        let writeFD = fds[1]

        // Wrap the read end in a FileHandle for the reader. Tell FileHandle
        // it owns the descriptor so it will close it when deallocated.
        let readHandle = FileHandle(fileDescriptor: readFD, closeOnDealloc: true)
        let reader = MessageFrameReader(fileHandle: readHandle)

        // Write chunks from a GCD queue (not Swift concurrency) with a delay
        // between them so the reader sees two separate read() calls. Using
        // DispatchQueue avoids interacting with the cooperative thread pool.
        DispatchQueue.global().async {
            chunk1.withUnsafeBytes { ptr in
                _ = Darwin.write(writeFD, ptr.baseAddress!, ptr.count)
            }
            // Small delay so the reader consumes the first chunk before the second arrives.
            Thread.sleep(forTimeInterval: 0.1)
            chunk2.withUnsafeBytes { ptr in
                _ = Darwin.write(writeFD, ptr.baseAddress!, ptr.count)
            }
            // Close the write end so the reader sees EOF.
            Darwin.close(writeFD)
        }

        var messages: [Data] = []
        for try await message in await reader.messages() {
            messages.append(message)
        }

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], body)
    }
}
