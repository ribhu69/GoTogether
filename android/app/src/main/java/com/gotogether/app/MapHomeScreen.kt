package com.gotogether.app

import android.content.Context
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.OvalShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.preference.PreferenceManager
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polygon
import org.osmdroid.views.overlay.Polyline
import kotlin.math.cos
import kotlin.math.sin

private val Green = Color(0xFF2E7D32)
private const val ORIGIN_SPAN_KM = 0.5

// ---------- osmdroid wrapper ----------

@Composable
fun OsmMap(
    modifier: Modifier,
    center: GeoPoint,
    zoom: Double = 12.0,
    onMapReady: (MapView) -> Unit = {},
    update: (MapView) -> Unit = {},
) {
    val ctx = LocalContext.current
    val mapView = remember {
        Configuration.getInstance().load(ctx, PreferenceManager.getDefaultSharedPreferences(ctx))
        Configuration.getInstance().userAgentValue = "GoTogether/0.2"
        MapView(ctx).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            setBuiltInZoomControls(false)
            controller.setZoom(zoom)
            controller.setCenter(center)
            onMapReady(this)
        }
    }

    DisposableEffect(Unit) {
        mapView.onResume()
        onDispose { mapView.onDetach() }
    }

    LaunchedEffect(Unit) { update(mapView); mapView.invalidate() }
    // Run update on each recomposition — caller should keep update lambda stable with keys.
    update(mapView)

    AndroidView(modifier = modifier, factory = { mapView }, update = { update(it); it.invalidate() })
}

// ---------- circle overlay (osmdroid doesn't ship one) ----------

private fun drawCirclePoly(center: GeoPoint, radiusM: Double, fillColor: Int, strokeColor: Int, strokeWidth: Float): Polygon {
    val p = Polygon()
    p.points = Polygon.pointsAsCircle(center, radiusM)
    p.fillPaint.color = fillColor
    p.outlinePaint.color = strokeColor
    p.outlinePaint.strokeWidth = strokeWidth
    return p
}

private fun marker(map: MapView, pt: GeoPoint, title: String, snippet: String, colorArgb: Int, onClick: (() -> Unit)? = null): Marker {
    val m = Marker(map)
    m.position = pt
    m.title = title
    m.snippet = snippet
    m.setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
    val dot = ShapeDrawable(OvalShape())
    dot.paint.color = colorArgb
    dot.intrinsicWidth = 32; dot.intrinsicHeight = 32
    m.icon = dot
    onClick?.let { m.setOnMarkerClickListener { _, _ -> it(); true } }
    return m
}

// ---------- Map home screen ----------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapHomeScreen(app: AppState, modifier: Modifier, onRequested: () -> Unit) {
    val ctx = LocalContext.current
    var showSheet by remember { mutableStateOf(false) }
    var sheetTab by rememberSaveable { mutableIntStateOf(0) }
    var menuExpanded by remember { mutableStateOf(false) }
    var tappedIntent by remember { mutableStateOf<TravelIntent?>(null) }

    // Server integration
    LaunchedEffect(Unit) { app.refreshIntents() }
    LaunchedEffect(app.search.verifiedOnly, app.search.sameGenderOnly) { app.refreshIntents() }
    LaunchedEffect(app.myDest, app.myComfortKm, app.iAmOpen) { app.syncIntent() }
    LaunchedEffect(Unit) {
        while (true) { app.pollPending(); kotlinx.coroutines.delay(4000) }
    }

    // State changes trigger recomposition → map updates.
    OsmMap(
        modifier = modifier.fillMaxSize(),
        center = app.myOrigin.geoPoint,
        zoom = 12.0,
        onMapReady = { },
        update = { mv ->
            mv.overlays.clear()

            // Origin circle (who "near me" means)
            mv.overlays.add(drawCirclePoly(app.myOrigin.geoPoint, ORIGIN_SPAN_KM * 1000,
                0x1487CEEB, 0x4487CEEB, 2f))

            // Destination radius circle
            mv.overlays.add(drawCirclePoly(app.myDest.geoPoint, app.myComfortKm * 1000,
                0x18FFA500, 0x66FFA500, 2f))

            // My origin marker
            mv.overlays.add(marker(mv, app.myOrigin.geoPoint, "You", "Origin", 0xFF1976D2.toInt()))

            // My destination marker
            mv.overlays.add(marker(mv, app.myDest.geoPoint, app.myDest.name, "Your destination", 0xFFD32F2F.toInt()))

            // Open intents nearby
            val intents = app.openIntents().filter { Geo.km(app.myOrigin, it.origin) <= ORIGIN_SPAN_KM }
            for (i in intents) {
                mv.overlays.add(marker(mv, i.origin.geoPoint, i.rider.name,
                    "${i.rider.destination.name} · ${"%.1f".format(i.comfortRadiusKm)}km comfort",
                    0xFF43A047.toInt()) { tappedIntent = i })

                // Polyline from origin to destination
                val pl = Polyline()
                pl.setPoints(listOf(i.origin.geoPoint, i.rider.destination.geoPoint))
                pl.outlinePaint.color = 0x5943A047
                pl.outlinePaint.strokeWidth = 3f
                mv.overlays.add(pl)
            }

            mv.invalidate()
        },
    )

    // Bottom card
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Card(
            Modifier.fillMaxWidth().padding(12.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
        ) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Column {
                        Text("To: ${app.myDest.name}", style = MaterialTheme.typography.titleSmall)
                        if (app.isConnected) Text("● connected", style = MaterialTheme.typography.labelSmall, color = Green)
                        Text("Comfort: ${app.myComfortKm.toInt()} km · ${app.openIntents().count { Geo.km(app.myOrigin, it.origin) <= ORIGIN_SPAN_KM }} nearby",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Open", style = MaterialTheme.typography.labelSmall)
                        Switch(checked = app.iAmOpen, onCheckedChange = { app.iAmOpen = it })
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton({ menuExpanded = true }, Modifier.weight(1f)) { Text(app.myDest.name, maxLines = 1) }
                    DropdownMenu(menuExpanded, { menuExpanded = false }) {
                        Mock.places.filter { it.id != "BLR" }.forEach { p ->
                            DropdownMenuItem(text = { Text(p.name) }, onClick = { app.myDest = p; menuExpanded = false })
                        }
                    }
                    Button({ showSheet = true }, Modifier.weight(1f)) { Text("Find") }
                }
            }
        }
    }

    // Bottom sheet
    if (showSheet) {
        ModalBottomSheet(onDismissRequest = { showSheet = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            MapSheetContent(app, sheetTab, { sheetTab = it }, { showSheet = false; onRequested() })
        }
    }

    // Intent detail dialog
    tappedIntent?.let { i ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { tappedIntent = null },
            title = { Text(i.rider.name) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("ID: ${i.rider.idRef}")
                    Text("Going to: ${i.rider.destination.name}")
                    Text("Comfort range: ${i.comfortRadiusKm.toInt()} km")
                    Text("★ ${"%.1f".format(i.rider.rating)} · ${i.rider.trips} trips")
                    Text("Your dest gap: ${"%.1f".format(Geo.km(app.myDest, i.rider.destination))} km")
                    Text("Est. your fare: ₹${Fare.shared(app.myDest, i.rider.destination).toInt()}")
                }
            },
            confirmButton = { TextButton({ app.requestIntent(i); tappedIntent = null; onRequested() }) { Text("Share ride") } },
            dismissButton = { TextButton({ tappedIntent = null }) { Text("Close") } },
        )
    }
}

