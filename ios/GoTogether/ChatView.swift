import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var showBlockConfirm = false
    @State private var showEndConfirm = false
    @State private var replyTarget: ChatMessage?  // message being replied to

    /// Messages filtered to the active chat peer only.
    var peerMessages: [ChatMessage] {
        let peerId = app.activeChatPeerId
        let myId = ChatMessage.myUserId
        return app.chatMessages.filter {
            ($0.fromUserId == myId && $0.toUserId == peerId) ||
            ($0.fromUserId == peerId && $0.toUserId == myId)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        if app.hasMoreChat {
                            Button {
                                app.loadOlderMessages()
                            } label: {
                                Label("Load older messages", systemImage: "arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .padding(.vertical, 4)
                        }

                        LazyVStack(spacing: 6) {
                            ForEach(peerMessages) { msg in
                                ChatBubble(msg: msg)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button { replyTarget = msg; focused = true } label: {
                                            Label("Reply", systemImage: "arrow.turn.down.left")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: peerMessages.count) { _, _ in
                        if let last = peerMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if app.isLoadingChat {
                    ProgressView("Loading messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                }
            }
            .background(Color(.systemGroupedBackground))

            // Reply preview bar
            if let target = replyTarget {
                HStack(spacing: 8) {
                    Rectangle().fill(.blue).frame(width: 3, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.isFromMe ? "Replying to yourself" : "Replying")
                            .font(.caption2.weight(.medium)).foregroundStyle(.blue)
                        Text(target.text)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { replyTarget = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.regularMaterial)
            }

            // Input bar
            if app.isConversationEnded(app.activeChatPeerId) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Conversation ended")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            } else if app.isPeerBlocked(app.activeChatPeerId) {
                HStack(spacing: 12) {
                    Image(systemName: "nosign").foregroundStyle(.red)
                    Text("User blocked").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Unblock") { app.unblockUser(app.activeChatPeerId) }
                        .buttonStyle(.bordered).controlSize(.small).tint(.blue)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            } else {
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
        }
        .adaptiveWidth()
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if app.isPeerBlocked(app.activeChatPeerId) {
                        Button { app.unblockUser(app.activeChatPeerId) } label: {
                            Label("Unblock User", systemImage: "hand.raised.slash.fill")
                        }
                    } else {
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label("Block User", systemImage: "hand.raised.slash")
                        }
                    }
                    if !app.isConversationEnded(app.activeChatPeerId) {
                        Button { showEndConfirm = true } label: {
                            Label("End Conversation", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Block this user?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) { app.blockUser(app.activeChatPeerId) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to see you on the map or send you messages.")
        }
        .confirmationDialog("End this conversation?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End", role: .destructive) { app.endChat(with: app.activeChatPeerId) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't be able to exchange messages after ending.")
        }
        .onAppear {
            // Delay focus until the sheet animation completes,
            // otherwise the keyboard won't pop up reliably.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focused = true
            }
        }
        .task {
            app.fetchChatMessages(for: app.activeChatPeerId)
            while !Task.isCancelled {
                app.fetchChatMessages(for: app.activeChatPeerId)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        app.sendChatMessage(text, replyToText: replyTarget?.text)
        draft = ""
        replyTarget = nil
    }
}

// MARK: - Bubble

struct ChatBubble: View {
    @Environment(AppState.self) private var app
    let msg: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if msg.isFromMe {
                Spacer(minLength: 48)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable().frame(width: 28, height: 28)
                    .foregroundStyle(.green)
                    .clipShape(Circle())
            }

            VStack(alignment: msg.isFromMe ? .trailing : .leading, spacing: 2) {
                // Quoted reply preview
                if let reply = msg.replyToText {
                    HStack(spacing: 4) {
                        Rectangle().fill(msg.isFromMe ? .white.opacity(0.5) : .blue)
                            .frame(width: 2, height: 28)
                        Text(reply)
                            .font(.caption2)
                            .foregroundStyle(msg.isFromMe ? .white.opacity(0.8) : .secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8).padding(.top, 6)
                }

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

            if msg.isFromMe {
                ProfileImageView(imageData: app.profileImageData,
                                 size: 28, fallbackIcon: "person.circle.fill",
                                 fallbackColor: .blue, showBorder: false)
            } else {
                Spacer(minLength: 48)
            }
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