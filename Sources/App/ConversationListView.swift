import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var store: ChatStore
    @Binding var path: [UUID]

    var body: some View {
        Group {
            if store.conversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("SimpleChat").font(.title2).bold()
                    Text("和 AI 聊点什么。\n先到设置里配好 API 端点。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                List {
                    ForEach(store.conversations) { conv in
                        NavigationLink(value: conv.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conv.title).lineLimit(1)
                                Text("\(conv.model) · \(conv.messages.count) 条消息")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { store.deleteConversation(at: $0) }
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            ChatView(conversationID: id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let c = store.createConversation()
                    path.append(c.id)
                } label: { Image(systemName: "plus.message") }
            }
        }
    }
}

extension ChatStore {
    func deleteConversation(at offsets: IndexSet) {
        let ids = conversations.enumerated().filter { offsets.contains($0.offset) }.map { $0.element.id }
        ids.forEach { deleteConversation($0) }
    }
}

// MARK: - 对话页

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    let conversationID: UUID

    @State private var input = ""
    @State private var scrollTick = UUID()

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .navigationTitle(store.conversation(conversationID)?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    let messages = store.conversation(conversationID)?.messages ?? []
                    ForEach(messages) { m in
                        MessageBubble(message: m, streaming: store.streamingConversationID == conversationID && m.role == .assistant && isLast(m, in: messages))
                            .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .onChange(of: scrollTick) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: store.conversation(conversationID)?.messages.last?.text) { _ in
                scrollTick = UUID()
            }
            .onChange(of: store.conversation(conversationID)?.messages.last?.reasoning) { _ in
                scrollTick = UUID()
            }
        }
    }

    private func isLast(_ m: ChatMessage, in messages: [ChatMessage]) -> Bool {
        messages.last?.id == m.id
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("发消息…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            if store.streamingConversationID == conversationID {
                Button { store.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func send() {
        let text = input
        input = ""
        store.send(in: conversationID, input: text)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let streaming: Bool
    @State private var showReasoning = false

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    DisclosureGroup(isPresented: $showReasoning) {
                        ScrollView {
                            Text(reasoning)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                    } label: {
                        Label("思考过程", systemImage: "brain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                } else if streaming {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
