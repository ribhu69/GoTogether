package com.gotogether.app

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

// Helpers used by TripScreen and SafetyScreen

@Composable
internal fun Page(modifier: Modifier = Modifier, title: String, content: @Composable () -> Unit) {
    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, style = MaterialTheme.typography.headlineMedium)
        content()
    }
}

@Composable
internal fun Section(title: String, content: @Composable () -> Unit) {
    Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { content() } }
}

@Composable
internal fun KV(k: String, v: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(k, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(v)
    }
}

// --- Trip ---

@Composable
fun TripScreen(app: AppState, modifier: Modifier) {
    val ctx = LocalContext.current
    var confirmSos by remember { mutableStateOf(false) }
    val t = app.activeTrip
    Page(modifier, "Trip") {
        if (t == null) {
            if (app.history.isEmpty()) Text("No active trip. Find a co-rider to start.")
            app.history.forEach { h -> Section("${h.id} · ${h.match.rider.name}") { h.events.forEach { Text(it, style = MaterialTheme.typography.bodySmall) } } }
            return@Page
        }
        Section("Status") {
            KV("Status", t.status.label); KV("Trip ID", t.id)
            KV("Co-rider", t.match.rider.name); KV("Your fare", "₹${t.match.sharedFare}")
        }
        if (t.status != TripStatus.Requested) {
            Section("Boarding") { KV("Cab", t.cabPlate); KV("Driver", t.driverName); KV("Trip PIN", t.pin) }
            Section("Safety") {
                OutlinedButton({
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, app.shareText(t))
                    ctx.startActivity(Intent.createChooser(send, "Share trip"))
                }, Modifier.fillMaxWidth()) { Text("Share trip with a friend") }
                Button({ confirmSos = true }, Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text("SOS") }
            }
            Button(app::complete, Modifier.fillMaxWidth()) { Text("Complete trip") }
            TextButton(app::cancel) { Text("Cancel trip") }
        }
        Section("Log") { t.events.forEach { Text(it, style = MaterialTheme.typography.bodySmall) } }
    }
    if (confirmSos) AlertDialog(
        onDismissRequest = { confirmSos = false },
        title = { Text("Raise SOS?") },
        text = { Text("Your emergency contact gets live trip details, co-rider ID and cab plate.") },
        confirmButton = {
            TextButton({
                confirmSos = false
                app.raiseSOS()
                ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:112")))
            }) { Text("Alert contact & call 112") }
        },
        dismissButton = { TextButton({ confirmSos = false }) { Text("Cancel") } },
    )
}

// --- Safety ---

@Composable
fun SafetyScreen(app: AppState, modifier: Modifier) {
    Page(modifier, "Safety") {
        Section("You") {
            KV("Name", app.name); KV("Phone", if (app.phoneVerified) "Verified" else "—")
            KV("ID", "${app.idType} ••••${app.idLast4}"); KV("Emergency", "${app.emergencyName} ${app.emergencyPhone}")
        }
        Section("How we keep you traceable") {
            Text("• Every rider is ID + selfie verified")
            Text("• Each trip is logged with both riders, cab plate and driver")
            Text("• PIN check before boarding")
            Text("• One-tap SOS: alerts contact and dials 112")
        }
        Section("SOS history") {
            if (app.safetyLog.isEmpty()) Text("None")
            app.safetyLog.forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
        }
    }
}