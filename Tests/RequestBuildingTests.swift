import XCTest
@testable import SimpleChat

final class RequestBuildingTests: XCTestCase {

    // MARK: - URL 归一化

    func testOpenAIAppendV1() {
        let url = URLNormalizer.chatURL(endpoint: "https://api.deepseek.com", style: .openAICompatible)
        XCTAssertEqual(url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
    }

    func testOpenAIKeepExistingV1() {
        let url = URLNormalizer.chatURL(endpoint: "https://x.com/v1/", style: .openAICompatible)
        XCTAssertEqual(url?.absoluteString, "https://x.com/v1/chat/completions")
    }

    func testOpenAIFullPathKept() {
        let url = URLNormalizer.chatURL(
            endpoint: "https://x.com/v1/chat/completions",
            style: .openAICompatible
        )
        XCTAssertEqual(url?.absoluteString, "https://x.com/v1/chat/completions")
    }

    func testAnthropicAppendV1Messages() {
        let url = URLNormalizer.chatURL(endpoint: "https://api.anthropic.com", style: .anthropic)
        XCTAssertEqual(url?.absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testNonHTTPTypesRejected() {
        XCTAssertNil(URLNormalizer.chatURL(endpoint: "ftp://x.com", style: .openAICompatible))
        XCTAssertNil(URLNormalizer.chatURL(endpoint: "api.deepseek.com", style: .openAICompatible))
        XCTAssertNil(URLNormalizer.chatURL(endpoint: "", style: .anthropic))
    }

    func testDirtyInputRejected() {
        // 非 ASCII host / 内部空白 → 拒绝（这些输入走 CFNetwork 转义路径有已知崩溃面）
        XCTAssertNil(URLNormalizer.chatURL(endpoint: "https://中文.域名.com", style: .openAICompatible))
        XCTAssertNil(URLNormalizer.chatURL(endpoint: "https://api .deepseek.com", style: .openAICompatible))
        XCTAssertNil(URLNormalizer.chatURL(endpoint: "https://api.deepseek.com/v1 chat", style: .openAICompatible))
    }

    func testPortAndIPHost() {
        XCTAssertEqual(
            URLNormalizer.chatURL(endpoint: "http://192.168.1.20:8080", style: .openAICompatible)?.absoluteString,
            "http://192.168.1.20:8080/v1/chat/completions"
        )
        XCTAssertEqual(
            URLNormalizer.chatURL(endpoint: "https://api.example.com:8443/v1", style: .anthropic)?.absoluteString,
            "https://api.example.com:8443/v1/messages"
        )
    }

    func testNonASCIIPathPercentEncoded() {
        let url = URLNormalizer.chatURL(endpoint: "https://api.deepseek.com/v1/聊天", style: .openAICompatible)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("%E8%81%8A%E5%A4%A9"))
        XCTAssertTrue(url!.absoluteString.hasSuffix("/chat/completions"))
    }

    // MARK: - OpenAI 兼容请求组装

    func testOpenAIRequestBody() throws {
        let config = EndpointConfig(
            style: .openAICompatible,
            endpoint: "https://api.deepseek.com",
            apiKey: "sk-test",
            model: "deepseek-chat",
            systemPrompt: "你是助手"
        )
        let messages = [
            ChatMessage(role: .user, text: "问题"),
            ChatMessage(role: .assistant, text: "回答"),
            ChatMessage(role: .user, text: "追问"),
        ]
        let request = try StreamingChatClient.buildRequest(config: config, messages: messages)

        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["model"] as? String, "deepseek-chat")
        let msgs = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(msgs.count, 4) // system + 3
        XCTAssertEqual(msgs[0]["role"], "system")
        XCTAssertEqual(msgs[3]["content"], "追问")
    }

    // MARK: - Anthropic 兼容请求组装

    func testAnthropicRequestBody() throws {
        let config = EndpointConfig(
            style: .anthropic,
            endpoint: "https://api.anthropic.com",
            apiKey: "ak-test",
            model: "claude-sonnet-4-5",
            systemPrompt: "你是助手"
        )
        let messages = [
            ChatMessage(role: .user, text: "问题"),
            ChatMessage(role: .assistant, text: "回答"),
            ChatMessage(role: .user, text: "追问"),
        ]
        let request = try StreamingChatClient.buildRequest(config: config, messages: messages)

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "ak-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["system"] as? String, "你是助手")
        XCTAssertEqual(json["max_tokens"] as? Int, 8192)
        let msgs = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(msgs.count, 3) // system 不进 messages
        XCTAssertEqual(msgs[0]["role"], "user")
    }

    // MARK: - 错误体解析

    func testErrorBodyOpenAIShape() {
        let data = Data(#"{"error":{"message":"余额不足","type":"insufficient_quota"}}"#.utf8)
        XCTAssertEqual(ErrorBodyExtractor.message(from: data, fallback: "fb"), "余额不足")
    }

    func testErrorBodyAnthropicShape() {
        let data = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad key"}}"#.utf8)
        XCTAssertEqual(ErrorBodyExtractor.message(from: data, fallback: "fb"), "bad key")
    }

    func testErrorBodyFallback() {
        let data = Data("网关炸了".utf8)
        XCTAssertEqual(ErrorBodyExtractor.message(from: data, fallback: "fb"), "网关炸了")
    }
}
