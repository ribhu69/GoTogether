import Foundation
import Observation
import CoreLocation

// MARK: - JSON shapes matching the server

struct ServerUser: Codable { let userId: String; var name: String; var phone: String; var gender: String; var idType: String; var idLast4: String; var emergencyName: String; var emergencyPhone: String; var phoneVerified: Bool; var idVerified: Bool }

struct ServerCoord: Codable { let lat: Double; let lon: Double; let name: String? }

struct ServerIntent: Codable {
    let intentId: String; let userId: String; let userName: String; let userGender: String
    let idVerified: Bool; let idRef: String; let rating: Double; let trips: Int
    let origin: ServerCoord; let dest: ServerCoord
    let comfortRadiusKm: Double; let isOpen: Bool
    let originGapKm: Double?; let destGapKm: Double?
}

struct ServerMatch: Codable {
    let matchId: String; let fromUserId: String; let fromUserName: String
    let toUserId: String; let toUserName: String; let toIntentId: String
    let destGapKm: Double?; var status: String
    let cabPlate: String?; let pin: String?; let driverName: String?
}

struct ServerPeerLocation: Codable {
    let userId: String; let userName: String
    let lat: Double; let lon: Double; let name: String?
    let destLat: Double?; let destLon: Double?; let destName: String?
}

struct IntentsResponse: Codable { let intents: [ServerIntent]; let peers: [ServerPeerLocation]? }
struct MatchesResponse: Codable { let matches: [ServerMatch] }

// Chat
struct ServerChatMessage: Codable { let fromUserId: String; let toUserId: String; let text: String; let ts: Double }
struct MessagesResponse: Codable { let messages: [ServerChatMessage] }

struct SearchResult {
    let intents: [ServerIntent]
    let peers: [PeerLocation]

    static let empty = SearchResult(intents: [], peers: [])
}

// MARK: - API client

