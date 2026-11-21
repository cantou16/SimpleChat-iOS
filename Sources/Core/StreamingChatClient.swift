import Foundation

// MARK: - SSE 增量解析器（纯逻辑，可单测；对齐 Android 端 SseLineParser.kt 的职责）
//
// 同时吃两种协议的 data 载荷，按 JSON 形状自动分派：
// - OpenAI 兼容：{choices:[{delta:{content?,reasoning_content?},finish_reason?}]}，终止符 data: [DONE]
// - Anthropic：{type:"content_block_delta",delta:{type:"text_delta"|"thinking_delta",...}}
//              以及 {type:"error",error:{message}}

struct SSEDeltaParser {
    /// 吃一行 SSE，返回该行产生的增量事件；`data:` 载荷自描述，无需依赖 event: 帧
    mutating func feed(line: String) throws -> [ChatEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return [] }
        if payload == "[DONE]" { return [.finished] }

        guard let data = payload.data(using: .utf8) else { return [] }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let obj = json else { return [] }

        // Anthropic 错误事件 → 抛出
        if obj["type"] as? String == "error",
           let error = obj["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ChatError.api(message)
        }

        // OpenAI 形状
        if let choices = obj["choices"] as? [[String: Any]],
           let choice = choices.first {
            var events: [ChatEvent] = []
            if let delta = choice["delta"] as? [String: Any] {
                if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                    events.append(.reasoningDelta(reasoning))
                }
                if let text = delta["content"] as? String, !text.isEmpty {
                    events.append(.textDelta(text))
                }
            }
            if choice["finish_reason"] != nil {
                events.append(.finished)
            }
            return events
        }

        // Anthropic 形状
        switch obj["type"] as? String {
        case "content_block_delta":
            guard let delta = obj["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                if let text = delta["text"] as? String, !text.isEmpty {
                    return [.textDelta(text)]
                }
            case "thinking_delta":
                if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                    return [.reasoningDelta(thinking)]
                }
            default:
                break
            }
            return []
        case "message_stop":
            return [.finished]
        default:
            return [] // ping / message_start / content_block_start|stop / message_delta(usage) 等
        }
    }
}

// MARK: - 流式客户端（URLSession + AsyncLines，对应 Android 端 SseClient.kt + OkHttp）

final class StreamingChatClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 600
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// 发起流式对话请求，返回增量事件流
    func stream(config: EndpointConfig, messages: [ChatMessage]) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.buildRequest(config: config, messages: messages)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ChatError.badResponse }

                    if http.statusCode != 200 {
                        var body = Data()
                        for try await b in bytes { body.append(b); if body.count > 64 * 1024 { break } }
                        let message = ErrorBodyExtractor.message(
                            from: body,
                            fallback: "HTTP \(http.statusCode)"
                        )
                        throw ChatError.http(http.statusCode, message)
                    }

                    var parser = SSEDeltaParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        for event in try parser.feed(line: line) {
                            if case .finished = event {
                                continuation.finish()
                                return
                            }
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if error is ChatError {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish(throwing: ChatError.network(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 请求组装（对齐 Android 端 ChatApi.kt / AnthropicRequestBuilder.kt 的双通道）

    static func buildRequest(config: EndpointConfig, messages: [ChatMessage]) throws -> URLRequest {
        guard let url = URLNormalizer.chatURL(endpoint: config.endpoint, style: config.style) else {
            throw ChatError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["stream": true]

        switch config.style {
        case .openAICompatible:
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            var payload: [[String: String]] = []
            if let system = config.systemPrompt, !system.isEmpty {
                payload.append(["role": "system", "content": system])
            }
            for m in messages where m.role != .system {
                payload.append(["role": m.role.rawValue, "content": m.text])
            }
            body["messages"] = payload
            body["model"] = config.model

        case .anthropic:
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let system = config.systemPrompt, !system.isEmpty {
                body["system"] = system
            }
            body["messages"] = messages
                .filter { $0.role != .system }
                .map { ["role": $0.role.rawValue, "content": $0.text] }
            body["model"] = config.model
            body["max_tokens"] = 8192
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
