package com.gotogether.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class AppState : ViewModel() {
    val api = ApiClient()

    // Profile / trust
    var name by mutableStateOf("")
    var phone by mutableStateOf("")
    var gender by mutableStateOf(Gender.Female)
    var phoneVerified by mutableStateOf(false)
    var idVerified by mutableStateOf(false)
    var idType by mutableStateOf("Aadhaar")
    var idLast4 by mutableStateOf("")
    var emergencyName by mutableStateOf("")
    var emergencyPhone by mutableStateOf("")

    val onboarded get() = phoneVerified && idVerified && name.isNotEmpty() && emergencyPhone.isNotEmpty()

    // My travel intent
    var myOrigin by mutableStateOf(Mock.airport)
    var myDest by mutableStateOf(Mock.places.first { it.id != "BLR" })
    var myComfortKm by mutableStateOf(5.0)
    var iAmOpen by mutableStateOf(false)

    // Trips
    var search by mutableStateOf(SearchQuery())
    var activeTrip by mutableStateOf<Trip?>(null)
    val history = mutableStateListOf<Trip>()
    val safetyLog = mutableStateListOf<String>()

    // Server state
    var serverIntents by mutableStateOf<List<ServerIntent>>(emptyList())
    var serverCompatible by mutableStateOf<List<ServerIntent>>(emptyList())
    var serverPending by mutableStateOf<List<ServerMatch>>(emptyList())

    val isConnected get() = api.userId != null

    // Chat
    val chatMessages = mutableStateListOf<ChatMessage>()
    var activeChatPeerId by mutableStateOf("")
    val unreadChats = mutableStateListOf<String>()
    val conversations = mutableStateListOf<InboxConv>()
    val blockedUserIds = mutableStateListOf<String>()
    var isLoadingChat by mutableStateOf(false)
    var hasMoreChat by mutableStateOf(false)
    private val chatPageSize = 20
    private val lastChatPoll = mutableMapOf<String, Double>()

    // Groups
    val myGroups = mutableStateListOf<GroupInfo>()
    var activeGroupId by mutableStateOf("")
    val groupMessages = mutableStateListOf<ChatMessage>()
    var lastGroupPoll by mutableStateOf(0.0)
    var isLoadingGroup by mutableStateOf(false)
    var hasMoreGroup by mutableStateOf(false)

    data class InboxConv(
        val peerId: String, val peerName: String, val lastText: String,
        val lastTs: Double, var unread: Boolean, var ended: Boolean, var blocked: Boolean,
    )

    data class GroupInfo(
        val id: String, val name: String,
        val memberIds: List<String>, val memberNames: List<String>,
    )

    // ── Registration (server) ──

    fun registerWithServer(onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            try {
                val u = api.register(name, phone, gender.label.lowercase(), idType, idLast4, emergencyName, emergencyPhone)
                phoneVerified = u.phoneVerified; idVerified = u.idVerified
                onResult(true)
            } catch (_: Exception) { onResult(false) }
        }
    }

    fun verifyPhoneOnServer(otp: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            try { val u = api.verifyPhone(otp); phoneVerified = u.phoneVerified; onResult(true) }
            catch (_: Exception) { onResult(false) }
        }
    }

    fun verifyIdOnServer(last4: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            try { val u = api.verifyId(last4); idVerified = u.idVerified; onResult(true) }
            catch (_: Exception) { onResult(false) }
        }
    }

    // ── Intent sync ──

    fun syncIntent() {
        if (!isConnected) return
        viewModelScope.launch {
            try { serverCompatible = api.upsertIntent(myOrigin, myDest, myComfortKm, iAmOpen) }
            catch (_: Exception) {}
        }
    }

    fun refreshIntents() {
        if (!isConnected) return
        viewModelScope.launch {
            try {
                serverIntents = api.searchIntents(myOrigin, myDest, myComfortKm,
                    search.verifiedOnly, search.sameGenderOnly)
            } catch (_: Exception) {}
        }
    }

    fun pollPending() {
        if (!isConnected) return
        viewModelScope.launch {
            try { serverPending = api.pendingMatches() } catch (_: Exception) {}
        }
    }

    // ── Intents (server-first, Mock fallback) ──

    fun openIntents(): List<TravelIntent> {
        if (isConnected && serverIntents.isNotEmpty()) return serverIntents.map(api::toTravelIntent)
        return Mock.openIntents()
    }

    fun matchingOpenIntents(): List<TravelIntent> {
        if (isConnected && serverIntents.isNotEmpty()) return serverIntents.map(api::toTravelIntent)
        return MatchingEngine.findOpen(myOrigin, myDest, myComfortKm, Mock.openIntents(), gender,
            verifiedOnly = search.verifiedOnly, sameGenderOnly = search.sameGenderOnly)
    }

    fun matches() = MatchingEngine.find(search, Mock.riders(), gender)

    // ── Trip actions ──

    fun request(m: Match) {
        val t = Trip(m, events = listOf("${stamp()} Requested share with ${m.rider.name} (${m.rider.idRef})"))
        activeTrip = t
        viewModelScope.launch {
            delay(2000)
            val cur = activeTrip ?: return@launch
            if (cur.id != t.id) return@launch
            activeTrip = cur.copy(
                status = TripStatus.Confirmed,
                events = cur.events + "${stamp()} ${m.rider.name} accepted. Cab ${t.cabPlate}, PIN ${t.pin}",
            )
        }
    }

    fun requestIntent(i: TravelIntent) {
        if (isConnected) {
            val si = serverIntents.find { it.intentId == i.id || it.userName == i.rider.name }
            if (si != null) {
                viewModelScope.launch {
                    try {
                        val m = api.requestMatch(si.intentId)
                        val match = Match(i.rider, m.destGapKm ?: Geo.km(myDest, i.rider.destination), 0,
                            Fare.solo(myDest).roundToInt(), Fare.shared(myDest, i.rider.destination).roundToInt())
                        request(match)
                    } catch (_: Exception) {}
                }
                return
            }
        }
        val m = Match(i.rider, Geo.km(myDest, i.rider.destination), 0,
            Fare.solo(myDest).roundToInt(), Fare.shared(myDest, i.rider.destination).roundToInt())
        request(m)
    }

    fun acceptServerMatch(sm: ServerMatch) {
        viewModelScope.launch {
            try {
                val m = api.respondToMatch(sm.matchId, true)
                val rider = Rider(sm.fromUserId, sm.fromUserName, Gender.Other, 5.0, 0, true, "", myDest, System.currentTimeMillis())
                val match = Match(rider, sm.destGapKm ?: 0.0, 0,
                    Fare.solo(myDest).roundToInt(), Fare.shared(myDest, myDest).roundToInt())
                val t = Trip(match, events = listOf("${stamp()} Accepted match from ${sm.fromUserName}. Cab ${m.cabPlate ?: ""}, PIN ${m.pin ?: ""}"))
                activeTrip = t.copy(status = TripStatus.Confirmed)
            } catch (_: Exception) {}
        }
    }

    fun complete() {
        val t = activeTrip ?: return
        history.add(0, t.copy(status = TripStatus.Completed, events = t.events + "${stamp()} Trip completed"))
        activeTrip = null
    }

    fun cancel() { activeTrip = null }

    fun raiseSOS() {
        val t = activeTrip ?: return
        val line = "${stamp()} SOS raised. Live location + trip record sent to ${emergencyName.ifEmpty { "emergency contact" }}"
        activeTrip = t.copy(status = TripStatus.Sos, events = t.events + line)
        safetyLog.add(0, line)
    }

    fun shareText(t: Trip) = """
        I'm sharing a cab from ${Mock.airport.name} to ${myDest.name}.
        Trip ${t.id} · Cab ${t.cabPlate} · Driver ${t.driverName}
        Co-rider: ${t.match.rider.name} (${t.match.rider.idRef})
    """.trimIndent()

    private fun stamp() = LocalTime.now().format(DateTimeFormatter.ofPattern("h:mm a"))

    // ── Chat ──

    fun openChat(peerId: String) {
        ChatMessage.myUserId = api.userId ?: ""
        if (activeChatPeerId != peerId) {
            chatMessages.clear()
            lastChatPoll[peerId] = 0.0
        }
        activeChatPeerId = peerId
        unreadChats.remove(peerId)
        isLoadingChat = true
        fetchChatMessages(peerId)
        viewModelScope.launch {
            try { blockedUserIds.clear(); blockedUserIds.addAll(api.fetchBlocked()) }
            catch (_: Exception) {}
        }
    }

    fun closeChat() { activeChatPeerId = "" }

    fun fetchChatMessages(peerId: String = activeChatPeerId) {
        if (!isConnected || peerId.isEmpty()) return
        val since = lastChatPoll[peerId] ?: 0.0
        val isInitial = since == 0.0
        viewModelScope.launch {
            try {
                val msgs = api.fetchMessages(peerId, since, chatPageSize, poll = !isInitial)
                isLoadingChat = false
                hasMoreChat = msgs.size >= chatPageSize
                for (sm in msgs) {
                    val msg = ChatMessage(sm.fromUserId, sm.toUserId, sm.text, sm.ts, sm.replyToText)
                    if (chatMessages.none { it.ts == msg.ts && it.fromUserId == msg.fromUserId })
                        chatMessages.add(msg)
                }
                chatMessages.sortBy { it.ts }
                msgs.lastOrNull()?.let { lastChatPoll[peerId] = it.ts }
            } catch (_: Exception) { isLoadingChat = false }
        }
    }

    fun loadOlderMessages() {
        if (!isConnected || activeChatPeerId.isEmpty()) return
        val before = chatMessages.firstOrNull()?.ts ?: (System.currentTimeMillis() / 1000.0)
        viewModelScope.launch {
            try {
                val msgs = api.fetchMessages(activeChatPeerId, 0.0, chatPageSize, before, false)
                hasMoreChat = msgs.size >= chatPageSize
                for (sm in msgs) {
                    val msg = ChatMessage(sm.fromUserId, sm.toUserId, sm.text, sm.ts, sm.replyToText)
                    if (chatMessages.none { it.ts == msg.ts && it.fromUserId == msg.fromUserId })
                        chatMessages.add(msg)
                }
                chatMessages.sortBy { it.ts }
            } catch (_: Exception) {}
        }
    }

    fun sendChatMessage(text: String, replyToText: String? = null) {
        if (!isConnected || activeChatPeerId.isEmpty()) return
        val peerId = activeChatPeerId
        ChatMessage.myUserId = api.userId ?: ""
        val myId = api.userId ?: ""
        val now = System.currentTimeMillis() / 1000.0
        val local = ChatMessage(myId, peerId, text, now, replyToText)
        chatMessages.add(local)
        viewModelScope.launch {
            try {
                val sm = api.sendMessage(peerId, text, replyToText)
                chatMessages.removeAll { it.ts == now && it.fromUserId == myId }
                chatMessages.add(ChatMessage(sm.fromUserId, sm.toUserId, sm.text, sm.ts, sm.replyToText))
                chatMessages.sortBy { it.ts }
                lastChatPoll[peerId] = sm.ts
            } catch (_: Exception) {}
        }
    }

    fun pollMessagesFromPeers() {
        if (!isConnected) return
        viewModelScope.launch {
            try {
                val convs = api.fetchInbox(0.0, false)
                val updated = mutableListOf<InboxConv>()
                for (c in convs) {
                    val pid = c.peerId
                    if (!lastChatPoll.containsKey(pid)) lastChatPoll[pid] = 0.0
                    for (sm in c.messages) {
                        val msg = ChatMessage(sm.fromUserId, sm.toUserId, sm.text, sm.ts, sm.replyToText)
                        if (chatMessages.none { it.ts == msg.ts && it.fromUserId == msg.fromUserId })
                            chatMessages.add(msg)
                    }
                    chatMessages.sortBy { it.ts }
                    c.messages.lastOrNull()?.let { lastChatPoll[pid] = maxOf(lastChatPoll[pid]!!, it.ts) }
                    val hasFromPeer = c.messages.any { it.fromUserId == pid }
                    if (hasFromPeer && pid != activeChatPeerId) unreadChats.add(pid)
                    val last = c.messages.lastOrNull()
                    updated.add(InboxConv(pid, c.peerName, last?.text ?: "", last?.ts ?: 0.0,
                        unreadChats.contains(pid), c.ended ?: false, c.blocked ?: false))
                }
                conversations.clear(); conversations.addAll(updated)
            } catch (_: Exception) {}
        }
    }

    fun blockUser(peerId: String) {
        blockedUserIds.add(peerId)
        viewModelScope.launch { try { api.blockUser(peerId) } catch (_: Exception) {} }
    }

    fun unblockUser(peerId: String) {
        blockedUserIds.remove(peerId)
        viewModelScope.launch { try { api.unblockUser(peerId) } catch (_: Exception) {} }
    }

    fun endChat(peerId: String) {
        viewModelScope.launch { try { api.endChat(peerId) } catch (_: Exception) {} }
    }

    // ── Groups ──

    fun fetchMyGroups() {
        if (!isConnected) return
        viewModelScope.launch {
            try {
                val gs = api.listGroups()
                myGroups.clear()
                myGroups.addAll(gs.map { g ->
                    GroupInfo(g.groupId, g.name, g.memberIds,
                        g.members?.map { it.name } ?: g.memberIds.map { it.take(8) })
                })
            } catch (_: Exception) {}
        }
    }

    fun createGroup(name: String, memberIds: List<String>) {
        if (!isConnected) return
        viewModelScope.launch {
            try { api.createGroup(name, memberIds); fetchMyGroups() }
            catch (_: Exception) {}
        }
    }

    fun openGroup(groupId: String) {
        ChatMessage.myUserId = api.userId ?: ""
        activeGroupId = groupId
        groupMessages.clear()
        lastGroupPoll = 0.0
        isLoadingGroup = true
        fetchGroupMessages()
    }

    fun closeGroup() { activeGroupId = "" }

    fun fetchGroupMessages() {
        if (!isConnected || activeGroupId.isEmpty()) return
        val since = lastGroupPoll
        val isInitial = since == 0.0
        viewModelScope.launch {
            try {
                val msgs = api.fetchGroupMessages(activeGroupId, since, chatPageSize, poll = !isInitial)
                isLoadingGroup = false
                hasMoreGroup = msgs.size >= chatPageSize
                for (sm in msgs) {
                    val msg = ChatMessage(sm.fromUserId, sm.groupId, sm.text, sm.ts, sm.replyToText)
                    if (groupMessages.none { it.ts == msg.ts && it.fromUserId == msg.fromUserId })
                        groupMessages.add(msg)
                }
                groupMessages.sortBy { it.ts }
                msgs.lastOrNull()?.let { lastGroupPoll = it.ts }
            } catch (_: Exception) { isLoadingGroup = false }
        }
    }

    fun sendGroupMessage(text: String, replyToText: String? = null) {
        if (!isConnected || activeGroupId.isEmpty()) return
        val gid = activeGroupId
        ChatMessage.myUserId = api.userId ?: ""
        val myId = api.userId ?: ""
        val now = System.currentTimeMillis() / 1000.0
        groupMessages.add(ChatMessage(myId, gid, text, now, replyToText))
        viewModelScope.launch {
            try {
                val sm = api.sendGroupMessage(gid, text, replyToText)
                groupMessages.removeAll { it.ts == now && it.fromUserId == myId }
                groupMessages.add(ChatMessage(sm.fromUserId, sm.groupId, sm.text, sm.ts, sm.replyToText))
                groupMessages.sortBy { it.ts }
                lastGroupPoll = sm.ts
            } catch (_: Exception) {}
        }
    }

    fun pollCycle() {
        if (!isConnected) return
        viewModelScope.launch {
            try {
                api.updateLocation(myOrigin.lat, myOrigin.lon, myOrigin.name)
                if (iAmOpen) api.upsertIntent(myOrigin, myDest, myComfortKm, iAmOpen)
                serverPending = api.pendingMatches()
                serverIntents = api.searchIntents(myOrigin, myDest, myComfortKm, search.verifiedOnly, search.sameGenderOnly)
            } catch (_: Exception) {}
        }
    }
}
