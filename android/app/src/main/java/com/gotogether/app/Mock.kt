package com.gotogether.app

object Mock {
    val airport = Place("BLR", "Kempegowda Airport (BLR)", 13.1986, 77.7066)

    // Satellite points near the airport so "open" users cluster around it visually.
    val airportEdge = Place("BLR-edge", "Airport pickup lane", 13.2000, 77.7080)
    val airportSouth = Place("BLR-south", "Airport south exit", 13.1960, 77.7050)

    val places = listOf(
        airport,
        Place("hebbal", "Hebbal", 13.0358, 77.5970),
        Place("mg", "MG Road", 12.9756, 77.6068),
        Place("indira", "Indiranagar", 12.9784, 77.6408),
        Place("kora", "Koramangala", 12.9352, 77.6245),
        Place("hsr", "HSR Layout", 12.9116, 77.6474),
        Place("white", "Whitefield", 12.9698, 77.7500),
        Place("marath", "Marathahalli", 12.9569, 77.7011),
        Place("ecity", "Electronic City", 12.8452, 77.6602),
        Place("yelah", "Yelahanka", 13.1007, 77.5963),
        Place("malle", "Malleshwaram", 13.0035, 77.5647),
        Place("jaya", "Jayanagar", 12.9250, 77.5938),
    )

    private fun p(id: String) = places.first { it.id == id }

    fun riders(nowMs: Long = System.currentTimeMillis()): List<Rider> {
        fun r(n: String, g: Gender, rt: Double, t: Int, v: Boolean, ref: String, d: String, off: Int) =
            Rider(n, n, g, rt, t, v, ref, p(d), nowMs + off * 60_000L)
        return listOf(
            r("Priya S.", Gender.Female, 4.9, 42, true, "AADHAAR ••••4821", "indira", 12),
            r("Rahul M.", Gender.Male, 4.7, 18, true, "PASSPORT ••••7710", "mg", 20),
            r("Ananya R.", Gender.Female, 4.8, 31, true, "DL ••••2093", "hebbal", 8),
            r("Vikram T.", Gender.Male, 4.5, 9, true, "AADHAAR ••••3356", "marath", 25),
            r("Sneha P.", Gender.Female, 4.6, 5, false, "UNVERIFIED", "kora", 18),
            r("Karthik N.", Gender.Male, 4.9, 77, true, "PASSPORT ••••1188", "white", 35),
            r("Meera D.", Gender.Female, 4.8, 24, true, "AADHAAR ••••9042", "yelah", 15),
            r("Arjun B.", Gender.Male, 4.4, 12, true, "DL ••••6617", "ecity", 22),
            r("Divya L.", Gender.Female, 4.7, 16, true, "AADHAAR ••••5530", "malle", 60),
        )
    }

    /// People who are "open to travel" right now from near the airport.
    fun openIntents(nowMs: Long = System.currentTimeMillis()): List<TravelIntent> {
        val riders = riders(nowMs)
        val origins = listOf(airportEdge, airportSouth)
        val radii = listOf(3.0, 5.0, 7.0, 4.0, 6.0, 5.0, 3.0, 7.0, 5.0)
        return riders.zip(radii).mapIndexed { i, (r, rad) ->
            TravelIntent(r.id, r, origins[i % 2], rad, true, nowMs + 120 * 60_000)
        }
    }
}
