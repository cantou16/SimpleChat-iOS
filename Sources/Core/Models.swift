import Foundation

// MARK: - 基础模型（对应 Android 端 db/Entities.kt 的精简子集）

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var role: MessageRole
    var text: String
    /// DeepSeek 风格的思考内容（reasoning_content / thinking），可为空
    var reasoning: String? = nil
    var createdAt: Date = Date()
}

enum ProviderStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// OpenAI 兼容：POST {base}/v1/chat/completions（DeepSeek、自建端点大多走这条）
    case openAICompatible
    /// Anthropic 兼容：POST {base}/v1/messages
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI 兼容 (chat/completions)"
        case .anthropic: return "Anthropic 兼容 (/v1/messages)"
        }
    }
}

struct Conversation: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var title: String
    var providerStyle: ProviderStyle
    var endpoint: String
    var model: String
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
