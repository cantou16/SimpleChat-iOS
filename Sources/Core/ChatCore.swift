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
        case .badURL: return "端点 URL 无法解析：必须是 http(s):// + 纯英文域名，不能含空格或中文/emoji"
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
        // 内部空白/控制字符一律拒绝（URLSession 的转义路径对脏输入不可靠）
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              // host 必须纯 ASCII（中文/emoji 域名走 CFNetwork 转义路径有已知崩溃面）
              host.allSatisfy({ $0.isASCII })
        else { return nil }

        var path = components.path
        switch style {
        case .openAICompatible:
            if !path.hasSuffix("/chat/completions") {
                if path.hasSuffix("/v1") || path.hasSuffix("/v1beta") {
                    path += "/chat/completions"
                } else {
                    path += "/v1/chat/completions"
                }
            }
        case .anthropic:
            if !path.hasSuffix("/messages") {
                if path.hasSuffix("/v1") {
                    path += "/messages"
                } else {
                    path += "/v1/messages"
                }
            }
        }
        components.path = path
        return components.url
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
