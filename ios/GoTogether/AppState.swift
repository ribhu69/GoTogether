import Foundation
import Observation

@Observable
final class AppState {
    let api = ApiClient()
    let location = LocationManager()

    // Profile / trust
    var name = ""
    var phone = ""
    var gender: Gender = .female
    var phoneVerified = false
    var idVerified = false
    var idType = "Aadhaar"
    var idLast4 = ""
    var emergencyName = ""
    var emergencyPhone = ""
    var profileImageData: Data?  // persisted profile photo

    /// True once the user explicitly completes all onboarding steps. Persisted.
    var onboardingFinished: Bool = Persistence.onboardingFinished

    /// Quick-start eligibility: previously completed onboarding.
    var hasSavedProfile: Bool {
        Persistence.onboardingComplete && !Persistence.savedName.isEmpty && !Persistence.savedPhone.isEmpty
    }

    // Trip intent
    var myOrigin: Place = Place.defaultOrigin
    var myDest: Place = Place.defaultOrigin  // same as origin until user picks
    var myComfortKm: Double = 5
    var hasDestination = false  // true after user explicitly picks a destination
    var iAmOpen: Bool { hasDestination }  // always Open when you have a destination

    // Search history (latest first)
    var recentSearches: [Place] {
        get { Persistence.recentSearches }
        set { Persistence.recentSearches = newValue }
    }

    // Home address
    var homeAddress: Place? {
        get { Persistence.homeAddress }
        set { Persistence.homeAddress = newValue }
    }

    // Trips
    var search = SearchQuery()
    var activeTrip: Trip?
    var history: [Trip] = []
    var safetyLog: [String] = []

    // Server state
    var serverIntents: [ServerIntent] = []
    var serverCompatible: [ServerIntent] = []
    var serverPending: [ServerMatch] = []

    // Real-time locations of other users (from server polling)
    var peerLocations: [PeerLocation] = []

    // Polling status
    var isRefreshing = false
    var lastRefreshAt: Date?

    // Chat
    var chatMessages: [ChatMessage] = []
    var activeChatPeerId: String = ""
    var lastChatPoll: [String: Double] = [:]   // peerId → last ts polled
    var unreadChats: Set<String> = []           // peerIds with unread messages
    var conversations: [Conversation] = []      // all inbox conversations
    var blockedUserIds: Set<String> = []         // userIds we've blocked
    var unreadCount: Int { unreadChats.count }
    var isLoadingChat = false                    // true while initial chat messages load
    var hasMoreChat = false                      // true when more pages exist
    private let chatPageSize = 20

    // Groups
    var myGroups: [GroupInfo] = []
    var activeGroupId: String = ""
    var groupMessages: [ChatMessage] = []
    var lastGroupPoll: Double = 0
    var isLoadingGroup = false
    var hasMoreGroup = false

    struct GroupInfo: Identifiable {
        let id: String; let name: String
        let memberIds: [String]; let memberNames: [String]
    }

    struct Conversation: Identifiable {
        let id: String          // peerId
        let peerName: String
        let lastText: String
        let lastTs: Double
        var unread: Bool
        var ended: Bool
        var blocked: Bool
    }

    // Server-side status (for diagnostics)
    var serverMe: ServerMeStatus?
    var serverReachable = false
    var isReconnecting = false

    /// True when registered with the server.
    var isConnected: Bool { api.userId != nil }

    // MARK: - Init with persistence

    func loadSavedProfile() {
        name = Persistence.savedName
        phone = Persistence.savedPhone
        gender = Gender(rawValue: Persistence.savedGender) ?? .female
        emergencyName = Persistence.savedEmergencyName
        emergencyPhone = Persistence.savedEmergencyPhone
        phoneVerified = Persistence.savedPhoneVerified
        idVerified = Persistence.savedIdVerified
        idType = Persistence.savedIdType
        idLast4 = Persistence.savedIdLast4
        profileImageData = Persistence.loadProfileImage()
    }

    func saveProfileImage(_ data: Data) {
        profileImageData = data
        Persistence.saveProfileImage(data)
    }

    func clearProfileImage() {
        profileImageData = nil
        Persistence.deleteProfileImage()
    }

