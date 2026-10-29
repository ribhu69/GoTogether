package com.gotogether.app

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

// Data classes matching server JSON

data class ServerUser(
    val userId: String, val name: String, val phone: String, val gender: String,
    val idType: String, val idLast4: String, val emergencyName: String, val emergencyPhone: String,
    val phoneVerified: Boolean, val idVerified: Boolean,
)

data class ServerCoord(val lat: Double, val lon: Double, val name: String?)

data class ServerIntent(
    val intentId: String, val userId: String, val userName: String, val userGender: String,
    val idVerified: Boolean, val idRef: String, val rating: Double, val trips: Int,
    val origin: ServerCoord, val dest: ServerCoord,
    val comfortRadiusKm: Double, val isOpen: Boolean,
    val originGapKm: Double?, val destGapKm: Double?,
)

data class ServerMatch(
    val matchId: String, val fromUserId: String, val fromUserName: String,
    val toUserId: String, val toUserName: String, val toIntentId: String,
    val destGapKm: Double?, var status: String,
    val cabPlate: String?, val pin: String?, val driverName: String?,
)

class ApiClient(var baseURL: String = "http://10.0.2.2:8080") {
    var userId: String? = null

    // Helpers
    private suspend fun post(path: String, body: JSONObject): JSONObject = withContext(Dispatchers.IO) {
        val url = URL("$baseURL$path")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/json")
        conn.doOutput = true
        OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }
        readResponse(conn)
    }

    private suspend fun get(path: String): JSONObject = withContext(Dispatchers.IO) {
        val conn = (URL("$baseURL$path").openConnection() as HttpURLConnection).apply { requestMethod = "GET" }
        readResponse(conn)
    }

    private fun readResponse(conn: HttpURLConnection): JSONObject {
        val text = if (conn.responseCode in 200..299) {
            BufferedReader(InputStreamReader(conn.inputStream)).readText()
        } else {
            BufferedReader(InputStreamReader(conn.errorStream)).readText()
        }
        return JSONObject(text)
    }

    // Endpoints

    suspend fun register(
        name: String, phone: String, gender: String, idType: String, idLast4: String,
        emergencyName: String, emergencyPhone: String,
    ): ServerUser {
        val r = post("/api/register", JSONObject().apply {
            put("name", name); put("phone", phone); put("gender", gender)
            put("idType", idType); put("idLast4", idLast4)
            put("emergencyName", emergencyName); put("emergencyPhone", emergencyPhone)
        })
        userId = r.getString("userId")
        return parseUser(r)
    }

    suspend fun verifyPhone(otp: String): ServerUser {
        val r = post("/api/verify", JSONObject().apply {
            put("userId", userId); put("type", "phone"); put("otp", otp)
        })
        return parseUser(r)
    }

    suspend fun verifyId(idLast4: String): ServerUser {
        val r = post("/api/verify", JSONObject().apply {
            put("userId", userId); put("type", "id"); put("idLast4", idLast4)
        })
        return parseUser(r)
    }

    suspend fun upsertIntent(origin: Place, dest: Place, comfortKm: Double, isOpen: Boolean): List<ServerIntent> {
        val r = post("/api/intent", JSONObject().apply {
            put("userId", userId)
            put("origin", JSONObject().apply { put("lat", origin.lat); put("lon", origin.lon); put("name", origin.name) })
            put("dest", JSONObject().apply { put("lat", dest.lat); put("lon", dest.lon); put("name", dest.name) })
            put("comfortRadiusKm", comfortKm); put("isOpen", isOpen)
        })
        return parseIntentArray(r.getJSONArray("compatible"))
    }

    suspend fun searchIntents(
        origin: Place, dest: Place, comfortKm: Double,
        verifiedOnly: Boolean, sameGender: Boolean,
    ): List<ServerIntent> {
        val r = get("/api/intents?userId=$userId" +
            "&lat=${origin.lat}&lon=${origin.lon}" +
            "&destLat=${dest.lat}&destLon=${dest.lon}" +
            "&comfortKm=$comfortKm" +
            "&verifiedOnly=$verifiedOnly&sameGender=$sameGender")
        return parseIntentArray(r.getJSONArray("intents"))
    }

    suspend fun requestMatch(toIntentId: String): ServerMatch {
        val r = post("/api/match/request", JSONObject().apply {
            put("fromUserId", userId); put("toIntentId", toIntentId)
        })
        return parseMatch(r)
    }

    suspend fun pendingMatches(): List<ServerMatch> {
        val r = get("/api/match/pending?userId=$userId")
        return parseMatchArray(r.getJSONArray("matches"))
    }

    suspend fun respondToMatch(matchId: String, accept: Boolean): ServerMatch {
        val r = post("/api/match/respond", JSONObject().apply {
            put("matchId", matchId); put("userId", userId); put("accept", accept)
        })
        return parseMatch(r)
    }

    // Bridge helpers
    fun toTravelIntent(si: ServerIntent): TravelIntent {
        val rider = Rider(
            id = si.intentId, name = si.userName, gender = when (si.userGender) {
                "female" -> Gender.Female; "male" -> Gender.Male; else -> Gender.Other
            },
            rating = si.rating, trips = si.trips,
            idVerified = si.idVerified, idRef = si.idRef,
            destination = Place(si.dest.name ?: "", si.dest.name ?: "", si.dest.lat, si.dest.lon),
            departAtMs = System.currentTimeMillis(),
        )
        return TravelIntent(
            id = si.intentId, rider = rider,
            origin = Place(si.origin.name ?: "", si.origin.name ?: "", si.origin.lat, si.origin.lon),
            comfortRadiusKm = si.comfortRadiusKm, isOpen = si.isOpen,
            openUntilMs = System.currentTimeMillis() + 3600_000,
        )
    }

    // JSON parsers
    private fun parseUser(j: JSONObject) = ServerUser(
        j.getString("userId"), j.getString("name"), j.getString("phone"), j.getString("gender"),
        j.optString("idType"), j.optString("idLast4"),
        j.optString("emergencyName"), j.optString("emergencyPhone"),
        j.getBoolean("phoneVerified"), j.getBoolean("idVerified"),
    )

    private fun parseIntentArray(a: JSONArray): List<ServerIntent> =
        (0 until a.length()).map { parseIntent(a.getJSONObject(it)) }

    private fun parseIntent(j: JSONObject) = ServerIntent(
        j.getString("intentId"), j.getString("userId"), j.getString("userName"), j.getString("userGender"),
        j.getBoolean("idVerified"), j.getString("idRef"), j.getDouble("rating"), j.getInt("trips"),
        parseCoord(j.getJSONObject("origin")), parseCoord(j.getJSONObject("dest")),
        j.getDouble("comfortRadiusKm"), j.getBoolean("isOpen"),
        j.optDouble("originGapKm").takeIf { !j.isNull("originGapKm") },
        j.optDouble("destGapKm").takeIf { !j.isNull("destGapKm") },
    )

    private fun parseCoord(j: JSONObject) = ServerCoord(j.getDouble("lat"), j.getDouble("lon"), j.optString("name", null))

    private fun parseMatchArray(a: JSONArray): List<ServerMatch> =
        (0 until a.length()).map { parseMatch(a.getJSONObject(it)) }

    private fun parseMatch(j: JSONObject) = ServerMatch(
        j.getString("matchId"), j.getString("fromUserId"), j.getString("fromUserName"),
        j.getString("toUserId"), j.getString("toUserName"), j.getString("toIntentId"),
        j.optDouble("destGapKm").takeIf { !j.isNull("destGapKm") }, j.getString("status"),
        j.optString("cabPlate", null), j.optString("pin", null), j.optString("driverName", null),
    )
}
