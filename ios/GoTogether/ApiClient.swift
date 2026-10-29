import Foundation
import Observation

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

struct IntentsResponse: Codable { let intents: [ServerIntent] }
struct MatchesResponse: Codable { let matches: [ServerMatch] }

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

    private func post<T: Decodable>(_ path: String, _ body: [String: Any]) async throws -> T {
        var r = URLRequest(url: URL(string: "\(baseURL)\(path)")!); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
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
        let u: ServerUser = try await post("/api/register", [
            "name": name, "phone": phone, "gender": gender,
            "idType": idType, "idLast4": idLast4,
            "emergencyName": emergencyName, "emergencyPhone": emergencyPhone,
        ])
        userId = u.userId
        return u
    }

    func verifyPhone(otp: String) async throws -> ServerUser {
        try await post("/api/verify", ["userId": userId!, "type": "phone", "otp": otp])
    }

    func verifyId(idLast4: String) async throws -> ServerUser {
        try await post("/api/verify", ["userId": userId!, "type": "id", "idLast4": idLast4])
    }

    func upsertIntent(origin: Place, dest: Place, comfortKm: Double, isOpen: Bool) async throws -> [ServerIntent] {
        struct R: Decodable { let compatible: [ServerIntent] }
        let r: R = try await post("/api/intent", [
            "userId": userId!,
            "origin": ["lat": origin.lat, "lon": origin.lon, "name": origin.name],
            "dest": ["lat": dest.lat, "lon": dest.lon, "name": dest.name],
            "comfortRadiusKm": comfortKm, "isOpen": isOpen,
        ])
        return r.compatible
    }

    func searchIntents(origin: Place, dest: Place, comfortKm: Double,
                       verifiedOnly: Bool, sameGender: Bool) async throws -> [ServerIntent] {
        let r: IntentsResponse = try await get(
            "/api/intents?userId=\(userId!)&lat=\(origin.lat)&lon=\(origin.lon)" +
            "&destLat=\(dest.lat)&destLon=\(dest.lon)&comfortKm=\(comfortKm)" +
            "&verifiedOnly=\(verifiedOnly)&sameGender=\(sameGender)")
        return r.intents
    }

    func requestMatch(toIntentId: String) async throws -> ServerMatch {
        try await post("/api/match/request", ["fromUserId": userId!, "toIntentId": toIntentId])
    }

    func pendingMatches() async throws -> [ServerMatch] {
        let r: MatchesResponse = try await get("/api/match/pending?userId=\(userId!)")
        return r.matches
    }

    func respondToMatch(matchId: String, accept: Bool) async throws -> ServerMatch {
        try await post("/api/match/respond", ["matchId": matchId, "userId": userId!, "accept": accept])
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
