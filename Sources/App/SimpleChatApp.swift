import SwiftUI

@main
struct SimpleChatApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark) // DeepSeek 风格深色
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: ChatStore
    @State private var path: [UUID] = []
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ConversationListView(path: $path)
                .navigationTitle("SimpleChat")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("出错了", isPresented: .init(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
