package com.gotogether.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

private val Green = Color(0xFF2E7D32)

@Composable
fun OnboardingScreen(app: AppState) {
    var otp by remember { mutableStateOf("") }
    var otpSent by remember { mutableStateOf(false) }
    var serverURL by remember { mutableStateOf(app.api.baseURL) }
    var useServer by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Welcome to GoTogether", style = MaterialTheme.typography.headlineMedium)

        // Server section
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Server (optional)", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                OutlinedTextField(serverURL, { serverURL = it }, label = { Text("http://10.0.2.2:8080") }, modifier = Modifier.fillMaxWidth())
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Use server for live matching")
                    Switch(checked = useServer, onCheckedChange = { useServer = it })
                }
                if (app.isConnected) {
                    Text("✓ Connected as ${app.api.userId?.take(8) ?: ""}…", color = Green)
                }
            }
        }

        // 1. Phone
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("1 · Phone", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                OutlinedTextField(app.name, { app.name = it }, label = { Text("Full name") }, modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Gender.entries.forEach { g ->
                        FilterChip(app.gender == g, { app.gender = g }, label = { Text(g.label) })
                    }
                }
                OutlinedTextField(app.phone, { app.phone = it }, label = { Text("Phone number") }, modifier = Modifier.fillMaxWidth())
                when {
                    app.phoneVerified -> Text("✓ Phone verified", color = Green)
                    otpSent -> {
                        OutlinedTextField(otp, { otp = it }, label = { Text("OTP (demo: 123456)") }, modifier = Modifier.fillMaxWidth())
                        Button({
                            if (useServer) scope.launch { app.api.baseURL = serverURL; app.verifyPhoneOnServer(otp) {} }
                            else app.phoneVerified = otp == "123456"
                        }) { Text("Verify OTP") }
                    }
                    else -> Button({ otpSent = true }, enabled = app.phone.length >= 8) { Text("Send OTP") }
                }
            }
        }

        // 2. ID
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("2 · Government ID", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("Aadhaar", "Passport", "Driving licence").forEach { t ->
                        FilterChip(app.idType == t, { app.idType = t }, label = { Text(t) })
                    }
                }
                OutlinedTextField(app.idLast4, { app.idLast4 = it }, label = { Text("Last 4 digits") }, modifier = Modifier.fillMaxWidth())
                if (app.idVerified) Text("✓ ID + selfie verified", color = Green)
                else Button({
                    if (useServer) scope.launch { app.verifyIdOnServer(app.idLast4) {} }
                    else app.idVerified = app.idLast4.length == 4
                }, enabled = app.phoneVerified) { Text("Simulate ID + selfie check") }
                Text("Demo only. Production: DigiLocker / e-KYC plus liveness selfie.", style = MaterialTheme.typography.bodySmall)
            }
        }

        // 3. Emergency
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("3 · Emergency contact", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                OutlinedTextField(app.emergencyName, { app.emergencyName = it }, label = { Text("Contact name") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(app.emergencyPhone, { app.emergencyPhone = it }, label = { Text("Contact phone") }, modifier = Modifier.fillMaxWidth())
                Text("Notified with live trip details if you press SOS.", style = MaterialTheme.typography.bodySmall)
            }
        }

        // Register with server
        if (useServer && app.phoneVerified && app.idVerified && app.name.isNotEmpty() && app.emergencyPhone.isNotEmpty() && !app.isConnected) {
            Button({
                app.api.baseURL = serverURL
                app.registerWithServer { ok -> if (!ok) { /* retry */ } }
            }, Modifier.fillMaxWidth()) { Text("Register on server") }
        }
    }
}
