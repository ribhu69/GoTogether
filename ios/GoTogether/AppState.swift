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

    /// Re-register with the server using the current profile (for reconnect).
    /// Resyncs intent + location after successful registration.
    func reconnectToServer() {
        guard !name.isEmpty, !phone.isEmpty else { return }
        isReconnecting = true
        Task {
            guard let u = try? await api.register(
                name: name, phone: phone, gender: gender.rawValue.lowercased(),
                idType: idType, idLast4: idLast4,
                emergencyName: emergencyName, emergencyPhone: emergencyPhone)
            else {
                await MainActor.run {
                    serverReachable = false
                    isReconnecting = false
                }
                return
            }
            await MainActor.run {
                phoneVerified = u.phoneVerified
                idVerified = u.idVerified
                serverReachable = true
                isReconnecting = false
            }
            if hasDestination { syncIntent() }
            syncLocation()
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
        Task {
            let compat = (try? await api.upsertIntent(
                origin: myOrigin, dest: myDest, comfortKm: myComfortKm, isOpen: iAmOpen,
                userName: name, userGender: gender.rawValue.lowercased())) ?? []
            await MainActor.run { serverCompatible = compat }
        }
    }

    func syncLocation() {
        guard isConnected else { return }
        Task {
            _ = try? await api.updateLocation(
                lat: myOrigin.lat, lon: myOrigin.lon, name: myOrigin.name)
        }
    }

    func refreshIntents() {
        guard isConnected, hasDestination else {
            Task { @MainActor in
                serverIntents = []; peerLocations = []
            }
            return
        }
        Task {
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
    }

    func pollPending() {
        guard isConnected else { return }
        Task {
            let pending = (try? await api.pendingMatches()) ?? []
            await MainActor.run { serverPending = pending }
        }
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
        // Clear only when switching to a different peer
        if activeChatPeerId != peerId { chatMessages = [] }
        activeChatPeerId = peerId
        unreadChats.remove(peerId)
        if lastChatPoll[peerId] == nil { lastChatPoll[peerId] = 0 }
        fetchChatMessages(for: peerId)
    }

    func closeChat() {
        activeChatPeerId = ""
    }

    /// Fetch messages from server for a peer. Appends new ones, skips duplicates.
    func fetchChatMessages(for peerId: String) {
        guard isConnected else { return }
        ChatMessage.myUserId = api.userId ?? ""
        let since = lastChatPoll[peerId] ?? 0
        Task {
            let serverMsgs: [ServerChatMessage] = (try? await api.fetchMessages(
                peerId: peerId, since: since)) ?? []
            guard !serverMsgs.isEmpty else { return }
            await MainActor.run {
                for sm in serverMsgs {
                    let msg = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.toUserId,
                                          text: sm.text, ts: sm.ts)
                    if !chatMessages.contains(where: { $0.ts == msg.ts && $0.fromUserId == msg.fromUserId }) {
                        chatMessages.append(msg)
                    }
                }
                chatMessages.sort { $0.ts < $1.ts }
                if let latest = serverMsgs.last { lastChatPoll[peerId] = latest.ts }
            }
        }
    }

    func sendChatMessage(_ text: String) {
        guard isConnected, !activeChatPeerId.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let peerId = activeChatPeerId
        ChatMessage.myUserId = api.userId ?? ""
        let myId = api.userId ?? ""

        // 1. Show locally immediately (optimistic)
        let now = Date().timeIntervalSince1970
        let local = ChatMessage(fromUserId: myId, toUserId: peerId, text: trimmed, ts: now)
        chatMessages.append(local)

        // 2. Send to server in background; update with real ts on success
        Task {
            if let sm = try? await api.sendMessage(toUserId: peerId, text: trimmed) {
                await MainActor.run {
                    // Replace local with server-confirmed (real ts)
                    chatMessages.removeAll { $0.ts == now && $0.fromUserId == myId }
                    let confirmed = ChatMessage(fromUserId: sm.fromUserId, toUserId: sm.toUserId,
                                                text: sm.text, ts: sm.ts)
                    chatMessages.append(confirmed)
                    chatMessages.sort { $0.ts < $1.ts }
                    lastChatPoll[peerId] = sm.ts
                }
            }
        }
    }

    /// Poll every visible peer for new messages. Called from the main map loop.
    func pollMessagesFromPeers() {
        guard isConnected else { return }
        ChatMessage.myUserId = api.userId ?? ""
        for peer in peerLocations {
            let pid = peer.id
            // Skip the currently open chat (pollChat handles it)
            if pid == activeChatPeerId { continue }
            let since = lastChatPoll[pid] ?? 0
            Task {
                let msgs: [ServerChatMessage] = (try? await api.fetchMessages(
                    peerId: pid, since: since)) ?? []
                guard !msgs.isEmpty else { return }
                await MainActor.run {
                    // Init lastChatPoll if this is the first message from this peer
                    if lastChatPoll[pid] == nil { lastChatPoll[pid] = 0 }
                    if let latest = msgs.last { lastChatPoll[pid] = latest.ts }
                    // Any message FROM this peer (not from me) = unread
                    let hasFromPeer = msgs.contains { $0.fromUserId == pid }
                    if hasFromPeer { unreadChats.insert(pid) }
                }
            }
        }
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