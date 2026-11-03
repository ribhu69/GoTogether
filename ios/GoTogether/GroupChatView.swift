import SwiftUI

struct GroupChatView: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var replyTarget: ChatMessage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        if app.hasMoreGroup {
                            Button { app.loadOlderGroupMessages() } label: {
                                Label("Load older messages", systemImage: "arrow.up").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small).padding(.vertical, 4)
                        }
                        LazyVStack(spacing: 6) {
                            ForEach(app.groupMessages) { msg in
                                GroupBubble(msg: msg)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button { replyTarget = msg; focused = true } label: {
                                            Label("Reply", systemImage: "arrow.turn.down.left")
                                        }.tint(.blue)
                                    }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .onChange(of: app.groupMessages.count) { _, _ in
                        if let last = app.groupMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                if app.isLoadingGroup {
                    ProgressView("Loading messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                }
            }
            .background(Color(.systemGroupedBackground))

            // Reply preview
            if let target = replyTarget {
                HStack(spacing: 8) {
                    Rectangle().fill(.blue).frame(width: 3, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.isFromMe ? "Replying to yourself" : "Replying to \(senderName(for: target.fromUserId))")
                            .font(.caption2.weight(.medium)).foregroundStyle(.blue)
                        Text(target.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { replyTarget = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6).background(.regularMaterial)
            }

            // Input
            HStack(spacing: 8) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                    .focused($focused).onSubmit { send() }.lineLimit(1...4)
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2).symbolRenderingMode(.hierarchical)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 8).background(.regularMaterial)
        }
        .adaptiveWidth()
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
        }
        .task {
            app.fetchGroupMessages()
            while !Task.isCancelled {
                app.fetchGroupMessages()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var groupName: String {
        app.myGroups.first(where: { $0.id == app.activeGroupId })?.name ?? "Group"
    }

    private func senderName(for userId: String) -> String {
        if userId == ChatMessage.myUserId { return "you" }
        return app.myGroups.first(where: { $0.id == app.activeGroupId })?
            .memberNames[app.myGroups.first(where: { $0.id == app.activeGroupId })?
            .memberIds.firstIndex(of: userId) ?? 0] ?? userId.prefix(8).description
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        app.sendGroupMessage(text, replyToText: replyTarget?.text)
        draft = ""
        replyTarget = nil
    }
}

// MARK: - Group bubble

struct GroupBubble: View {
    @Environment(AppState.self) private var app
    let msg: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if msg.isFromMe { Spacer(minLength: 48) }
            else {
                Image(systemName: "person.circle.fill")
                    .resizable().frame(width: 28, height: 28)
                    .foregroundStyle(.green).clipShape(Circle())
            }

            VStack(alignment: msg.isFromMe ? .trailing : .leading, spacing: 2) {
                // Sender name for others' messages
                if !msg.isFromMe {
                    Text(senderName(for: msg.fromUserId))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 4)
                }
                // Reply quote
                if let reply = msg.replyToText {
                    HStack(spacing: 4) {
                        Rectangle().fill(msg.isFromMe ? .white.opacity(0.5) : .blue)
                            .frame(width: 2, height: 28)
                        Text(reply).font(.caption2)
                            .foregroundStyle(msg.isFromMe ? .white.opacity(0.8) : .secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8).padding(.top, 6)
                }
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(msg.isFromMe ? .white : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(msg.isFromMe ? Color.blue : Color(.systemGray5),
                                in: RoundedRectangle(cornerRadius: 16))
                Text(formatTs(msg.ts))
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 4)
            }

            if msg.isFromMe {
                ProfileImageView(imageData: app.profileImageData, size: 28,
                                 fallbackIcon: "person.circle.fill", fallbackColor: .blue, showBorder: false)
            } else {
                Spacer(minLength: 48)
            }
        }
    }

    private func senderName(for userId: String) -> String {
        let g = app.myGroups.first(where: { $0.id == app.activeGroupId })
        if let idx = g?.memberIds.firstIndex(of: userId), let names = g?.memberNames {
            return idx < names.count ? names[idx] : userId.prefix(8).description
        }
        return userId.prefix(8).description
    }

    private func formatTs(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}