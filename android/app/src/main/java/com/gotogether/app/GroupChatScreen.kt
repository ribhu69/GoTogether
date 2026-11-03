package com.gotogether.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupChatScreen(app: AppState, onBack: () -> Unit) {
    var draft by remember { mutableStateOf("") }
    var replyTarget by remember { mutableStateOf<ChatMessage?>(null) }
    val listState = rememberLazyListState()
    val group = app.myGroups.find { it.id == app.activeGroupId }
    val title = group?.name ?: "Group"

    LaunchedEffect(app.groupMessages.size) {
        if (app.groupMessages.isNotEmpty()) listState.animateScrollToItem(app.groupMessages.size - 1)
    }
    LaunchedEffect(Unit) { while (true) { app.fetchGroupMessages(); delay(500) } }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text(title) }, navigationIcon = {
                IconButton(onClick = { app.closeGroup(); onBack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            })
        },
        bottomBar = {
            Column {
                if (replyTarget != null) Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant).padding(8.dp)) {
                    Box(Modifier.width(3.dp).height(32.dp).background(Color.Blue))
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Replying", color = Color.Blue, fontSize = 11.sp, fontWeight = FontWeight.Medium)
                        Text(replyTarget!!.text, maxLines = 1, fontSize = 12.sp)
                    }
                    IconButton(onClick = { replyTarget = null }) { Icon(Icons.Default.Close, "Dismiss") }
                }
                Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(draft, { draft = it }, Modifier.weight(1f),
                        placeholder = { Text("Message…") }, shape = RoundedCornerShape(20.dp), maxLines = 4)
                    Spacer(Modifier.width(8.dp))
                    IconButton(onClick = {
                        if (draft.isNotBlank()) {
                            app.sendGroupMessage(draft.trim(), replyTarget?.text); draft = ""; replyTarget = null
                        }
                    }, enabled = draft.isNotBlank()) { Icon(Icons.Default.Send, "Send") }
                }
            }
        }
    ) { padding ->
        if (app.isLoadingGroup) Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        } else LazyColumn(state = listState, modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)) {
            items(app.groupMessages.toList(), key = { "${it.ts}_${it.fromUserId}" }) { msg ->
                val senderName = group?.let { g ->
                    val idx = g.memberIds.indexOf(msg.fromUserId)
                    if (idx >= 0 && idx < g.memberNames.size) g.memberNames[idx] else msg.fromUserId.take(8)
                } ?: msg.fromUserId.take(8)
                GroupBubbleRow(msg, senderName, onReply = { replyTarget = msg })
            }
        }
    }
}

@Composable
fun GroupBubbleRow(msg: ChatMessage, senderName: String, onReply: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp),
        horizontalArrangement = if (msg.isFromMe) Arrangement.End else Arrangement.Start) {
        if (!msg.isFromMe) {
            Icon(Icons.Default.Person, null, Modifier.size(28.dp).clip(RoundedCornerShape(50)).background(Color(0xFF4CAF50)), tint = Color.White)
            Spacer(Modifier.width(6.dp))
        }
        Column(horizontalAlignment = if (msg.isFromMe) Alignment.End else Alignment.Start) {
            if (!msg.isFromMe) Text(senderName, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.Blue)
            if (msg.replyToText != null) Row(Modifier.padding(start = 8.dp, top = 4.dp)) {
                Box(Modifier.width(2.dp).height(20.dp).background(if (msg.isFromMe) Color.White.copy(alpha = 0.5f) else Color.Blue))
                Text(msg.replyToText!!, Modifier.padding(start = 4.dp), maxLines = 2, fontSize = 11.sp, color = if (msg.isFromMe) Color.White.copy(alpha = 0.8f) else Color.Gray)
            }
            Text(msg.text, Modifier.background(if (msg.isFromMe) Color.Blue else Color(0xFFE0E0E0), RoundedCornerShape(16.dp))
                .padding(horizontal = 12.dp, vertical = 8.dp), color = if (msg.isFromMe) Color.White else Color.Black)
            Text(formatTs(msg.ts), fontSize = 10.sp, color = Color.Gray, modifier = Modifier.padding(horizontal = 4.dp))
        }
        if (msg.isFromMe) {
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Default.Person, null, Modifier.size(28.dp).clip(RoundedCornerShape(50)).background(Color.Blue), tint = Color.White)
        }
    }
}