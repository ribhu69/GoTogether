import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var pollTimer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(app.chatMessages) { msg in
                            ChatBubble(msg: msg)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: app.chatMessages.count) { _, _ in
                    if let last = app.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))

            // Input bar
            HStack(spacing: 8) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                    .focused($focused)
                    .onSubmit { send() }
                    .lineLimit(1...4)

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .adaptiveWidth()
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Poll messages every 2 seconds while this view is visible
            pollTimer = Task {
                while !Task.isCancelled {
                    app.pollChat()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        .onDisappear {
            pollTimer?.cancel()
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        app.sendChatMessage(text)
        draft = ""
    }
}

// MARK: - Bubble

struct ChatBubble: View {
    let msg: ChatMessage

    var body: some View {
        HStack(spacing: 6) {
            if msg.isFromMe { Spacer(minLength: 48) }

            VStack(alignment: msg.isFromMe ? .trailing : .leading, spacing: 2) {
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(msg.isFromMe ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        msg.isFromMe ? Color.blue : Color(.systemGray5),
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                Text(formatTs(msg.ts))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !msg.isFromMe { Spacer(minLength: 48) }
        }
    }

    private func formatTs(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Peer chat wrapper

struct PeerChatSheet: View {
    @Environment(AppState.self) private var app
    let peer: PeerLocation

    var body: some View {
        NavigationStack {
            ChatView()
        }
        .onAppear { app.openChat(with: peer.id) }
        .onDisappear { app.closeChat() }
    }
}