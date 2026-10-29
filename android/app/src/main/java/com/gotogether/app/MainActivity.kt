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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Place

class MainActivity : ComponentActivity() {
    private val app: AppState by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Root(app) } }
    }
}

@androidx.compose.runtime.Composable
fun Root(app: AppState) {
    if (!app.onboarded) {
        OnboardingScreen(app)
        return
    }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(bottomBar = {
        NavigationBar {
            listOf("Map" to Icons.Default.Place, "Trip" to Icons.Default.LocationOn, "Safety" to Icons.Default.Lock)
                .forEachIndexed { i, (label, icon) ->
                    NavigationBarItem(selected = tab == i, onClick = { tab = i },
                        icon = { Icon(icon, null) }, label = { Text(label) })
                }
        }
    }) { pad ->
        val m = Modifier.padding(pad)
        when (tab) {
            0 -> MapHomeScreen(app, m, onRequested = { tab = 1 })
            1 -> TripScreen(app, m)
            else -> SafetyScreen(app, m)
        }
    }
}
