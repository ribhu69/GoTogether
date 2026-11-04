package com.gotogether.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Green = Color(0xFF2E7D32)
private val Red = Color(0xFFD32F2F)

@Composable
fun OnboardingScreen(app: AppState, onDone: () -> Unit) {
    var step by remember { mutableIntStateOf(0) }
    var otp by remember { mutableStateOf("") }
    var otpSent by remember { mutableStateOf(false) }
    var serverURL by remember { mutableStateOf(app.api.baseURL) }
    var useServer by remember { mutableStateOf(true) }

    fun canAdvance(): Boolean = when (step) {
        0 -> app.phoneVerified
        1 -> app.idVerified
        2 -> app.emergencyName.isNotBlank() && app.emergencyPhone.isNotBlank()
        3 -> true  // server step — always can proceed
        else -> false
    }

    Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        // Header
        Spacer(Modifier.height(24.dp))
        Text("🚕", fontSize = 48.sp)
        Text("GoTogether", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text("Share cabs. Split fares. Stay safe.", style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(20.dp))

        // Step indicator
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(4) { i ->
                Box(Modifier.weight(1f).height(4.dp).clip(RoundedCornerShape(2.dp))
                    .background(if (i <= step) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant))
            }
        }
        Spacer(Modifier.height(20.dp))

        // Connection status
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(CircleShape)
                .background(if (app.isConnected) Green else if (useServer) Color(0xFFFFA726) else Color.Gray))
            Spacer(Modifier.width(6.dp))
            Text(
                if (app.isConnected) "Connected to server" else if (useServer) "Server: not connected" else "Offline mode",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.height(16.dp))

        // Step content
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (step) {
                0 -> PhoneStep(app, otp, otpSent,
                    onOtpChange = { otp = it },
                    onSendOtp = { otpSent = true },
                    onVerify = {
                        if (otp.isBlank()) return@PhoneStep
                        if (useServer) {
                            app.api.baseURL = serverURL
                            if (!app.isConnected) app.registerWithServer { ok -> if (ok) app.verifyPhoneOnServer(otp) {} }
                            else app.verifyPhoneOnServer(otp) {}
                        } else app.phoneVerified = otp == "123456"
                    })
                1 -> IDStep(app, onVerify = {
                    if (useServer) {
                        if (!app.isConnected) app.registerWithServer { ok -> if (ok) app.verifyIdOnServer(app.idLast4) {} }
                        else app.verifyIdOnServer(app.idLast4) {}
                    } else app.idVerified = app.idLast4.length == 4
                })
                2 -> EmergencyStep(app)
                3 -> ServerStep(app, serverURL, useServer,
                    onServerURLChange = { serverURL = it },
                    onUseServerChange = { useServer = it })
            }
        }

        // Bottom buttons
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            if (step > 0) {
                OutlinedButton(onClick = { step-- }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Back")
                }
            } else Spacer(Modifier.width(1.dp))

            Button(onClick = {
                if (step < 3) step++
                else {
                    // Get Started
                    app.api.baseURL = serverURL
                    if (useServer && !app.isConnected) {
                        app.registerWithServer { ok -> if (ok) onDone() }
                    } else onDone()
                }
            }, enabled = canAdvance()) {
                Text(if (step < 3) "Continue" else "Get Started")
                if (step < 3) Icon(Icons.AutoMirrored.Filled.ArrowForward, null, Modifier.size(18.dp))
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun PhoneStep(app: AppState, otp: String, otpSent: Boolean,
                       onOtpChange: (String) -> Unit, onSendOtp: () -> Unit, onVerify: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Your Identity", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        OutlinedTextField(app.name, { app.name = it }, Modifier.fillMaxWidth(), label = { Text("Full name") }, singleLine = true)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Gender.entries.forEach { g -> FilterChip(app.gender == g, { app.gender = g }, label = { Text(g.label) }) }
        }
        OutlinedTextField(app.phone, { app.phone = it }, Modifier.fillMaxWidth(), label = { Text("Phone number") }, singleLine = true)
        when {
            app.phoneVerified -> Text("✓ Phone verified", color = Green, fontWeight = FontWeight.Medium)
            otpSent -> {
                OutlinedTextField(otp, onOtpChange, Modifier.fillMaxWidth(), label = { Text("OTP (demo: 123456)") }, singleLine = true)
                Button(onClick = onVerify, Modifier.fillMaxWidth()) { Text("Verify OTP") }
                Text("Demo OTP: 123456", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> Button(onClick = onSendOtp, Modifier.fillMaxWidth(), enabled = app.phone.length >= 8) { Text("Send OTP") }
        }
    }
}

@Composable
private fun IDStep(app: AppState, onVerify: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Government ID", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Aadhaar", "Passport", "Driving licence").forEach { t ->
                FilterChip(app.idType == t, { app.idType = t }, label = { Text(t) })
            }
        }
        OutlinedTextField(app.idLast4, { app.idLast4 = it }, Modifier.fillMaxWidth(), label = { Text("Last 4 digits") }, singleLine = true)
        if (app.idVerified) Text("✓ ID verified", color = Green, fontWeight = FontWeight.Medium)
        else Button(onClick = onVerify, Modifier.fillMaxWidth(), enabled = app.phoneVerified) { Text("Verify ID") }
        Text("Demo: any 4 digits pass. Production uses DigiLocker / e-KYC.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun EmergencyStep(app: AppState) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Emergency Contact", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        OutlinedTextField(app.emergencyName, { app.emergencyName = it }, Modifier.fillMaxWidth(), label = { Text("Contact name") }, singleLine = true)
        OutlinedTextField(app.emergencyPhone, { app.emergencyPhone = it }, Modifier.fillMaxWidth(), label = { Text("Contact phone") }, singleLine = true)
        Text("Notified with live trip details if you press SOS.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ServerStep(app: AppState, serverURL: String, useServer: Boolean,
                        onServerURLChange: (String) -> Unit, onUseServerChange: (Boolean) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Server Setup", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        OutlinedTextField(serverURL, onServerURLChange, Modifier.fillMaxWidth(),
            label = { Text("Server URL") }, singleLine = true,
            placeholder = { Text("http://10.0.2.2:8080") })
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("Use server for live matching")
            Switch(checked = useServer, onCheckedChange = onUseServerChange)
        }
        Text("Emulator reaches your Mac at 10.0.2.2:8080", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}