    func saveProfile() {
        Persistence.savedName = name
        Persistence.savedPhone = phone
        Persistence.savedGender = gender.rawValue
        Persistence.savedEmergencyName = emergencyName
        Persistence.savedEmergencyPhone = emergencyPhone
        Persistence.savedPhoneVerified = phoneVerified
        Persistence.savedIdVerified = idVerified
        Persistence.savedIdType = idType
        Persistence.savedIdLast4 = idLast4
        Persistence.onboardingComplete = true
        Persistence.onboardingFinished = true
        onboardingFinished = true
    }

    func quickStart() {
        loadSavedProfile()
        Persistence.onboardingFinished = true
        onboardingFinished = true
        if !phone.isEmpty && phoneVerified {
            Task { await registerWithServer() }
        }
    }

    /// Clear all persisted data and return to onboarding.
    func resetProfile() {
        Persistence.onboardingComplete = false
        Persistence.onboardingFinished = false
        Persistence.savedName = ""
        Persistence.savedPhone = ""
        Persistence.savedGender = Gender.female.rawValue
        Persistence.savedEmergencyName = ""
        Persistence.savedEmergencyPhone = ""
        Persistence.savedPhoneVerified = false
        Persistence.savedIdVerified = false
        Persistence.savedIdType = "Aadhaar"
        Persistence.savedIdLast4 = ""
        Persistence.homeAddress = nil
        // In-memory state
        name = ""; phone = ""; gender = .female
        phoneVerified = false; idVerified = false
        idLast4 = ""; emergencyName = ""; emergencyPhone = ""
        onboardingFinished = false
        api.userId = nil
        serverIntents = []; serverCompatible = []; serverPending = []
        peerLocations = []
        profileImageData = nil
        Persistence.deleteProfileImage()
    }

    // ── Origin tracking ──

    func updateOriginFromLocation() {
        if let p = location.place {
            myOrigin = p
        }
    }

    // MARK: - Registration (server)

    func registerWithServer() async {
        guard let u = try? await api.register(
            name: name, phone: phone, gender: gender.rawValue.lowercased(),
            idType: idType, idLast4: idLast4,
            emergencyName: emergencyName, emergencyPhone: emergencyPhone)
        else { return }
        phoneVerified = u.phoneVerified
        idVerified = u.idVerified
    }

