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
    var myDest: Place = Mock.places.first { $0.id != "BLR" } ?? Mock.places[0]
    var myComfortKm: Double = 5
    var iAmOpen = false

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
        iAmOpen = false
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
                origin: myOrigin, dest: myDest, comfortKm: myComfortKm, isOpen: iAmOpen)) ?? []
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
        guard isConnected else { return }
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
            let rider = Rider(name: sm.fromUserName, gender: .other, rating: 5, trips: 0,
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
}