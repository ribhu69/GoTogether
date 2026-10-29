package com.gotogether.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class AppState : ViewModel() {
    val api = ApiClient()

    // Profile / trust
    var name by mutableStateOf("")
    var phone by mutableStateOf("")
    var gender by mutableStateOf(Gender.Female)
    var phoneVerified by mutableStateOf(false)
    var idVerified by mutableStateOf(false)
    var idType by mutableStateOf("Aadhaar")
    var idLast4 by mutableStateOf("")
    var emergencyName by mutableStateOf("")
    var emergencyPhone by mutableStateOf("")

    val onboarded get() = phoneVerified && idVerified && name.isNotEmpty() && emergencyPhone.isNotEmpty()

    // My travel intent
    var myOrigin by mutableStateOf(Mock.airport)
    var myDest by mutableStateOf(Mock.places.first { it.id != "BLR" })
    var myComfortKm by mutableStateOf(5.0)
    var iAmOpen by mutableStateOf(false)

    // Trips
    var search by mutableStateOf(SearchQuery())
    var activeTrip by mutableStateOf<Trip?>(null)
    val history = mutableStateListOf<Trip>()
    val safetyLog = mutableStateListOf<String>()

    // Server state
    var serverIntents by mutableStateOf<List<ServerIntent>>(emptyList())
    var serverCompatible by mutableStateOf<List<ServerIntent>>(emptyList())
    var serverPending by mutableStateOf<List<ServerMatch>>(emptyList())

    val isConnected get() = api.userId != null

    // ── Registration (server) ──

    fun registerWithServer(onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            try {
                val u = api.register(name, phone, gender.label.lowercase(), idType, idLast4, emergencyName, emergencyPhone)
                phoneVerified = u.phoneVerified; idVerified = u.idVerified
                onResult(true)
            } catch (_: Exception) { onResult(false) }
        }
    }

    fun verifyPhoneOnServer(otp: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            try { val u = api.verifyPhone(otp); phoneVerified = u.phoneVerified; onResult(true) }
            catch (_: Exception) { onResult(false) }
        }
    }

    fun verifyIdOnServer(last4: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            try { val u = api.verifyId(last4); idVerified = u.idVerified; onResult(true) }
            catch (_: Exception) { onResult(false) }
        }
    }

    // ── Intent sync ──

    fun syncIntent() {
        if (!isConnected) return
        viewModelScope.launch {
            try { serverCompatible = api.upsertIntent(myOrigin, myDest, myComfortKm, iAmOpen) }
            catch (_: Exception) {}
        }
    }

    fun refreshIntents() {
        if (!isConnected) return
        viewModelScope.launch {
            try {
                serverIntents = api.searchIntents(myOrigin, myDest, myComfortKm,
                    search.verifiedOnly, search.sameGenderOnly)
            } catch (_: Exception) {}
        }
    }

    fun pollPending() {
        if (!isConnected) return
        viewModelScope.launch {
            try { serverPending = api.pendingMatches() } catch (_: Exception) {}
        }
    }

    // ── Intents (server-first, Mock fallback) ──

    fun openIntents(): List<TravelIntent> {
        if (isConnected && serverIntents.isNotEmpty()) return serverIntents.map(api::toTravelIntent)
        return Mock.openIntents()
    }

    fun matchingOpenIntents(): List<TravelIntent> {
        if (isConnected && serverIntents.isNotEmpty()) return serverIntents.map(api::toTravelIntent)
        return MatchingEngine.findOpen(myOrigin, myDest, myComfortKm, Mock.openIntents(), gender,
            verifiedOnly = search.verifiedOnly, sameGenderOnly = search.sameGenderOnly)
    }

    fun matches() = MatchingEngine.find(search, Mock.riders(), gender)

    // ── Trip actions ──

    fun request(m: Match) {
        val t = Trip(m, events = listOf("${stamp()} Requested share with ${m.rider.name} (${m.rider.idRef})"))
        activeTrip = t
        viewModelScope.launch {
            delay(2000)
            val cur = activeTrip ?: return@launch
            if (cur.id != t.id) return@launch
            activeTrip = cur.copy(
                status = TripStatus.Confirmed,
                events = cur.events + "${stamp()} ${m.rider.name} accepted. Cab ${t.cabPlate}, PIN ${t.pin}",
            )
        }
    }

    fun requestIntent(i: TravelIntent) {
        if (isConnected) {
            val si = serverIntents.find { it.intentId == i.id || it.userName == i.rider.name }
            if (si != null) {
                viewModelScope.launch {
                    try {
                        val m = api.requestMatch(si.intentId)
                        val match = Match(i.rider, m.destGapKm ?: Geo.km(myDest, i.rider.destination), 0,
                            Fare.solo(myDest).roundToInt(), Fare.shared(myDest, i.rider.destination).roundToInt())
                        request(match)
                    } catch (_: Exception) {}
                }
                return
            }
        }
        val m = Match(i.rider, Geo.km(myDest, i.rider.destination), 0,
            Fare.solo(myDest).roundToInt(), Fare.shared(myDest, i.rider.destination).roundToInt())
        request(m)
    }

    fun acceptServerMatch(sm: ServerMatch) {
        viewModelScope.launch {
            try {
                val m = api.respondToMatch(sm.matchId, true)
                val rider = Rider(sm.fromUserId, sm.fromUserName, Gender.Other, 5.0, 0, true, "", myDest, System.currentTimeMillis())
                val match = Match(rider, sm.destGapKm ?: 0.0, 0,
                    Fare.solo(myDest).roundToInt(), Fare.shared(myDest, myDest).roundToInt())
                val t = Trip(match, events = listOf("${stamp()} Accepted match from ${sm.fromUserName}. Cab ${m.cabPlate ?: ""}, PIN ${m.pin ?: ""}"))
                activeTrip = t.copy(status = TripStatus.Confirmed)
            } catch (_: Exception) {}
        }
    }

    fun complete() {
        val t = activeTrip ?: return
        history.add(0, t.copy(status = TripStatus.Completed, events = t.events + "${stamp()} Trip completed"))
        activeTrip = null
    }

    fun cancel() { activeTrip = null }

    fun raiseSOS() {
        val t = activeTrip ?: return
        val line = "${stamp()} SOS raised. Live location + trip record sent to ${emergencyName.ifEmpty { "emergency contact" }}"
        activeTrip = t.copy(status = TripStatus.Sos, events = t.events + line)
        safetyLog.add(0, line)
    }

    fun shareText(t: Trip) = """
        I'm sharing a cab from ${Mock.airport.name} to ${myDest.name}.
        Trip ${t.id} · Cab ${t.cabPlate} · Driver ${t.driverName}
        Co-rider: ${t.match.rider.name} (${t.match.rider.idRef})
    """.trimIndent()

    private fun stamp() = LocalTime.now().format(DateTimeFormatter.ofPattern("h:mm a"))
}
