import Foundation
import Combine

// MARK: - 持久化状态（JSON 落盘；API Key 经 KeychainSecretBox 加密后一起入库）

struct AppSettings: Codable, Sendable {
    var endpoint: String = "https://api.deepseek.com"
    var style: ProviderStyle = .openAICompatible
    var model: String = "deepseek-chat"
    var systemPrompt: String = ""
    /// KeychainSecretBox 加密后的 API Key（base64 AES-GCM 密文）
    var encryptedAPIKey: String = ""
}

struct PersistedState: Codable, Sendable {
    var settings: AppSettings = AppSettings()
    var conversations: [Conversation] = []
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var state: PersistedState
    @Published var streamingConversationID: UUID?
    @Published var lastError: String?

    private let client = StreamingChatClient()
    private var streamTask: Task<Void, Never>?
    private let fileURL: URL

    var settings: AppSettings {
        get { state.settings }
        set {
            state.settings = newValue
            save()
        }
    }

    var conversations: [Conversation] {
        state.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    init(fileURL: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? docs.appendingPathComponent("simplechat_state.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            state = decoded
        } else {
            state = PersistedState()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - 会话管理

    func createConversation() -> Conversation {
        let c = Conversation(
            title: "新对话",
            providerStyle: state.settings.style,
            endpoint: state.settings.endpoint,
            model: state.settings.model
        )
        state.conversations.append(c)
        save()
        return c
    }

    func deleteConversation(_ id: UUID) {
        state.conversations.removeAll { $0.id == id }
        save()
    }

    func conversation(_ id: UUID) -> Conversation? {
        state.conversations.first { $0.id == id }
    }

    func update(conversation: Conversation) {
        guard let idx = state.conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        var c = conversation
        c.updatedAt = Date()
        state.conversations[idx] = c
        save()
    }

    // MARK: - API Key

    func storeAPIKey(_ key: String) {
        var s = state.settings
        if key.isEmpty {
            s.encryptedAPIKey = ""
        } else if let encrypted = try? KeychainSecretBox.encrypt(key) {
            s.encryptedAPIKey = encrypted
        }
        state.settings = s
        save()
    }

    func currentAPIKey() -> String {
        guard !state.settings.encryptedAPIKey.isEmpty,
              let plain = try? KeychainSecretBox.decrypt(state.settings.encryptedAPIKey) else { return "" }
        return plain
    }

    // MARK: - 发送 / 停止

    func send(in conversationID: UUID, input: String) {
        guard var conv = conversation(conversationID) else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        conv.messages.append(ChatMessage(role: .user, text: text))
        let assistant = ChatMessage(role: .assistant, text: "")
        conv.messages.append(assistant)
        update(conversation: conv)

        let config = EndpointConfig(
            style: state.settings.style,
            endpoint: state.settings.endpoint,
            apiKey: currentAPIKey(),
            model: state.settings.model,
            systemPrompt: state.settings.systemPrompt.isEmpty ? nil : state.settings.systemPrompt
        )

        streamingConversationID = conversationID
        lastError = nil

        let assistantID = assistant.id
        streamTask = Task { [weak self] in
            guard let self else { return }
            let history = self.conversation(conversationID)?.messages.dropLast().map { $0 } ?? []
            let events = self.client.stream(config: config, messages: history)

            for try await event in events {
                self.apply(event: event, conversationID: conversationID, assistantID: assistantID)
            }
            self.finishStreaming(conversationID: conversationID, assistantID: assistantID)
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        streamingConversationID = nil
    }

    private func apply(event: ChatEvent, conversationID: UUID, assistantID: UUID) {
        guard var conv = conversation(conversationID),
              let idx = conv.messages.firstIndex(where: { $0.id == assistantID }) else { return }
        switch event {
        case .textDelta(let delta):
            conv.messages[idx].text += delta
        case .reasoningDelta(let delta):
            let r = conv.messages[idx].reasoning ?? ""
            conv.messages[idx].reasoning = r + delta
        case .finished:
            break
        }
        update(conversation: conv)
    }

    private func finishStreaming(conversationID: UUID, assistantID: UUID) {
        streamingConversationID = nil
        streamTask = nil
        guard var conv = conversation(conversationID) else { return }
        // 空回复占位提示；首条用户消息自动做标题（对齐 Android 端 ConversationTitle.kt 的简化版）
        if let idx = conv.messages.firstIndex(where: { $0.id == assistantID }),
           conv.messages[idx].text.isEmpty, (conv.messages[idx].reasoning ?? "").isEmpty {
            conv.messages[idx].text = "（无回复内容，可重试）"
        }
        if conv.title == "新对话",
           let firstUser = conv.messages.first(where: { $0.role == .user }) {
            conv.title = String(firstUser.text.prefix(24))
        }
        update(conversation: conv)
    }
}

