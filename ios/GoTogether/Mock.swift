import Foundation

enum Mock {
    static let airport = Place(id: "BLR", name: "Kempegowda Airport (BLR)", lat: 13.1986, lon: 77.7066)

    // Keep a small reference set for tests only (not shown in UI)
    static let airportEdge = Place(id: "airportEdge", name: "BLR Terminal", lat: 13.1990, lon: 77.7075)
    static let indiranagar = Place(id: "indira", name: "Indiranagar", lat: 12.9784, lon: 77.6408)
    static let koramangala = Place(id: "kora", name: "Koramangala", lat: 12.9352, lon: 77.6245)
    static let hebbal = Place(id: "hebbal", name: "Hebbal", lat: 13.0358, lon: 77.5970)
    static let marathahalli = Place(id: "marath", name: "Marathahalli", lat: 12.9569, lon: 77.7011)

    // Legacy array for tests
    static let places: [Place] = [airport, hebbal, indiranagar, koramangala, marathahalli]

    static func riders() -> [Rider] {[
        Rider(userId: "priya", name: "Priya S.", gender: .female, rating: 4.8, trips: 23, idVerified: true,
              idRef: "Aadhaar ••••1234", destination: indiranagar, departAt: Date()),
        Rider(userId: "arjun", name: "Arjun B.", gender: .male, rating: 4.5, trips: 12, idVerified: true,
              idRef: "DL ••••5678", destination: hebbal, departAt: Date()),
        Rider(userId: "sneha", name: "Sneha P.", gender: .female, rating: 4.2, trips: 5, idVerified: false,
              idRef: "Aadhaar ••••9012", destination: koramangala, departAt: Date()),
    ]}

    static func openIntents(now: Date) -> [TravelIntent] {[
        TravelIntent(userId: "priya", rider: Rider(userId: "priya", name: "Priya S.", gender: .female, rating: 4.8, trips: 23,
                     idVerified: true, idRef: "Aadhaar ••••1234",
                     destination: indiranagar, departAt: now),
                     origin: airportEdge, comfortRadiusKm: 10, isOpen: true, openUntil: now.addingTimeInterval(3600)),
        TravelIntent(userId: "vikram", rider: Rider(userId: "vikram", name: "Vikram T.", gender: .male, rating: 4.6, trips: 18,
                     idVerified: true, idRef: "Passport ••••3456",
                     destination: marathahalli, departAt: now),
                     origin: airport, comfortRadiusKm: 5, isOpen: true, openUntil: now.addingTimeInterval(3600)),
    ]}
}