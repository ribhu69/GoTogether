import Foundation
import CoreLocation

enum Gender: String, CaseIterable, Identifiable {
    case female = "Female", male = "Male", other = "Other"
    var id: String { rawValue }
}

struct Place: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    var coord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

struct Rider: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let gender: Gender
    let rating: Double
    let trips: Int
    let idVerified: Bool
    let idRef: String
    let destination: Place
    let departAt: Date
}

/// A user who has toggled "open to travel." Broadcasts origin, destination, and comfort radius.
struct TravelIntent: Identifiable, Hashable {
    let id = UUID()
    let rider: Rider
    var origin: Place
    var comfortRadiusKm: Double
    var isOpen: Bool
    var openUntil: Date
}

struct SearchQuery {
    var destination: Place = Mock.places[0]
    var departAt: Date = Date().addingTimeInterval(15 * 60)
    var comfortRadiusKm: Double = 5
    var windowMin: Double = 30
    var verifiedOnly = true
    var sameGenderOnly = false
}

struct Match: Identifiable {
    var id: UUID { rider.id }
    let rider: Rider
    let destGapKm: Double
    let timeGapMin: Int
    let soloFare: Int
    let sharedFare: Int
    var saving: Int { soloFare - sharedFare }
}

enum TripStatus: String { case requested = "Requesting", confirmed = "Confirmed", completed = "Completed", sos = "SOS raised" }

struct Trip: Identifiable {
    let id = "GT-" + String(Int.random(in: 100000...999999))
    let match: Match
    let pin = String(Int.random(in: 1000...9999))
    let cabPlate = "KA 01 AB " + String(Int.random(in: 1000...9999))
    let driverName = "Ravi K."
    var status: TripStatus = .requested
    var events: [String] = []
}
