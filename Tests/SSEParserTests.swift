import XCTest
@testable import SimpleChat

final class SSEParserTests: XCTestCase {
    private var parser = SSEDeltaParser()

    override func setUp() {
        super.setUp()
        parser = SSEDeltaParser()
    }

    func testIgnoresNonDataLines() throws {
        XCTAssertTrue(try parser.feed(line: ": keep-alive").isEmpty)
        XCTAssertTrue(try parser.feed(line: "event: ping").isEmpty)
        XCTAssertTrue(try parser.feed(line: "").isEmpty)
    }

    func testOpenAIContentDelta() throws {
        let events = try parser.feed(
            line: #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        )
        XCTAssertEqual(events, [.textDelta("你好")])
    }

    func testOpenAIReasoningDelta() throws {
        let events = try parser.feed(
            line: #"data: {"choices":[{"delta":{"reasoning_content":"思考中"}}]}"#
        )
        XCTAssertEqual(events, [.reasoningDelta("思考中")])
    }

    func testOpenAIFinishReason() throws {
        let events = try parser.feed(
            line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        )
        XCTAssertEqual(events.count, 1)
        if case .finished = events[0] {} else { XCTFail("应为 finished") }
    }

    func testOpenAIDone() throws {
        let events = try parser.feed(line: "data: [DONE]")
        XCTAssertEqual(events.count, 1)
        if case .finished = events[0] {} else { XCTFail("应为 finished") }
    }

    func testAnthropicTextDelta() throws {
        let events = try parser.feed(
            line: #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}"#
        )
        XCTAssertEqual(events, [.textDelta("hi")])
    }

    func testAnthropicThinkingDelta() throws {
        let events = try parser.feed(
            line: #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}"#
        )
        XCTAssertEqual(events, [.reasoningDelta("hmm")])
    }

    func testAnthropicMessageStop() throws {
        let events = try parser.feed(line: #"data: {"type":"message_stop"}"#)
        if case .finished? = events.first {} else { XCTFail("应为 finished") }
    }

    func testAnthropicErrorThrows() throws {
        XCTAssertThrowsError(try parser.feed(
            line: #"data: {"type":"error","error":{"type":"invalid_request_error","message":"bad"}}"#
        )) { error in
            guard case ChatError.api(let m) = error else {
                return XCTFail("应为 ChatError.api")
            }
            XCTAssertEqual(m, "bad")
        }
    }

    func testIgnoresAnthropicLifecycleFrames() throws {
        XCTAssertTrue(try parser.feed(line: #"data: {"type":"ping"}"#).isEmpty)
        XCTAssertTrue(try parser.feed(
            line: #"data: {"type":"message_start","message":{"id":"x"}}"#
        ).isEmpty)
    }
}
