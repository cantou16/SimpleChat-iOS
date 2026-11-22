import XCTest
@testable import SimpleChat

final class HTTPStreamParserTests: XCTestCase {

    private func feed(_ parser: HTTPStreamParser, _ text: String) throws -> [String] {
        try parser.feed(Data(text.utf8))
    }

    // MARK: - 头部与 Content-Length

    func testHeadersSplitAcrossFeeds() throws {
        let parser = HTTPStreamParser()
        XCTAssertTrue(try feed(parser, "HTTP/1.1 200 OK\r\nContent-Len").isEmpty)
        XCTAssertTrue(try feed(parser, "gth: 28\r\nContent-Type: text/event-stream\r\n\r\n").isEmpty)
        XCTAssertEqual(parser.statusCode, 200)
        let lines = try feed(parser, "data: {\"a\":1}\n\ndata: [DONE]\n")
        XCTAssertEqual(lines, ["data: {\"a\":1}", "", "data: [DONE]"])
        XCTAssertTrue(parser.isComplete)
    }

    func testContentLengthStopsExactly() throws {
        let parser = HTTPStreamParser()
        _ = try feed(parser, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nx\n")
        XCTAssertFalse(parser.isComplete)
        let lines = try feed(parser, "y\nEXTRA-TRAILING-GARBAGE")
        XCTAssertEqual(lines, ["y"])
        XCTAssertTrue(parser.isComplete)
    }

    // MARK: - chunked

    func testChunkedTwoChunks() throws {
        let parser = HTTPStreamParser()
        _ = try feed(parser, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        // "data: A\n" = 8 bytes
        let lines1 = try feed(parser, "8\r\ndata: A\n\r\n")
        XCTAssertEqual(lines1, ["data: A"])
        let lines2 = try feed(parser, "8\r\ndata: B\n\r\n0\r\n\r\n")
        XCTAssertEqual(lines2, ["data: B"])
        XCTAssertTrue(parser.isComplete)
    }

    func testChunkedSplitMidChunk() throws {
        let parser = HTTPStreamParser()
        _ = try feed(parser, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        _ = try feed(parser, "8\r\ndata: ")
        let lines = try feed(parser, "C\n\r\n0\r\n\r\n")
        XCTAssertEqual(lines, ["data: C"])
        XCTAssertTrue(parser.isComplete)
    }

    func testChunkedWithCRLFLineEndings() throws {
        let parser = HTTPStreamParser()
        _ = try feed(parser, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        // "data: x\r\n" = 9 bytes
        let lines = try feed(parser, "9\r\ndata: x\r\n\r\n0\r\n\r\n")
        XCTAssertEqual(lines, ["data: x"])
    }

    // MARK: - 错误响应

    func testNon200CollectsErrorBody() throws {
        let parser = HTTPStreamParser()
        let lines = try feed(parser, "HTTP/1.1 401 Unauthorized\r\nContent-Length: 43\r\n\r\n")
        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(parser.statusCode, 401)
        _ = try feed(parser, "{\"error\":{\"message\":\"Invalid API key\"}}")
        XCTAssertEqual(parser.errorMessage(fallback: "fb"), "Invalid API key")
    }

    func testMalformedStatusLineThrows() {
        let parser = HTTPStreamParser()
        XCTAssertThrowsError(try parser.feed(Data("GARBAGE 200\r\n\r\n".utf8)))
    }
}
