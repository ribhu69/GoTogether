package com.gotogether.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.MailOutline

class MainActivity : ComponentActivity() {
    private val app: AppState by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Root(app) } }
    }
}

@androidx.compose.runtime.Composable
fun Root(app: AppState) {
    var onboardingDone by remember { mutableStateOf(false) }

    if (!app.onboarded && !onboardingDone) {
        OnboardingScreen(app, onDone = { onboardingDone = true })
        return
    }

    // Auto-connect after onboarding
    LaunchedEffect(Unit) { app.autoConnect() }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var chatPeer by remember { mutableStateOf<String?>(null) }
    var groupId by remember { mutableStateOf<String?>(null) }

    if (chatPeer != null) ChatScreen(app) { chatPeer = null }
    else if (groupId != null) GroupChatScreen(app) { groupId = null }
    else Scaffold(bottomBar = {
        NavigationBar {
            val tabs = listOf("Map" to Icons.Default.Place, "Messages" to Icons.Default.MailOutline,
                "Trip" to Icons.Default.LocationOn, "Safety" to Icons.Default.Lock)
            tabs.forEachIndexed { i, (label, icon) ->
                NavigationBarItem(selected = tab == i, onClick = { tab = i },
                    icon = { Icon(icon, null) }, label = { Text(label) })
            }
        }
    }) { pad ->
        val m = Modifier.padding(pad)
        when (tab) {
            0 -> MapHomeScreen(app, m, onRequested = { tab = 2 })
            1 -> MessagesScreen(app, m, onChatOpen = { app.openChat(it); chatPeer = it },
                onGroupOpen = { app.openGroup(it); groupId = it })
            2 -> TripScreen(app, m)
            else -> SafetyScreen(app, m)
        }
    }
}
