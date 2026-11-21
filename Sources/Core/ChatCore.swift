import Foundation

// MARK: - 错误类型

enum ChatError: LocalizedError, Sendable {
    case badURL
    case badResponse
    case http(Int, String)
    case api(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "端点 URL 无法解析，请检查设置里的地址"
        case .badResponse: return "服务端响应不是 HTTP（代理或网关异常？）"
        case .http(let code, let message): return "HTTP \(code)：\(message)"
        case .api(let message): return message
        case .network(let message): return "网络错误：\(message)"
        }
    }
}

// MARK: - 流事件

enum ChatEvent: Sendable, Equatable {
    case textDelta(String)
    case reasoningDelta(String)
    case finished
}

// MARK: - 端点配置

struct EndpointConfig: Sendable {
    var style: ProviderStyle
    /// 用户填写的 base，如 https://api.deepseek.com 或完整 URL
    var endpoint: String
    var apiKey: String
    var model: String
    var systemPrompt: String?
}

// MARK: - URL 归一化（对齐 Android 端 Provider.kt 的拼接规则）

enum URLNormalizer {
    static func chatURL(endpoint: String, style: ProviderStyle) -> URL? {
        var trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://") else { return nil }

        switch style {
        case .openAICompatible:
            if trimmed.hasSuffix("/chat/completions") { return URL(string: trimmed) }
            if trimmed.hasSuffix("/v1") || trimmed.hasSuffix("/v1beta") {
                return URL(string: trimmed + "/chat/completions")
            }
            return URL(string: trimmed + "/v1/chat/completions")
        case .anthropic:
            if trimmed.hasSuffix("/messages") { return URL(string: trimmed) }
            if trimmed.hasSuffix("/v1") { return URL(string: trimmed + "/messages") }
            return URL(string: trimmed + "/v1/messages")
        }
    }
}

// MARK: - 错误体启发式解析（OpenAI 与 Anthropic 两种形状都试）

enum ErrorBodyExtractor {
    static func message(from data: Data, fallback: String) -> String {
        struct OpenAIShape: Decodable {
            struct E: Decodable { var message: String? }
            var error: E?
        }
        struct AnthropicShape: Decodable {
            struct E: Decodable { var message: String? }
            var type: String?
            var error: E?
        }
        if let shape = try? JSONDecoder().decode(OpenAIShape.self, from: data),
           let m = shape.error?.message, !m.isEmpty {
            return m
        }
        if let shape = try? JSONDecoder().decode(AnthropicShape.self, from: data),
           shape.type == "error", let m = shape.error?.message, !m.isEmpty {
            return m
        }
        let raw = String(decoding: data.prefix(300), as: UTF8.self)
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }
}
