package com.gotogether.app

import android.annotation.SuppressLint
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

@SuppressLint("UnusedMaterial3ScaffoldPaddingParameter")
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(app: AppState, onBack: () -> Unit) {
    var draft by remember { mutableStateOf("") }
    var replyTarget by remember { mutableStateOf<ChatMessage?>(null) }
    var showBlockConfirm by remember { mutableStateOf(false) }
    var showEndConfirm by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val conv = app.conversations.find { it.peerId == app.activeChatPeerId }
    val isEnded = conv?.ended == true
    val isBlocked = conv?.blocked == true || app.blockedUserIds.contains(app.activeChatPeerId)

    LaunchedEffect(app.chatMessages.size) {
        if (app.chatMessages.isNotEmpty()) listState.animateScrollToItem(app.chatMessages.size - 1)
    }
    LaunchedEffect(Unit) { while (true) { app.fetchChatMessages(); delay(500) } }

    Scaffold(topBar = {
        TopAppBar(title = { Text("Chat") }, navigationIcon = {
            IconButton(onClick = { app.closeChat(); onBack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        }, actions = {
            var menuExp by remember { mutableStateOf(false) }
            Box {
                IconButton(onClick = { menuExp = true }) { Icon(Icons.Default.MoreVert, "Menu") }
                DropdownMenu(expanded = menuExp, onDismissRequest = { menuExp = false }) {
                    if (isBlocked) DropdownMenuItem(text = { Text("Unblock") },
                        onClick = { app.unblockUser(app.activeChatPeerId); menuExp = false })
                    else DropdownMenuItem(text = { Text("Block", color = MaterialTheme.colorScheme.error) },
                        onClick = { showBlockConfirm = true; menuExp = false })
                    if (!isEnded) DropdownMenuItem(text = { Text("End Chat") },
                        onClick = { showEndConfirm = true; menuExp = false })
                }
            }
        })
    }, bottomBar = {
        Column {
            if (replyTarget != null) {
                Row(modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant).padding(8.dp)) {
                    Box(Modifier.width(3.dp).height(32.dp).background(Color.Blue))
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text(if (replyTarget!!.isFromMe) "Replying to yourself" else "Replying",
                            color = Color.Blue, fontSize = 11.sp, fontWeight = FontWeight.Medium)
                        Text(replyTarget!!.text, maxLines = 1, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    IconButton(onClick = { replyTarget = null }) { Icon(Icons.Default.Close, "Dismiss") }
                }
            }
            if (isEnded) Text("✓ Conversation ended", Modifier.fillMaxWidth().padding(12.dp))
            else if (isBlocked) Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("User blocked", Modifier.weight(1f))
                OutlinedButton(onClick = { app.unblockUser(app.activeChatPeerId) }) { Text("Unblock") }
            } else Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(value = draft, onValueChange = { draft = it }, modifier = Modifier.weight(1f),
                    placeholder = { Text("Message…") }, shape = RoundedCornerShape(20.dp), maxLines = 4)
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = {
                    if (draft.isNotBlank()) { app.sendChatMessage(draft.trim(), replyTarget?.text); draft = ""; replyTarget = null }
                }, enabled = draft.isNotBlank()) { Icon(Icons.Default.Send, "Send") }
            }
        }
    }) { padding ->
        if (app.isLoadingChat) Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        } else LazyColumn(state = listState, modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)) {
            if (app.hasMoreChat) item {
                TextButton(onClick = { app.loadOlderMessages() }, modifier = Modifier.fillMaxWidth()) { Text("Load older") }
            }
            items(app.chatMessages.filter {
                (it.fromUserId == app.activeChatPeerId && it.toUserId == ChatMessage.myUserId) ||
                (it.fromUserId == ChatMessage.myUserId && it.toUserId == app.activeChatPeerId)
            }, key = { it.ts.toString() + it.fromUserId }) { msg ->
                SwipeableChatBubble(msg, onReply = { replyTarget = msg })
            }
        }
    }

    if (showBlockConfirm) AlertDialog(onDismissRequest = { showBlockConfirm = false },
        title = { Text("Block?") }, text = { Text("They won't see you or message you.") },
        confirmButton = { TextButton({ app.blockUser(app.activeChatPeerId); showBlockConfirm = false }) { Text("Block", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ showBlockConfirm = false }) { Text("Cancel") } })
    if (showEndConfirm) AlertDialog(onDismissRequest = { showEndConfirm = false },
        title = { Text("End chat?") }, text = { Text("No more messages.") },
        confirmButton = { TextButton({ app.endChat(app.activeChatPeerId); showEndConfirm = false }) { Text("End", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ showEndConfirm = false }) { Text("Cancel") } })
}

@Composable
fun ChatBubbleRow(msg: ChatMessage, onReply: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
        horizontalArrangement = if (msg.isFromMe) Arrangement.End else Arrangement.Start) {
        if (!msg.isFromMe) {
            Icon(Icons.Default.Person, null, Modifier.size(28.dp).clip(RoundedCornerShape(50)).background(Color(0xFF4CAF50)), tint = Color.White)
            Spacer(Modifier.width(6.dp))
        }
        Column(horizontalAlignment = if (msg.isFromMe) Alignment.End else Alignment.Start) {
            if (msg.replyToText != null) {
                Row(modifier = Modifier.padding(start = 8.dp, top = 4.dp)) {
                    Box(Modifier.width(2.dp).height(20.dp).background(if (msg.isFromMe) Color.White.copy(alpha = 0.5f) else Color.Blue))
                    Text(msg.replyToText!!, Modifier.padding(start = 4.dp), maxLines = 2, fontSize = 11.sp,
                        color = if (msg.isFromMe) Color.White.copy(alpha = 0.8f) else Color.Gray)
                }
            }
            Text(msg.text, modifier = Modifier.background(if (msg.isFromMe) Color.Blue else Color(0xFFE0E0E0), RoundedCornerShape(16.dp))
                .padding(horizontal = 12.dp, vertical = 8.dp), color = if (msg.isFromMe) Color.White else Color.Black)
            Text(formatTs(msg.ts), fontSize = 10.sp, color = Color.Gray, modifier = Modifier.padding(horizontal = 4.dp))
        }
        if (msg.isFromMe) {
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Default.Person, null, Modifier.size(28.dp).clip(RoundedCornerShape(50)).background(Color.Blue), tint = Color.White)
        }
    }
}

@Composable
fun SwipeableChatBubble(msg: ChatMessage, onReply: () -> Unit) {
    var dragX by remember { mutableStateOf(0f) }
    val threshold = 60f * 3f // approximate 60dp in pixels

    Box(Modifier.pointerInput(Unit) {
        detectHorizontalDragGestures(
            onDragEnd = {
                if (dragX >= threshold) onReply()
                dragX = 0f
            },
            onHorizontalDrag = { _, amount -> dragX = (dragX + amount).coerceIn(0f, threshold * 2f) }
        )
    }) {
        ChatBubbleRow(msg, onReply = {})
    }
}

fun formatTs(ts: Double): String {
    val sdf = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
    return sdf.format(java.util.Date((ts * 1000).toLong()))
}