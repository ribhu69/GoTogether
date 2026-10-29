package com.gotogether.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertTrue as ok
import org.junit.Test

class MatchingTest {
    private fun q(id: String) = SearchQuery(destination = Mock.places.first { it.id == id })
    private fun names(q: SearchQuery) = MatchingEngine.find(q, Mock.riders(), Gender.Male).map { it.rider.name }

    @Test fun radiusFiltersFarRiders() {
        val n = names(q("indira"))
        assertTrue("Priya S." in n)
        assertFalse("Arjun B." in n)
    }

    @Test fun verifiedOnlyExcludesUnverified() {
        assertFalse("Sneha P." in names(q("kora").copy(verifiedOnly = true)))
        assertTrue("Sneha P." in names(q("kora").copy(verifiedOnly = false)))
    }

    @Test fun sharedFareIsCheaperThanSolo() {
        val a = Mock.places[1]; val b = Mock.places[2]
        ok(Fare.shared(a, b) < Fare.solo(a))
    }

    @Test fun openMatchFindsCompatible() {
        val hits = MatchingEngine.findOpen(
            Mock.airportEdge, Mock.places.first { it.id == "indira" }, 5.0,
            Mock.openIntents(), Gender.Male, verifiedOnly = false, sameGenderOnly = false,
        )
        assertTrue(hits.any { it.rider.name == "Priya S." })   // Indiranagar, 0 km
        assertFalse(hits.any { it.rider.name == "Vikram T." }) // Marathahalli, far
    }

    @Test fun openMatchExcludesFarOrigin() {
        val hits = MatchingEngine.findOpen(
            Mock.airport, Mock.places.first { it.id == "indira" }, 10.0,
            Mock.openIntents(), Gender.Male, verifiedOnly = false, sameGenderOnly = false,
        )
        assertTrue(hits.any { it.rider.name == "Priya S." })
    }
}
