package com.gotogether.app

import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

object Geo {
    /** Great-circle distance in km. */
    fun km(a: Place, b: Place): Double {
        val r = 6371.0
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLon = Math.toRadians(b.lon - a.lon)
        val h = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(h))
    }
}

object Fare {
    private const val BASE = 150.0
    private const val PER_KM = 22.0
    private const val ROAD_FACTOR = 1.3
    private const val OVERLAP_SHARE = 0.2

    fun solo(to: Place) = BASE + PER_KM * ROAD_FACTOR * Geo.km(Mock.airport, to)

    fun shared(you: Place, them: Place): Double {
        val a = solo(you)
        val b = solo(them)
        return (max(a, b) + OVERLAP_SHARE * min(a, b)) * a / (a + b)
    }
}

object MatchingEngine {
    fun find(q: SearchQuery, riders: List<Rider>, myGender: Gender, nowMs: Long = System.currentTimeMillis()): List<Match> {
        val departAt = nowMs + (q.departInMin * 60_000).toLong()
        return riders.mapNotNull { r ->
            val gap = Geo.km(q.destination, r.destination)
            val tGap = (abs(r.departAtMs - departAt) / 60_000).toInt()
            when {
                gap > q.comfortRadiusKm || tGap > q.windowMin -> null
                q.verifiedOnly && !r.idVerified -> null
                q.sameGenderOnly && r.gender != myGender -> null
                else -> Match(
                    r, gap, tGap,
                    Fare.solo(q.destination).roundToInt(),
                    Fare.shared(q.destination, r.destination).roundToInt(),
                )
            }
        }.sortedWith(compareBy({ it.destGapKm }, { it.timeGapMin }))
    }

    /// Two-way match: find "open to travel" users whose origin is near mine
    /// and whose destination falls within my comfort radius.
    fun findOpen(
        myOrigin: Place, myDest: Place, myRadiusKm: Double,
        intents: List<TravelIntent>, myGender: Gender,
        verifiedOnly: Boolean, sameGenderOnly: Boolean,
    ): List<TravelIntent> {
        return intents
            .filter { it.isOpen }
            .filter { i -> !verifiedOnly || i.rider.idVerified }
            .filter { i -> !sameGenderOnly || i.rider.gender == myGender }
            .filter { i ->
                val originGap = Geo.km(myOrigin, i.origin)
                val destGap = Geo.km(myDest, i.rider.destination)
                originGap <= 0.5 && destGap <= myRadiusKm &&
                    Geo.km(i.rider.destination, myDest) <= i.comfortRadiusKm
            }
            .sortedBy { Geo.km(myDest, it.rider.destination) }
    }
}
