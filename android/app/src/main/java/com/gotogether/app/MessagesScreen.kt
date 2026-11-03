package com.gotogether.app

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun MessagesScreen(app: AppState, modifier: Modifier = Modifier,
    onChatOpen: (String) -> Unit, onGroupOpen: (String) -> Unit) {
    LaunchedEffect(Unit) { app.fetchMyGroups() }

    LazyColumn(modifier = modifier.padding(horizontal = 12.dp)) {
        if (app.myGroups.isNotEmpty()) {
            item { Text("Groups", fontWeight = FontWeight.Bold, fontSize = 18.sp,
                modifier = Modifier.padding(top = 12.dp, bottom = 8.dp)) }
            items(app.myGroups.toList(), key = { it.id }) { g ->
                ListItem(headlineContent = { Text(g.name, fontWeight = FontWeight.Medium) },
                    supportingContent = { Text(g.memberNames.joinToString(", "), maxLines = 1) },
                    leadingContent = {
                        Icon(Icons.Default.Person, null, Modifier.size(36.dp).clip(RoundedCornerShape(50))
                            .background(Color(0xFF2196F3).copy(alpha = 0.1f)).padding(6.dp),
                            tint = Color(0xFF2196F3))
                    },
                    modifier = Modifier.clickable { onGroupOpen(g.id) })
            }
            if (app.conversations.isNotEmpty()) item { Spacer(Modifier.height(8.dp)) }
        }

        if (app.conversations.isNotEmpty()) {
            item { Text("Direct Messages", fontWeight = FontWeight.Bold, fontSize = 18.sp,
                modifier = Modifier.padding(top = 12.dp, bottom = 8.dp)) }
            items(app.conversations.sortedByDescending { it.lastTs }.toList(), key = { it.peerId }) { c ->
                ListItem(headlineContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(c.peerName, fontWeight = FontWeight.Medium)
                        if (c.ended) {
                            Spacer(Modifier.width(4.dp))
                            Surface(shape = MaterialTheme.shapes.extraSmall, color = Color(0xFFFF9800).copy(alpha = 0.15f)) {
                                Text("Ended", fontSize = 10.sp, color = Color(0xFFFF9800),
                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp))
                            }
                        }
                        if (c.blocked) {
                            Spacer(Modifier.width(4.dp))
                            Surface(shape = MaterialTheme.shapes.extraSmall, color = Color(0xFFF44336).copy(alpha = 0.15f)) {
                                Text("Blocked", fontSize = 10.sp, color = Color(0xFFF44336),
                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp))
                            }
                        }
                    }
                }, supportingContent = { Text(c.lastText.ifEmpty { "No messages" }, maxLines = 1) },
                    leadingContent = {
                        Icon(Icons.Default.Person, null, Modifier.size(36.dp).clip(RoundedCornerShape(50))
                            .background(if (c.blocked) Color.Gray else if (c.ended) Color(0xFFFF9800) else Color(0xFF4CAF50)),
                            tint = Color.White)
                    },
                    modifier = Modifier.clickable { onChatOpen(c.peerId) })
            }
        }

        if (app.myGroups.isEmpty() && app.conversations.isEmpty()) item {
            Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("No messages yet", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Chat with co-riders to see conversations here", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}