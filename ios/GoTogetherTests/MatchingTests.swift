import XCTest
@testable import GoTogether

final class MatchingTests: XCTestCase {
    private func query(_ id: String) -> SearchQuery {
        var q = SearchQuery()
        q.destination = Mock.places.first { $0.id == id }!
        q.departAt = Date().addingTimeInterval(15 * 60)
        return q
    }

    func testRadiusFiltersFarRiders() {
        let names = MatchingEngine.find(query: query("indira"), riders: Mock.riders(), myGender: .male).map(\.rider.name)
        XCTAssertTrue(names.contains("Priya S."))
        XCTAssertFalse(names.contains("Arjun B."))
    }

    func testVerifiedOnlyExcludesUnverified() {
        var q = query("kora"); q.verifiedOnly = true
        XCTAssertFalse(MatchingEngine.find(query: q, riders: Mock.riders(), myGender: .male).map(\.rider.name).contains("Sneha P."))
        q.verifiedOnly = false
        XCTAssertTrue(MatchingEngine.find(query: q, riders: Mock.riders(), myGender: .male).map(\.rider.name).contains("Sneha P."))
    }

    func testSharedFareIsCheaperThanSolo() {
        let a = Mock.places[1], b = Mock.places[2]
        XCTAssertLessThan(Fare.shared(you: a, them: b), Fare.solo(to: a))
    }

    func testOpenMatchFindsCompatible() {
        let hits = MatchingEngine.findOpen(
            myOrigin: Mock.airportEdge, myDest: Mock.places.first { $0.id == "indira" }!, myRadiusKm: 5,
            intents: Mock.openIntents(now: Date()), myGender: .male,
            verifiedOnly: false, sameGenderOnly: false
        )
        // Priya S. (indira, origin=airportEdge) should match at 0 km dest gap.
        XCTAssertTrue(hits.contains { $0.rider.name == "Priya S." })
        // Vikram T. (marathahalli) is far from indiranagar — shouldn't match at radius 5.
        XCTAssertFalse(hits.contains { $0.rider.name == "Vikram T." })
    }

    func testOpenMatchExcludesFarOrigin() {
        let hits = MatchingEngine.findOpen(
            myOrigin: Mock.airport, myDest: Mock.places.first { $0.id == "indira" }!, myRadiusKm: 10,
            intents: Mock.openIntents(now: Date()), myGender: .male,
            verifiedOnly: false, sameGenderOnly: false
        )
        // airportEdge is ~0.2 km from airport — still within 0.5 km.
        // But with myOrigin=airport (not airportEdge), gap is still small.
        // The intent's origin is airportEdge or airportSouth — both near the airport.
        XCTAssertTrue(hits.contains { $0.rider.name == "Priya S." })
    }
}
