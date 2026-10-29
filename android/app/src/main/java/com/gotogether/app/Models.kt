package com.gotogether.app

import org.osmdroid.util.GeoPoint

enum class Gender(val label: String) { Female("Female"), Male("Male"), Other("Other") }

data class Place(val id: String, val name: String, val lat: Double, val lon: Double) {
    val geoPoint get() = GeoPoint(lat, lon)
}

data class Rider(
    val id: String,
    val name: String,
    val gender: Gender,
    val rating: Double,
    val trips: Int,
    val idVerified: Boolean,
    val idRef: String,
    val destination: Place,
    val departAtMs: Long,
)

/// A user who has toggled "open to travel." Broadcasts origin, destination, and comfort radius.
data class TravelIntent(
    val id: String,
    val rider: Rider,
    val origin: Place,
    val comfortRadiusKm: Double,
    val isOpen: Boolean,
    val openUntilMs: Long,
)

data class SearchQuery(
    val destination: Place = Mock.places[0],
    val departInMin: Float = 15f,
    val comfortRadiusKm: Float = 5f,
    val windowMin: Float = 30f,
    val verifiedOnly: Boolean = true,
    val sameGenderOnly: Boolean = false,
)

data class Match(
    val rider: Rider,
    val destGapKm: Double,
    val timeGapMin: Int,
    val soloFare: Int,
    val sharedFare: Int,
) { val saving get() = soloFare - sharedFare }

enum class TripStatus(val label: String) {
    Requested("Requesting"), Confirmed("Confirmed"), Completed("Completed"), Sos("SOS raised")
}

data class Trip(
    val match: Match,
    val id: String = "GT-" + (100000..999999).random(),
    val pin: String = (1000..9999).random().toString(),
    val cabPlate: String = "KA 01 AB " + (1000..9999).random(),
    val driverName: String = "Ravi K.",
    val status: TripStatus = TripStatus.Requested,
    val events: List<String> = emptyList(),
)