    /// Re-sync with the server — no new userId. Server auto-creates users
    /// on intent upsert, so just re-send intent + location.
    func reconnectToServer() {
        guard isConnected, !name.isEmpty else { return }
        isReconnecting = true
        syncIntent()
        syncLocation()
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { isReconnecting = false }
            fetchServerStatus()
        }
    }

    func verifyPhoneOnServer(_ otp: String) async {
        guard let u = try? await api.verifyPhone(otp: otp) else { return }
        phoneVerified = u.phoneVerified
    }

    func verifyIdOnServer(_ last4: String) async {
        guard let u = try? await api.verifyId(idLast4: last4) else { return }
        idVerified = u.idVerified
    }

    // MARK: - Intent sync

    func syncIntent() {
        guard isConnected else { return }
        Task { await _syncIntent() }
    }

    private func _syncIntent() async {
        guard isConnected else { return }
        let compat = (try? await api.upsertIntent(
            origin: myOrigin, dest: myDest, comfortKm: myComfortKm, isOpen: iAmOpen,
            userName: name, userGender: gender.rawValue.lowercased())) ?? []
        await MainActor.run { serverCompatible = compat }
    }

    func syncLocation() {
        guard isConnected else { return }
        Task { await _syncLocation() }
    }

    private func _syncLocation() async {
        guard isConnected else { return }
        let locName = name.isEmpty ? myOrigin.name : name
        _ = try? await api.updateLocation(
            lat: myOrigin.lat, lon: myOrigin.lon, name: locName)
    }

    /// Properly-awaited poll cycle: publish self first, then search others.
    /// Unlike fire-and-forget, this ensures refreshIntents sees freshly posted
    /// location/intent data rather than the previous cycle's stale data,
    /// eliminating the "blip" where peers appear and disappear each cycle.
    func pollCycle() async {
        guard isConnected else { return }
        // 1. Publish our data first (awaited — must land before we search)
        await _syncLocation()
        if hasDestination { await _syncIntent() }
        // 2. Then search for others
        await _pollPending()
        await _refreshIntents()
        await _pollMessagesFromPeers()
    }

    func refreshIntents() {
        guard isConnected else { return }
        Task { await _refreshIntents() }
    }

    private func _refreshIntents() async {
        guard isConnected, hasDestination else {
            await MainActor.run { serverIntents = []; peerLocations = [] }
            return
        }
        await MainActor.run { isRefreshing = true }
        let result = (try? await api.searchIntents(
            origin: myOrigin, dest: myDest, comfortKm: myComfortKm,
            verifiedOnly: search.verifiedOnly, sameGender: search.sameGenderOnly)) ?? SearchResult.empty
        await MainActor.run {
            serverIntents = result.intents
            peerLocations = result.peers
            lastRefreshAt = Date()
            isRefreshing = false
        }
    }

    func pollPending() {
        guard isConnected else { return }
        Task { await _pollPending() }
    }

    private func _pollPending() async {
        let pending = (try? await api.pendingMatches()) ?? []
        await MainActor.run { serverPending = pending }
    }

    // MARK: - Intents (server-only, no mock fallback)

    var openIntents: [TravelIntent] {
        serverIntents.map(api.serverIntentToTravelIntent)
    }

    func matchingOpenIntents() -> [TravelIntent] {
        MatchingEngine.findOpen(
            myOrigin: myOrigin, myDest: myDest, myRadiusKm: myComfortKm,
            intents: openIntents, myGender: gender,
            verifiedOnly: search.verifiedOnly, sameGenderOnly: search.sameGenderOnly
        )
    }

    func matches() -> [Match] {
        // Server-only: no fake riders.
        []
    }

    // MARK: - Trip actions

    func request(_ m: Match) {
        var t = Trip(match: m)
        t.events.append("\(stamp()) Requested share with \(m.rider.name) (\(m.rider.idRef))")
        activeTrip = t
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard activeTrip?.id == t.id else { return }
            activeTrip?.status = .confirmed
            activeTrip?.events.append("\(stamp()) \(m.rider.name) accepted. Cab \(t.cabPlate), PIN \(t.pin)")
        }
    }

    func requestIntent(_ i: TravelIntent) {
        if isConnected, let si = serverIntents.first(where: {
            $0.intentId == i.rider.id.uuidString || $0.userId == i.rider.name || $0.userName == i.rider.name
        }) {
            Task {
                guard let m = try? await api.requestMatch(toIntentId: si.intentId) else { return }
                await MainActor.run {
                    let rider = i.rider
                    let match = Match(rider: rider,
                        destGapKm: m.destGapKm ?? Geo.km(myDest, i.rider.destination),
                        timeGapMin: 0,
                        soloFare: Int(Fare.solo(to: myDest).rounded()),
                        sharedFare: Int(Fare.shared(you: myDest, them: rider.destination).rounded()))
                    request(match)
                }
            }
            return
        }
        // Local fallback
        let m = Match(rider: i.rider,
            destGapKm: Geo.km(myDest, i.rider.destination),
            timeGapMin: 0,
            soloFare: Int(Fare.solo(to: myDest).rounded()),
            sharedFare: Int(Fare.shared(you: myDest, them: i.rider.destination).rounded()))
        request(m)
    }

    func acceptServerMatch(_ sm: ServerMatch) async {
        guard let m = try? await api.respondToMatch(matchId: sm.matchId, accept: true) else { return }
        await MainActor.run {
            let rider = Rider(userId: sm.fromUserId, name: sm.fromUserName, gender: .other, rating: 5, trips: 0,
                idVerified: true, idRef: "", destination: myDest, departAt: Date())
            let match = Match(rider: rider, destGapKm: sm.destGapKm ?? 0, timeGapMin: 0,
                soloFare: Int(Fare.solo(to: myDest).rounded()),
                sharedFare: Int(Fare.shared(you: myDest, them: myDest).rounded()))
            var t = Trip(match: match)
            t.events.append("\(stamp()) Accepted match from \(sm.fromUserName). Cab \(m.cabPlate ?? ""), PIN \(m.pin ?? "")")
            activeTrip = t; activeTrip?.status = .confirmed
        }
    }

    func complete() {
        guard var t = activeTrip else { return }
        t.status = .completed; t.events.append("\(stamp()) Trip completed")
        history.insert(t, at: 0); activeTrip = nil
    }

    func cancel() { activeTrip = nil }

    func raiseSOS() {
        activeTrip?.status = .sos
        let line = "\(stamp()) SOS raised. Live location + trip record sent to \(emergencyName.isEmpty ? "emergency contact" : emergencyName)"
        activeTrip?.events.append(line); safetyLog.insert(line, at: 0)
    }

    func shareText(_ t: Trip) -> String {
        """
        I'm sharing a cab from \(myOrigin.name) to \(myDest.name).
        Trip \(t.id) · Cab \(t.cabPlate) · Driver \(t.driverName)
        Co-rider: \(t.match.rider.name) (\(t.match.rider.idRef))
        """
    }

    private func stamp() -> String { Date().formatted(date: .omitted, time: .shortened) }

    // MARK: - Chat

    func openChat(with peerId: String) {
        ChatMessage.myUserId = api.userId ?? ""
        if activeChatPeerId != peerId {
            chatMessages = []
            // Always reset to load full history, not just messages since last map poll
            lastChatPoll[peerId] = 0
        }
        activeChatPeerId = peerId
        unreadChats.remove(peerId)
        isLoadingChat = true
        fetchChatMessages(for: peerId)
        Task { await fetchBlockedList() }
    }

    func closeChat() {
        activeChatPeerId = ""
    }

    /// Fetch messages from server for a peer. Initial load uses since=0,
    /// incremental polls use since=lastTs. Stops long-poll for initial load
    /// (poll:false) so it returns immediately from file store.
    func fetchChatMessages(for peerId: String) {
        guard isConnected else { return }
        ChatMessage.myUserId = api.userId ?? ""
        let since = lastChatPoll[peerId] ?? 0
        // Initial load: no long-poll, get existing messages immediately
        let isInitialLoad = since == 0
        Task {
            let serverMsgs: [ServerChatMessage] = (try? await api.fetchMessages(
                peerId: peerId, since: since, limit: chatPageSize, poll: !isInitialLoad)) ?? []
            await MainActor.run {
                isLoadingChat = false
                hasMoreChat = serverMsgs.count >= chatPageSize
                guard !serverMsgs.isEmpty else { return }
                for sm in serverMsgs {
                    let msg = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.toUserId,
                                          text: sm.text, ts: sm.ts,
                                          replyToText: sm.replyToText)
                    if !chatMessages.contains(where: { $0.ts == msg.ts && $0.fromUserId == msg.fromUserId }) {
                        chatMessages.append(msg)
                    }
                }
                chatMessages.sort { $0.ts < $1.ts }
                if let latest = serverMsgs.last { lastChatPoll[peerId] = latest.ts }
            }
        }
    }

    /// Load older messages (page before oldest visible).
    func loadOlderMessages() {
        guard isConnected, !activeChatPeerId.isEmpty else { return }
        let peerId = activeChatPeerId
        ChatMessage.myUserId = api.userId ?? ""
        let before = chatMessages.first?.ts ?? Date().timeIntervalSince1970
        Task {
            let serverMsgs: [ServerChatMessage] = (try? await api.fetchMessages(
                peerId: peerId, since: 0, limit: chatPageSize, before: before, poll: false)) ?? []
            await MainActor.run {
                hasMoreChat = serverMsgs.count >= chatPageSize
                guard !serverMsgs.isEmpty else { return }
                for sm in serverMsgs {
                    let msg = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.toUserId,
                                          text: sm.text, ts: sm.ts,
                                          replyToText: sm.replyToText)
                    if !chatMessages.contains(where: { $0.ts == msg.ts && $0.fromUserId == msg.fromUserId }) {
                        chatMessages.append(msg)
                    }
                }
                chatMessages.sort { $0.ts < $1.ts }
            }
        }
    }

    // MARK: - Groups

    func fetchMyGroups() {
        guard isConnected else { return }
        Task {
            let gs = (try? await api.listGroups()) ?? []
            await MainActor.run {
                myGroups = gs.map { g in
                    GroupInfo(id: g.groupId, name: g.name,
                              memberIds: g.memberIds,
                              memberNames: g.members?.map(\.name) ?? g.memberIds.map { $0.prefix(8).description })
                }
            }
        }
    }

    func createGroup(name: String, memberIds: [String]) {
        guard isConnected else { return }
        Task {
            if let g = try? await api.createGroup(name: name, memberIds: memberIds) {
                await MainActor.run { fetchMyGroups(); openGroup(groupId: g.groupId) }
            }
        }
    }

    func openGroup(groupId: String) {
        ChatMessage.myUserId = api.userId ?? ""
        activeGroupId = groupId
        groupMessages = []
        lastGroupPoll = 0
        isLoadingGroup = true
        fetchGroupMessages()
    }

    func closeGroup() { activeGroupId = "" }

    func fetchGroupMessages() {
        guard isConnected, !activeGroupId.isEmpty else { return }
        let gid = activeGroupId
        let since = lastGroupPoll
        let isInitial = since == 0
        Task {
            let msgs = (try? await api.fetchGroupMessages(
                groupId: gid, since: since, limit: chatPageSize, poll: !isInitial)) ?? []
            await MainActor.run {
                isLoadingGroup = false
                hasMoreGroup = msgs.count >= chatPageSize
                guard !msgs.isEmpty else { return }
                for sm in msgs {
                    let msg = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.groupId,
                                          text: sm.text, ts: sm.ts, replyToText: sm.replyToText)
                    if !groupMessages.contains(where: { $0.ts == msg.ts && $0.fromUserId == msg.fromUserId }) {
                        groupMessages.append(msg)
                    }
                }
                groupMessages.sort { $0.ts < $1.ts }
                if let latest = msgs.last { lastGroupPoll = latest.ts }
            }
        }
    }

    func loadOlderGroupMessages() {
        guard isConnected, !activeGroupId.isEmpty else { return }
        let gid = activeGroupId
        let before = groupMessages.first?.ts ?? Date().timeIntervalSince1970
        Task {
            let msgs = (try? await api.fetchGroupMessages(
                groupId: gid, since: 0, limit: chatPageSize, before: before, poll: false)) ?? []
            await MainActor.run {
                hasMoreGroup = msgs.count >= chatPageSize
                guard !msgs.isEmpty else { return }
                for sm in msgs {
                    let msg = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.groupId,
                                          text: sm.text, ts: sm.ts, replyToText: sm.replyToText)
                    if !groupMessages.contains(where: { $0.ts == msg.ts && $0.fromUserId == msg.fromUserId }) {
                        groupMessages.append(msg)
                    }
                }
                groupMessages.sort { $0.ts < $1.ts }
            }
        }
    }

    func sendGroupMessage(_ text: String, replyToText: String? = nil) {
        guard isConnected, !activeGroupId.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let gid = activeGroupId
        ChatMessage.myUserId = api.userId ?? ""
        let myId = api.userId ?? ""
        let now = Date().timeIntervalSince1970
        let local = ChatMessage(fromUserId: myId, toUserId: gid,
                                text: trimmed, ts: now, replyToText: replyToText)
        groupMessages.append(local)
        Task {
            if let sm = try? await api.sendGroupMessage(
                groupId: gid, text: trimmed, replyToText: replyToText) {
                await MainActor.run {
                    groupMessages.removeAll { $0.ts == now && $0.fromUserId == myId }
                    let confirmed = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.groupId,
                                                text: sm.text, ts: sm.ts, replyToText: sm.replyToText)
                    groupMessages.append(confirmed)
                    groupMessages.sort { $0.ts < $1.ts }
                    lastGroupPoll = sm.ts
                }
            }
        }
    }

    func pollGroupInbox() {
        guard isConnected else { return }
        Task {
            let convs = (try? await api.fetchGroupInbox(since: 0, poll: false)) ?? []
            guard !convs.isEmpty else { return }
            await MainActor.run {
                for conv in convs {
                    if lastGroupPoll == 0 { lastGroupPoll = 0 }
                    for sm in conv.messages {
                        let msg = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.groupId,
                                              text: sm.text, ts: sm.ts, replyToText: sm.replyToText)
                        if !groupMessages.contains(where: { $0.ts == msg.ts && $0.fromUserId == msg.fromUserId }) {
                            groupMessages.append(msg)
                        }
                    }
                    if let latest = conv.messages.last {
                        lastGroupPoll = max(lastGroupPoll, latest.ts)
                    }
                }
                groupMessages.sort { $0.ts < $1.ts }
            }
        }
    }

    func sendChatMessage(_ text: String, replyToText: String? = nil) {
        guard isConnected, !activeChatPeerId.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let peerId = activeChatPeerId
        ChatMessage.myUserId = api.userId ?? ""
        let myId = api.userId ?? ""

        let now = Date().timeIntervalSince1970
        let local = ChatMessage(fromUserId: myId, toUserId: peerId,
                                text: trimmed, ts: now, replyToText: replyToText)
        chatMessages.append(local)

        Task {
            if let sm = try? await api.sendMessage(toUserId: peerId, text: trimmed, replyToText: replyToText) {
                await MainActor.run {
                    chatMessages.removeAll { $0.ts == now && $0.fromUserId == myId }
                    let confirmed = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.toUserId,
                                                text: sm.text, ts: sm.ts,
                                                replyToText: sm.replyToText)
                    chatMessages.append(confirmed)
                    chatMessages.sort { $0.ts < $1.ts }
                    lastChatPoll[peerId] = sm.ts
                }
            }
        }
    }

    /// Poll inbox for new messages from all conversations. Called from map loop.
    func pollMessagesFromPeers() {
        guard isConnected else { return }
        Task { await _pollMessagesFromPeers() }
    }

    private func _pollMessagesFromPeers() async {
        guard isConnected else { return }
        ChatMessage.myUserId = api.userId ?? ""
        let inboxConversations = (try? await api.fetchInbox(since: 0, poll: false)) ?? []
        await MainActor.run {
            var updatedConversations: [Conversation] = []
            for conv in inboxConversations {
                let pid = conv.peerId
                if lastChatPoll[pid] == nil { lastChatPoll[pid] = 0 }
                var added = false
                for sm in conv.messages {
                    let msg = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.toUserId,
                                          text: sm.text, ts: sm.ts,
                                          replyToText: sm.replyToText)
                    if !chatMessages.contains(where: { $0.ts == msg.ts && $0.fromUserId == msg.fromUserId }) {
                        chatMessages.append(msg)
                        added = true
                    }
                }
                if added { chatMessages.sort { $0.ts < $1.ts } }
                if let latest = conv.messages.last {
                    lastChatPoll[pid] = max(lastChatPoll[pid]!, latest.ts)
                    let hasFromPeer = conv.messages.contains { $0.fromUserId == pid }
                    if hasFromPeer, pid != activeChatPeerId {
                        unreadChats.insert(pid)
                    }
                }
                let lastMsg = conv.messages.last
                updatedConversations.append(Conversation(
                    id: pid,
                    peerName: conv.peerName,
                    lastText: lastMsg?.text ?? "",
                    lastTs: lastMsg?.ts ?? 0,
                    unread: unreadChats.contains(pid),
                    ended: conv.ended ?? false,
                    blocked: conv.blocked ?? false))
            }
            self.conversations = updatedConversations
        }
    }

    // MARK: - Block / end-chat

    func blockUser(_ peerId: String) {
        guard isConnected else { return }
        blockedUserIds.insert(peerId)
        Task { _ = try? await api.blockUser(targetUserId: peerId) }
    }

    func unblockUser(_ peerId: String) {
        guard isConnected else { return }
        blockedUserIds.remove(peerId)
        Task { _ = try? await api.unblockUser(targetUserId: peerId) }
    }

    func endChat(with peerId: String) {
        guard isConnected else { return }
        Task { _ = try? await api.endChat(peerId: peerId) }
    }

    func fetchBlockedList() async {
        guard isConnected else { return }
        if let ids = try? await api.fetchBlocked() {
            await MainActor.run { blockedUserIds = Set(ids) }
        }
    }

    func isConversationEnded(_ peerId: String) -> Bool {
        conversations.first(where: { $0.id == peerId })?.ended ?? false
    }

    func isPeerBlocked(_ peerId: String) -> Bool {
        conversations.first(where: { $0.id == peerId })?.blocked ?? false || blockedUserIds.contains(peerId)
    }

    func addRecentSearch(_ place: Place) {
        var list = recentSearches
        // Remove duplicate if exists
        list.removeAll { $0.name == place.name && abs($0.lat - place.lat) < 0.0001 && abs($0.lon - place.lon) < 0.0001 }
        // Prepend (latest first)
        list.insert(place, at: 0)
        // Cap at 10
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentSearches = list
    }

    // MARK: - Server status

    func fetchServerStatus() {
        guard isConnected else {
            serverReachable = false; serverMe = nil; return
        }
        Task {
            if let me = try? await api.fetchMe() {
                await MainActor.run {
                    serverMe = me
                    serverReachable = true
                }
            } else {
                await MainActor.run { serverReachable = false }
            }
        }
    }
}