@Observable
final class ApiClient {
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "apiBaseURL") }
    }
    var userId: String? {
        didSet { UserDefaults.standard.set(userId, forKey: "apiUserId") }
    }

    init() {
        baseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://localhost:8080"
        userId = UserDefaults.standard.string(forKey: "apiUserId")
    }

    // ── helpers ──

    private func post<T: Decodable>(_ path: String, _ body: Encodable) async throws -> T {
        var r = URLRequest(url: URL(string: "\(baseURL)\(path)")!); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(body)
        let (d, _) = try await URLSession.shared.data(for: r)
        return try JSONDecoder().decode(T.self, from: d)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (d, _) = try await URLSession.shared.data(from: URL(string: "\(baseURL)\(path)")!)
        return try JSONDecoder().decode(T.self, from: d)
    }

    // ── endpoints ──

    func register(name: String, phone: String, gender: String, idType: String, idLast4: String,
                  emergencyName: String, emergencyPhone: String) async throws -> ServerUser {
        let u: ServerUser = try await post("/api/register", RegisterBody(
            name: name, phone: phone, gender: gender,
            idType: idType, idLast4: idLast4,
            emergencyName: emergencyName, emergencyPhone: emergencyPhone))
        userId = u.userId
        return u
    }

    func verifyPhone(otp: String) async throws -> ServerUser {
        try await post("/api/verify", VerifyBody(userId: userId!, type: "phone", otp: otp, idLast4: nil))
    }

    func verifyId(idLast4: String) async throws -> ServerUser {
        try await post("/api/verify", VerifyBody(userId: userId!, type: "id", otp: nil, idLast4: idLast4))
    }

    func upsertIntent(origin: Place, dest: Place, comfortKm: Double, isOpen: Bool) async throws -> [ServerIntent] {
        struct R: Decodable { let compatible: [ServerIntent] }
        let r: R = try await post("/api/intent", IntentBody(
            userId: userId!,
            origin: ServerCoord(lat: origin.lat, lon: origin.lon, name: origin.name),
            dest: ServerCoord(lat: dest.lat, lon: dest.lon, name: dest.name),
            comfortRadiusKm: comfortKm, isOpen: isOpen))
        return r.compatible
    }

    func updateLocation(lat: Double, lon: Double, name: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await post("/api/location", LocationBody(
            userId: userId!, lat: lat, lon: lon, name: name))
    }

    func searchIntents(origin: Place, dest: Place, comfortKm: Double,
                       verifiedOnly: Bool, sameGender: Bool) async throws -> SearchResult {
        let r: IntentsResponse = try await get(
            "/api/intents?userId=\(userId!)&lat=\(origin.lat)&lon=\(origin.lon)" +
            "&destLat=\(dest.lat)&destLon=\(dest.lon)&comfortKm=\(comfortKm)" +
            "&verifiedOnly=\(verifiedOnly)&sameGender=\(sameGender)")
        return SearchResult(
            intents: r.intents,
            peers: (r.peers ?? []).map { p in
                PeerLocation(
                    id: p.userId, name: p.userName,
                    coord: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
                    destination: p.destLat != nil
                        ? Place(id: p.destName ?? "", name: p.destName ?? "", lat: p.destLat!, lon: p.destLon!)
                        : nil)
            })
    }

    func requestMatch(toIntentId: String) async throws -> ServerMatch {
        try await post("/api/match/request", MatchRequestBody(fromUserId: userId!, toIntentId: toIntentId))
    }

    func pendingMatches() async throws -> [ServerMatch] {
        let r: MatchesResponse = try await get("/api/match/pending?userId=\(userId!)")
        return r.matches
    }

    func respondToMatch(matchId: String, accept: Bool) async throws -> ServerMatch {
        try await post("/api/match/respond", MatchRespondBody(matchId: matchId, userId: userId!, accept: accept))
    }

    // ── chat ──

    func sendMessage(toUserId: String, text: String) async throws -> ServerChatMessage {
        try await post("/api/message", SendMessageBody(fromUserId: userId!, toUserId: toUserId, text: text))
    }

    func fetchMessages(peerId: String, since: Double = 0) async throws -> [ServerChatMessage] {
        let r: MessagesResponse = try await get(
            "/api/messages?userId=\(userId!)&peerId=\(peerId)&since=\(since)")
        return r.messages
    }

    // ── bridge helpers ──

    func serverIntentToTravelIntent(_ si: ServerIntent) -> TravelIntent {
        let rider = Rider(
            name: si.userName,
            gender: Gender(rawValue: si.userGender.capitalized) ?? .other,
            rating: si.rating, trips: si.trips,
            idVerified: si.idVerified, idRef: si.idRef,
            destination: Place(id: si.dest.name ?? "", name: si.dest.name ?? "",
                               lat: si.dest.lat, lon: si.dest.lon),
            departAt: Date())
        return TravelIntent(
            rider: rider,
            origin: Place(id: si.origin.name ?? "", name: si.origin.name ?? "",
                          lat: si.origin.lat, lon: si.origin.lon),
            comfortRadiusKm: si.comfortRadiusKm,
            isOpen: si.isOpen,
            openUntil: Date().addingTimeInterval(3600))
    }
}

// MARK: - Request body structs (Codable)

private struct RegisterBody: Encodable {
    let name: String; let phone: String; let gender: String
    let idType: String; let idLast4: String
    let emergencyName: String; let emergencyPhone: String
}

private struct VerifyBody: Encodable {
    let userId: String; let type: String; let otp: String?; let idLast4: String?
}

private struct IntentBody: Encodable {
    let userId: String; let origin: ServerCoord; let dest: ServerCoord
    let comfortRadiusKm: Double; let isOpen: Bool
}

private struct LocationBody: Encodable {
    let userId: String; let lat: Double; let lon: Double; let name: String
}

private struct MatchRequestBody: Encodable {
    let fromUserId: String; let toIntentId: String
}

private struct MatchRespondBody: Encodable {
    let matchId: String; let userId: String; let accept: Bool
}

private struct SendMessageBody: Encodable {
    let fromUserId: String; let toUserId: String; let text: String
}