@Composable
private fun MapSheetContent(app: AppState, tab: Int, onTab: (Int) -> Unit, onDone: () -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Classic Search" to 0, "Nearby Open" to 1).forEach { (label, ix) ->
                FilterChip(tab == ix, { onTab(ix) }, label = { Text(label) }, modifier = Modifier.weight(1f))
            }
        }
        when (tab) {
            0 -> ClassicSearchTab(app, onDone)
            1 -> OpenIntentsTab(app, onDone)
        }
    }
}

@Composable
private fun ClassicSearchTab(app: AppState, onDone: () -> Unit) {
    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Comfort range (how far from your destination are you OK?)", style = MaterialTheme.typography.labelMedium)
        Text("${app.myComfortKm.toInt()} km", style = MaterialTheme.typography.headlineSmall, color = Color(0xFFFF8F00))
        Slider(app.myComfortKm.toFloat(), { app.myComfortKm = it.toDouble() }, valueRange = 1f..10f, steps = 8)
        Text("You'll be shown to people whose destination is within this radius.", style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("Verified only"); Switch(checked = app.search.verifiedOnly, onCheckedChange = { app.search = app.search.copy(verifiedOnly = it) }) }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("Same gender"); Switch(checked = app.search.sameGenderOnly, onCheckedChange = { app.search = app.search.copy(sameGenderOnly = it) }) }
        Spacer(Modifier.height(8.dp))
        val matches = app.matches()
        Button(onDone) { Text("View classic matches (${matches.size})") }
    }
}

@Composable
private fun OpenIntentsTab(app: AppState, onDone: () -> Unit) {
    val hits = app.matchingOpenIntents()
    val pending = app.serverPending

    if (hits.isEmpty() && pending.isEmpty()) {
        Text("No open travelers match. Try a wider comfort radius or fewer filters.")
    } else {
        // Incoming match requests from server
        if (pending.isNotEmpty()) {
            Text("📲 Incoming match requests", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            LazyColumn(Modifier.height(150.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(pending, key = { it.matchId }) { sm ->
                    Card(Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(sm.fromUserName, style = MaterialTheme.typography.titleSmall)
                                Text("Wants to share · ~${"%.1f".format(sm.destGapKm ?: 0.0)} km",
                                    style = MaterialTheme.typography.bodySmall)
                            }
                            Button({
                                app.acceptServerMatch(sm)
                                onDone()
                            }, enabled = app.activeTrip == null) { Text("Accept") }
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
        }
        if (hits.isNotEmpty()) {
            Text("${hits.size} people would be notified", style = MaterialTheme.typography.titleMedium)
            Text("These users marked themselves Open near your origin and their destination falls within your ${app.myComfortKm.toInt()} km radius.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            LazyColumn(Modifier.height(200.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(hits, key = { it.id }) { i ->
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(i.rider.name, style = MaterialTheme.typography.titleSmall)
                            Text("→ ${i.rider.destination.name} · ${"%.1f".format(Geo.km(app.myDest, i.rider.destination))} km",
                                style = MaterialTheme.typography.bodySmall)
                            Text("Comfort: ${i.comfortRadiusKm.toInt()} km · ★ ${"%.1f".format(i.rider.rating)}",
                                style = MaterialTheme.typography.bodySmall)
                        }
                        Button({ app.requestIntent(i); onDone() }, enabled = app.activeTrip == null) { Text("Share") }
                    }
                }
            }
        }
    }
}
    }
