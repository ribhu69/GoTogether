import Foundation

enum Mock {
    static let airport = Place(id: "BLR", name: "Kempegowda Airport (BLR)", lat: 13.1986, lon: 77.7066)

    // Satellite points near the airport so "open" users cluster around it visually.
    static let airportEdge = Place(id: "BLR-edge", name: "Airport pickup lane", lat: 13.2000, lon: 77.7080)
    static let airportSouth = Place(id: "BLR-south", name: "Airport south exit", lat: 13.1960, lon: 77.7050)

    static let places: [Place] = [
        airport,
        Place(id: "hebbal", name: "Hebbal", lat: 13.0358, lon: 77.5970),
        Place(id: "mg", name: "MG Road", lat: 12.9756, lon: 77.6068),
        Place(id: "indira", name: "Indiranagar", lat: 12.9784, lon: 77.6408),
        Place(id: "kora", name: "Koramangala", lat: 12.9352, lon: 77.6245),
        Place(id: "hsr", name: "HSR Layout", lat: 12.9116, lon: 77.6474),
        Place(id: "white", name: "Whitefield", lat: 12.9698, lon: 77.7500),
        Place(id: "marath", name: "Marathahalli", lat: 12.9569, lon: 77.7011),
        Place(id: "ecity", name: "Electronic City", lat: 12.8452, lon: 77.6602),
        Place(id: "yelah", name: "Yelahanka", lat: 13.1007, lon: 77.5963),
        Place(id: "malle", name: "Malleshwaram", lat: 13.0035, lon: 77.5647),
        Place(id: "jaya", name: "Jayanagar", lat: 12.9250, lon: 77.5938),
    ]

    private static func p(_ id: String) -> Place { places.first { $0.id == id }! }

    static func riders(now: Date = Date()) -> [Rider] {
        func r(_ n: String, _ g: Gender, _ rt: Double, _ t: Int, _ v: Bool, _ ref: String, _ d: String, _ off: Int) -> Rider {
            Rider(name: n, gender: g, rating: rt, trips: t, idVerified: v, idRef: ref,
                  destination: p(d), departAt: now.addingTimeInterval(Double(off) * 60))
        }
        return [
            r("Priya S.", .female, 4.9, 42, true, "AADHAAR ••••4821", "indira", 12),
            r("Rahul M.", .male, 4.7, 18, true, "PASSPORT ••••7710", "mg", 20),
            r("Ananya R.", .female, 4.8, 31, true, "DL ••••2093", "hebbal", 8),
            r("Vikram T.", .male, 4.5, 9, true, "AADHAAR ••••3356", "marath", 25),
            r("Sneha P.", .female, 4.6, 5, false, "UNVERIFIED", "kora", 18),
            r("Karthik N.", .male, 4.9, 77, true, "PASSPORT ••••1188", "white", 35),
            r("Meera D.", .female, 4.8, 24, true, "AADHAAR ••••9042", "yelah", 15),
            r("Arjun B.", .male, 4.4, 12, true, "DL ••••6617", "ecity", 22),
            r("Divya L.", .female, 4.7, 16, true, "AADHAAR ••••5530", "malle", 60),
        ]
    }

    /// People who are "open to travel" right now from near the airport.
    static func openIntents(now: Date) -> [TravelIntent] {
        let riders = riders(now: now)
        let origins = [airportEdge, airportSouth]
        let radii: [Double] = [3, 5, 7, 4, 6, 5, 3, 7, 5]
        return zip(riders, radii).enumerated().map { i, pair in
            TravelIntent(rider: pair.0, origin: origins[i % 2],
                         comfortRadiusKm: pair.1, isOpen: true,
                         openUntil: now.addingTimeInterval(120 * 60))
        }
    }
}
