import Foundation
import Observation

@Observable
final class AppState {
    let api = ApiClient()

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

    var onboarded: Bool { phoneVerified && idVerified && !name.isEmpty && !emergencyPhone.isEmpty }

    // Trip intent
    var myOrigin = Mock.airport
    var myDest = Mock.places.first { $0.id != "BLR" } ?? Mock.places[0]
    var myComfortKm: Double = 5
    var iAmOpen = false

    // Trips
    var search = SearchQuery()
    var activeTrip: Trip?
    var history: [Trip] = []
    var safetyLog: [String] = []

    // Server state
    var serverIntents: [ServerIntent] = []
    var serverCompatible: [ServerIntent] = []
    var serverPending: [ServerMatch] = []

    /// True when registered with the server.
    var isConnected: Bool { api.userId != nil }

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

    func refreshIntents() {
        guard isConnected else { return }
        Task {
            let intents = (try? await api.searchIntents(
                origin: myOrigin, dest: myDest, comfortKm: myComfortKm,
                verifiedOnly: search.verifiedOnly, sameGender: search.sameGenderOnly)) ?? []
            await MainActor.run { serverIntents = intents }
        }
    }

    func pollPending() {
        guard isConnected else { return }
        Task {
            let pending = (try? await api.pendingMatches()) ?? []
            await MainActor.run { serverPending = pending }
        }
    }

    // MARK: - Intents (server-first, Mock fallback)

    var openIntents: [TravelIntent] {
        if isConnected && !serverIntents.isEmpty {
            return serverIntents.map(api.serverIntentToTravelIntent)
        }
        return Mock.openIntents(now: Date())
    }

    func matchingOpenIntents() -> [TravelIntent] {
        if isConnected && !serverIntents.isEmpty {
            return serverIntents.map(api.serverIntentToTravelIntent)
        }
        return MatchingEngine.findOpen(
            myOrigin: myOrigin, myDest: myDest, myRadiusKm: myComfortKm,
            intents: Mock.openIntents(now: Date()), myGender: gender,
            verifiedOnly: search.verifiedOnly, sameGenderOnly: search.sameGenderOnly
        )
    }

    func matches() -> [Match] {
        MatchingEngine.find(query: search, riders: Mock.riders(), myGender: gender)
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
        // Server path: send match request
        if isConnected, let si = serverIntents.first(where: { $0.intentId == i.rider.id.uuidString || $0.userId == i.rider.name || $0.userName == i.rider.name }) {
            Task {
                guard let m = try? await api.requestMatch(toIntentId: si.intentId) else { return }
                await MainActor.run {
                    let rider = i.rider
                    let match = Match(rider: rider, destGapKm: m.destGapKm ?? Geo.km(myDest, i.rider.destination), timeGapMin: 0,
                                      soloFare: Int(Fare.solo(to: myDest).rounded()),
                                      sharedFare: Int(Fare.shared(you: myDest, them: rider.destination).rounded()))
                    request(match)
                }
            }
            return
        }
        // Fallback local
        let m = Match(rider: i.rider, destGapKm: Geo.km(myDest, i.rider.destination),
                      timeGapMin: 0,
                      soloFare: Int(Fare.solo(to: myDest).rounded()),
                      sharedFare: Int(Fare.shared(you: myDest, them: i.rider.destination).rounded()))
        request(m)
    }

    /// Accept an incoming server match request.
    func acceptServerMatch(_ sm: ServerMatch) async {
        guard let m = try? await api.respondToMatch(matchId: sm.matchId, accept: true) else { return }
        await MainActor.run {
            let rider = Rider(name: sm.fromUserName, gender: .other, rating: 5, trips: 0, idVerified: true,
                              idRef: "", destination: myDest, departAt: Date())
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
        I'm sharing a cab from \(Mock.airport.name) to \(myDest.name).
        Trip \(t.id) · Cab \(t.cabPlate) · Driver \(t.driverName)
        Co-rider: \(t.match.rider.name) (\(t.match.rider.idRef))
        """
    }

    private func stamp() -> String { Date().formatted(date: .omitted, time: .shortened) }
}
