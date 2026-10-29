import Foundation

enum Geo {
    static func km(_ a: Place, _ b: Place) -> Double {
        let r = 6371.0
        let dLat = (b.lat - a.lat) * .pi / 180, dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(h))
    }
}

enum Fare {
    static let base = 150.0, perKm = 22.0, roadFactor = 1.3, overlapShare = 0.2

    static func solo(to p: Place) -> Double { base + perKm * roadFactor * Geo.km(Mock.airport, p) }

    static func shared(you: Place, them: Place) -> Double {
        let a = solo(to: you), b = solo(to: them)
        return (max(a, b) + overlapShare * min(a, b)) * a / (a + b)
    }
}

enum MatchingEngine {
    /// Classic search: find riders heading near my destination.
    static func find(query q: SearchQuery, riders: [Rider], myGender: Gender) -> [Match] {
        riders.compactMap { r in
            let gap = Geo.km(q.destination, r.destination)
            let tGap = Int(abs(r.departAt.timeIntervalSince(q.departAt)) / 60)
            guard gap <= q.comfortRadiusKm, Double(tGap) <= q.windowMin else { return nil }
            if q.verifiedOnly && !r.idVerified { return nil }
            if q.sameGenderOnly && r.gender != myGender { return nil }
            return Match(rider: r, destGapKm: gap, timeGapMin: tGap,
                         soloFare: Int(Fare.solo(to: q.destination).rounded()),
                         sharedFare: Int(Fare.shared(you: q.destination, them: r.destination).rounded()))
        }
        .sorted { ($0.destGapKm, $0.timeGapMin) < ($1.destGapKm, $1.timeGapMin) }
    }

    /// Two-way match: find "open to travel" users whose origin is near mine
    /// and whose destination falls within my comfort radius. Their radius must
    /// also accommodate my destination.
    static func findOpen(myOrigin: Place, myDest: Place, myRadiusKm: Double,
                         intents: [TravelIntent], myGender: Gender,
                         verifiedOnly: Bool, sameGenderOnly: Bool) -> [TravelIntent] {
        intents
            .filter { $0.isOpen }
            .filter { i in !verifiedOnly || i.rider.idVerified }
            .filter { i in !sameGenderOnly || i.rider.gender == myGender }
            .filter { i in
                let originGap = Geo.km(myOrigin, i.origin)
                let destGap = Geo.km(myDest, i.rider.destination)
                // Both riders' comfort radii must accommodate each other's destinations.
                return originGap <= 0.5 && destGap <= myRadiusKm
                    && Geo.km(i.rider.destination, myDest) <= i.comfortRadiusKm
            }
            .sorted { Geo.km(myDest, $0.rider.destination) < Geo.km(myDest, $1.rider.destination) }
    }
}
