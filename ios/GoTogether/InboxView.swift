import SwiftUI

/// A scrollable list of all conversations with unread indicators and tap-to-open.
struct InboxView: View {
    @Environment(AppState.self) private var app
    @State private var selectedPeer: PeerLocation?
    @State private var showGroupChat = false

    var body: some View {
        NavigationStack {
            List {
                // Groups
                if !app.myGroups.isEmpty {
                    Section("Groups") {
                        ForEach(app.myGroups) { group in
                            NavigationLink {
                                GroupChatView()
                                    .onAppear { app.openGroup(groupId: group.id) }
                                    .onDisappear { app.closeGroup() }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.3.fill")
                                        .font(.title3).foregroundStyle(.blue)
                                        .frame(width: 36, height: 36)
                                        .background(.blue.opacity(0.1), in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.name).font(.headline)
                                        Text(group.memberNames.joined(separator: ", "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }

                // 1:1 conversations
                if app.conversations.isEmpty && app.myGroups.isEmpty {
                    ContentUnavailableView(
                        "No messages yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("When you chat with a co-rider, your conversations will appear here.")
                    )
                } else if !app.conversations.isEmpty {
                    Section("Direct Messages") {
                        conversationRows
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Messages")
            .sheet(item: $selectedPeer) { peer in PeerChatSheet(peer: peer) }
        }
        .onAppear { app.fetchMyGroups() }
    }

    @ViewBuilder
    private var conversationRows: some View {
        ForEach(app.conversations.sorted(by: { $0.lastTs > $1.lastTs })) { conv in
            Button {
                let peer = PeerLocation(id: conv.id, name: conv.peerName,
                    coord: app.myOrigin.coord, destination: nil)
                selectedPeer = peer
            } label: {
                conversationRow(conv)
            }
            .buttonStyle(.plain)
        }
    }

    private func conversationRow(_ conv: AppState.Conversation) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: conv.blocked ? "person.circle.fill" : "person.circle.fill")
                    .font(.title)
                    .foregroundStyle(conv.blocked ? .gray : conv.ended ? .orange : .green)
                if conv.unread {
                    Circle().fill(.red).frame(width: 8, height: 8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(conv.peerName).font(.headline).foregroundStyle(.primary)
                    if conv.ended {
                        Text("Ended").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
                    }
                    if conv.blocked {
                        Text("Blocked").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.red.opacity(0.15), in: Capsule()).foregroundStyle(.red)
                    }
                }
                Text(conv.lastText.isEmpty ? "No messages" : conv.lastText)
                    .font(.subheadline)
                    .foregroundStyle(conv.unread ? .primary : .secondary).lineLimit(1)
            }
            Spacer()
            Text(formatTs(conv.lastTs)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func formatTs(_ ts: Double) -> String {
        guard ts > 0 else { return "" }
        let diff = Date().timeIntervalSince(Date(timeIntervalSince1970: ts))
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        let f = DateFormatter(); f.dateFormat = diff < 86400 ? "HH:mm" : "MM/dd"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}