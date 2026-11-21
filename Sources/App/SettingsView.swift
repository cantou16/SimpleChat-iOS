import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var endpoint: String = ""
    @State private var style: ProviderStyle = .openAICompatible
    @State private var model: String = ""
    @State private var draftKey: String = ""
    @State private var systemPrompt: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("API 端点") {
                    TextField("https://api.deepseek.com", text: $endpoint)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Picker("协议", selection: $style) {
                        ForEach(ProviderStyle.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    TextField("模型（如 deepseek-chat）", text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API Key", text: $draftKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("系统提示词") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 80)
                }
                Section {
                    Button("保存") { save() }
                }
                Section("关于") {
                    LabeledContent("版本", value: "0.1.0 (iOS 移植)")
                    Text("基于 Pokanshuu/Simple-Chat (MIT) 的 iOS 原生移植。功能子集：双协议流式对话、思考链展示、Keychain 加密存 Key。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        let s = store.settings
        endpoint = s.endpoint
        style = s.style
        model = s.model
        systemPrompt = s.systemPrompt
        draftKey = store.currentAPIKey()
    }

    private func save() {
        var s = store.settings
        s.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        s.style = style
        s.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        s.systemPrompt = systemPrompt
        store.settings = s
        store.storeAPIKey(draftKey.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
