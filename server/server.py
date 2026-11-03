#!/usr/bin/env python3
"""
GoTogether local test server.  Single file, stdlib only, in-memory store.

Run:  python3 server.py          # listens on 0.0.0.0:8080
      python3 server.py 9000     # custom port

iOS Simulator → http://localhost:8080
Android Emulator → http://10.0.2.2:8080
Real devices → http://<mac-local-ip>:8080

Two devices on the same WiFi can discover each other in real time through
the /api/location endpoint (updated every few seconds by each client) and
the /api/intents endpoint (which now returns peer locations too).

Messages use long-polling: GET /api/messages and /api/messages/inbox hold
the connection open up to 10 seconds. When a new message is POSTed, waiting
GETs are woken immediately. Combined with client-side 500ms polling fallback,
this delivers messages near-instantly even across two devices.
"""
import json, time, math, uuid, sys, socket, os, threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs


# ── chat persistence ──────────────────────────────────────────────
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
os.makedirs(LOG_DIR, exist_ok=True)

def _log_message(chat_id: str, msg: dict) -> None:
    """Append one message JSON line to the chat log file."""
    path = os.path.join(LOG_DIR, f"chat_{chat_id}.jsonl")
    with open(path, "a") as f:
        f.write(json.dumps(msg) + "\n")

def _load_messages(chat_id: str) -> list[dict]:
    """Load all messages for a chat from the log file (lazy)."""
    path = os.path.join(LOG_DIR, f"chat_{chat_id}.jsonl")
    if not os.path.exists(path):
        return []
    msgs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    msgs.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return msgs


def local_ip() -> str:
    """Best-guess the LAN IP so real devices know what URL to use."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()

# ── in-memory store ──────────────────────────────────────────────
users: dict[str, dict] = {}        # userId → profile
intents: dict[str, dict] = {}      # intentId → intent (keyed by userId, overwritten)
matches: dict[str, dict] = {}      # matchId → match state
locations: dict[str, dict] = {}    # userId → {lat, lon, name, destLat, destLon, destName, ts}
messages: dict[str, list] = {}     # chatId → [{fromUserId, toUserId, text, ts, replyToText}]
blocked: dict[str, set] = {}       # userId → set of blocked userIds
ended_chats: dict[str, float] = {} # chatId → end timestamp (messages not allowed after)
# Groups
groups: dict[str, dict] = {}       # groupId → {groupId, name, createdBy, memberIds, createdAt}
group_messages: dict[str, list] = {} # groupId → [{fromUserId, text, ts, replyToText}]

# ── long-poll signalling ─────────────────────────────────────────
# When a message is POSTed, this condition is notified so any waiting
# GET /api/messages or GET /api/messages/inbox returns immediately.
_chat_cond = threading.Condition()
# Monotonic counter — incremented each time a message is posted, so waiters
# can detect new messages without holding the lock for the full timeout.
_message_version = 0

# ── geo ──────────────────────────────────────────────────────────
def haversine_km(a: dict, b: dict) -> float:
    r = 6371.0
    dlat = math.radians(b["lat"] - a["lat"])
    dlon = math.radians(b["lon"] - a["lon"])
    h = (math.sin(dlat / 2) ** 2 + math.cos(math.radians(a["lat"]))
         * math.cos(math.radians(b["lat"])) * math.sin(dlon / 2) ** 2)
    return 2 * r * math.asin(math.sqrt(h))

# ── helpers ──────────────────────────────────────────────────────
def ok(obj, status=200):
    return status, json.dumps(obj).encode(), "application/json"

def err(msg, status=400):
    return status, json.dumps({"error": msg}).encode(), "application/json"

# ── threaded server ──────────────────────────────────────────────
class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle each request in its own thread so long-polling doesn't block."""
    daemon_threads = True

# ── router ───────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # quiet

    def do_GET(self):
        p = urlparse(self.path)
        path = p.path
        qs = parse_qs(p.query)
        if path == "/" or path == "/dashboard": self.dashboard()
        elif path == "/api/health":          self.health()
        elif path == "/api/intents":       self.search_intents(qs)
        elif path == "/api/match/pending": self.pending_matches(qs)
        elif path == "/api/locations":     self.get_locations(qs)
        elif path == "/api/messages/inbox": self.inbox(qs)
        elif path == "/api/messages":      self.get_messages(qs)
        elif path == "/api/me":            self.me(qs)
        elif path == "/api/blocked":       self.list_blocked(qs)
        elif path == "/api/group/list":    self.list_groups(qs)
        elif path == "/api/group/messages": self.get_group_messages(qs)
        elif path == "/api/group/inbox":   self.group_inbox(qs)
        else: self._respond(*err("not found", 404))

    def do_POST(self):
        path = urlparse(self.path).path
        body = self._body()
        if path == "/api/register":       self.register(body)
        elif path == "/api/verify":       self.verify(body)
        elif path == "/api/intent":       self.upsert_intent(body)
        elif path == "/api/location":     self.update_location(body)
        elif path == "/api/match/request": self.request_match(body)
        elif path == "/api/match/respond": self.respond_match(body)
        elif path == "/api/message":      self.send_message(body)
        elif path == "/api/block":        self.block_user(body)
        elif path == "/api/unblock":      self.unblock_user(body)
        elif path == "/api/chat/end":     self.end_chat(body)
        elif path == "/api/group/create":  self.create_group(body)
        elif path == "/api/group/message": self.send_group_message(body)
        else: self._respond(*err("not found", 404))

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n)) if n else {}

    def _respond(self, status, data, ct):
        self.send_response(status)
        self.send_header("Content-Type", ct)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass  # client disconnected — nothing to do

    def health(self):
        self._respond(*ok({"status": "ok", "users": len(users), "intents": len(intents),
                           "matches": len(matches), "locations": len(locations), "ts": time.time()}))

    def dashboard(self):
        body = self._dashboard_html()
        self._respond(200, body.encode(), "text/html")

    def _dashboard_html(self) -> str:
        now = time.time()
        rows = []
        for uid, u in users.items():
            loc = locations.get(uid, {})
            intent = intents.get(uid, {})
            loc_age = round(now - loc["ts"], 1) if loc else None
            fresh = loc_age is not None and loc_age <= 60
            status = "●" if fresh else ("○" if loc_age is not None else "—")
            status_color = "#4ec9b0" if fresh else ("#ce9178" if loc_age is not None else "#808080")
            rows.append(f"""<tr>
                <td>{u['name']}</td>
                <td style="color:{'#4ec9b0' if u['phoneVerified'] else '#f44747'}">{'✓' if u['phoneVerified'] else '✗'}</td>
                <td>{intent.get('dest',{}).get('name','—') if intent else '—'}</td>
                <td style="color:{'#4ec9b0' if intent and intent['isOpen'] else '#808080'}">{'Open' if intent and intent['isOpen'] else 'Closed'}</td>
                <td style="color:{status_color}">{status} {f'{loc_age}s' if loc_age is not None else ''}</td>
                <td style="font-family:'SF Mono',monospace;font-size:11px;color:#808080">{uid[:8]}</td>
            </tr>""")
        return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GoTogether · Dashboard</title>
<style>
:root{{--bg:#1e1e1e;--surface:#252526;--border:#3e3e42;--text:#d4d4d4;--muted:#808080;--accent:#4ec9b0;--warn:#ce9178;--err:#f44747;--hl:#569cd6}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);padding:24px;min-height:100vh}}
h1{{font-size:20px;font-weight:600;color:#e0e0e0;margin-bottom:2px}}
h1 span{{color:var(--accent)}}
.sub{{color:var(--muted);font-size:12px;margin-bottom:24px}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-bottom:24px}}
.card{{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:16px 20px;text-align:center}}
.card .num{{font-size:28px;font-weight:700;color:var(--accent);line-height:1.2}}
.card .label{{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.8px;margin-top:4px}}
.table-wrap{{background:var(--surface);border:1px solid var(--border);border-radius:8px;overflow:hidden}}
table{{width:100%;border-collapse:collapse}}
th{{background:#2d2d30;color:var(--muted);font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.5px;padding:10px 14px;text-align:left;border-bottom:1px solid var(--border)}}
td{{padding:9px 14px;font-size:13px;color:#cccccc;border-bottom:1px solid #2d2d30}}
tr:last-child td{{border-bottom:none}}
tr:hover td{{background:#2a2d2e}}
td:first-child{{color:#e0e0e0;font-weight:500}}
.footer{{margin-top:16px;font-size:11px;color:var(--muted)}}
.footer span{{color:var(--accent)}}
</style></head>
<body>
<h1>🚕 GoTogether <span>Dashboard</span></h1>
<p class="sub">Live · {time.strftime('%H:%M:%S', time.localtime(now))} · auto‑refresh 3s · long-poll chat</p>
<div class="cards">
<div class="card"><div class="num">{len(users)}</div><div class="label">Users</div></div>
<div class="card"><div class="num">{len([i for i in intents.values() if i['isOpen']])}</div><div class="label">Open</div></div>
<div class="card"><div class="num">{len(locations)}</div><div class="label">Locations</div></div>
<div class="card"><div class="num">{len(messages)}</div><div class="label">Chats</div></div>
<div class="card"><div class="num">{len(matches)}</div><div class="label">Matches</div></div>
</div>
<div class="table-wrap">
<table><thead><tr><th>Name</th><th>Phone</th><th>Destination</th><th>Intent</th><th>GPS</th><th>User ID</th></tr></thead>
<tbody>{''.join(rows) if rows else '<tr><td colspan="6" style="color:var(--muted);text-align:center;padding:30px">No users registered — pick a destination on a device</td></tr>'}</tbody></table>
</div>
<p class="footer"><span>●</span> fresh ≤60s &nbsp; <span style="color:var(--warn)">○</span> stale &nbsp; <span style="color:var(--muted)">—</span> no location</p>
<script>setTimeout(()=>location.reload(),3000)</script>
</body></html>"""

    def me(self, qs):
        """Return this user's server-side state — profile, intent, location freshness."""
        uid = qs.get("userId", [""])[0]
        u = users.get(uid)
        if not u:
            return self._respond(*err("user not found"))
        now = time.time()
        loc = locations.get(uid)
        intent = intents.get(uid)
        return self._respond(*ok({
            "userId": uid,
            "name": u["name"],
            "phoneVerified": u["phoneVerified"],
            "idVerified": u["idVerified"],
            "hasLocation": loc is not None,
            "locationAgeSec": round(now - loc["ts"], 1) if loc else None,
            "hasIntent": intent is not None,
            "intentOpen": intent["isOpen"] if intent else False,
            "intentDest": intent["dest"]["name"] if intent else None,
            "comfortRadiusKm": intent["comfortRadiusKm"] if intent else None,
            "serverTs": now,
        }))

    # ── endpoints ────────────────────────────────────────────────

    def register(self, b):
        uid = uuid.uuid4().hex[:12]
        users[uid] = {
            "userId": uid,
            "name": b["name"], "phone": b["phone"], "gender": b["gender"],
            "idType": b.get("idType", ""), "idLast4": b.get("idLast4", ""),
            "emergencyName": b.get("emergencyName", ""),
            "emergencyPhone": b.get("emergencyPhone", ""),
            "phoneVerified": False, "idVerified": False,
            "createdAt": time.time(),
        }
        self._respond(*ok(users[uid], 201))

    def verify(self, b):
        u = users.get(b.get("userId", ""))
        if not u: return self._respond(*err("user not found"))
        if b.get("type") == "phone" and b.get("otp") == "123456":
            u["phoneVerified"] = True
        if b.get("type") == "id" and len(b.get("idLast4", "")) == 4:
            u["idVerified"] = True
        self._respond(*ok(u))

    def upsert_intent(self, b):
        u = users.get(b.get("userId", ""))
        if not u:
            # Server restart or stale userId — auto-create minimal profile
            uid = b["userId"]
            u = {
                "userId": uid,
                "name": b.get("userName", uid[:8]),
                "phone": b.get("phone", ""),
                "gender": b.get("userGender", "other"),
                "idType": "", "idLast4": "",
                "emergencyName": "", "emergencyPhone": "",
                "phoneVerified": True, "idVerified": True,
                "createdAt": time.time(),
            }
            users[uid] = u
        iid = b["userId"]  # one intent per user
        i = {
            "intentId": iid,
            "userId": b["userId"],
            "userName": u["name"],
            "userGender": u["gender"],
            "idVerified": u["idVerified"],
            "idRef": f"{u.get('idType','')} ••••{u.get('idLast4','')}",
            "rating": 5.0, "trips": 0,
            "origin": b["origin"],       # {lat, lon, name}
            "dest": b["dest"],           # {lat, lon, name}
            "comfortRadiusKm": b["comfortRadiusKm"],
            "isOpen": b["isOpen"],
            "updatedAt": time.time(),
        }
        intents[iid] = i
        compat = self._find_compatible(i)
        self._respond(*ok({"intent": i, "compatible": compat}))

    def search_intents(self, qs):
        uid = qs.get("userId", [""])[0]
        try:
            my_lat = float(qs.get("lat", [0])[0])
            my_lon = float(qs.get("lon", [0])[0])
            dst_lat = float(qs.get("destLat", [0])[0])
            dst_lon = float(qs.get("destLon", [0])[0])
            comfort = float(qs.get("comfortKm", [5])[0])
            verified = qs.get("verifiedOnly", ["true"])[0] == "true"
            same_gender = qs.get("sameGender", ["false"])[0] == "true"
        except (ValueError, IndexError):
            return self._respond(*err("bad query params"))

        my = users.get(uid)
        origin = {"lat": my_lat, "lon": my_lon}
        dest = {"lat": dst_lat, "lon": dst_lon}

        results = []
        for i in intents.values():
            if not i["isOpen"] or i["userId"] == uid: continue
            if verified and not i["idVerified"]: continue
            if same_gender and my and i["userGender"] != my["gender"]: continue
            # Hide blocked users and users who blocked us
            if i["userId"] in blocked.get(uid, set()): continue
            if uid in blocked.get(i["userId"], set()): continue
            origin_gap = haversine_km(origin, i["origin"])
            if origin_gap > 0.5: continue
            dest_gap = haversine_km(dest, i["dest"])
            if dest_gap > comfort: continue
            if haversine_km(i["dest"], dest) > i["comfortRadiusKm"]: continue
            results.append({**i, "originGapKm": round(origin_gap, 3), "destGapKm": round(dest_gap, 3)})

        results.sort(key=lambda x: x["destGapKm"])

        # Include peer locations for mutually compatible travelers only:
        # same airport (≤0.5 km), mutual destinations within each other's comfort radii.
        now = time.time()
        compatible_user_ids = {r["userId"] for r in results}
        peers = []
        for lid, loc in locations.items():
            if lid == uid: continue
            if now - loc.get("ts", 0) > 60: continue
            if lid not in compatible_user_ids: continue
            peers.append({
                "userId": lid,
                "userName": users.get(lid, {}).get("name", lid),
                "lat": loc["lat"], "lon": loc["lon"],
                "name": loc.get("name"),
                "destLat": loc.get("destLat"), "destLon": loc.get("destLon"),
                "destName": loc.get("destName"),
            })

        self._respond(*ok({"intents": results, "peers": peers}))

    def update_location(self, b):
        uid = b.get("userId", "")
        if not uid: return self._respond(*err("missing userId"))
        # Auto-create user if unknown (server restart / stale userId)
        if uid not in users:
            users[uid] = {
                "userId": uid,
                "name": b.get("name", uid[:8]),
                "phone": "", "gender": "other",
                "idType": "", "idLast4": "",
                "emergencyName": "", "emergencyPhone": "",
                "phoneVerified": True, "idVerified": True,
                "createdAt": time.time(),
            }
        locations[uid] = {
            "lat": b["lat"], "lon": b["lon"],
            "name": b.get("name", ""),
            "destLat": b.get("destLat"), "destLon": b.get("destLon"),
            "destName": b.get("destName"),
            "ts": time.time(),
        }
        # Also update the user's intent origin so matching uses live location.
        if uid in intents:
            intents[uid]["origin"] = {"lat": b["lat"], "lon": b["lon"], "name": b.get("name", "")}
        self._respond(*ok({"ok": True}))

    def get_locations(self, qs):
        uid = qs.get("userId", [""])[0]
        now = time.time()
        peers = []
        for lid, loc in locations.items():
            if lid == uid: continue
            if now - loc.get("ts", 0) > 60: continue
            peers.append({
                "userId": lid,
                "userName": users.get(lid, {}).get("name", lid),
                "lat": loc["lat"], "lon": loc["lon"],
                "name": loc.get("name"),
            })
        self._respond(*ok({"peers": peers}))

    def request_match(self, b):
        from_uid = b.get("fromUserId")
        to_iid = b.get("toIntentId")
        if not from_uid or not to_iid: return self._respond(*err("missing fields"))
        target = intents.get(to_iid)
        if not target: return self._respond(*err("intent not found"))

        mid = uuid.uuid4().hex[:10]
        matches[mid] = {
            "matchId": mid,
            "fromUserId": from_uid,
            "fromUserName": users.get(from_uid, {}).get("name", ""),
            "toUserId": target["userId"],
            "toUserName": target["userName"],
            "toIntentId": to_iid,
            "destGapKm": round(haversine_km(
                intents.get(from_uid, {}).get("dest", target["dest"]), target["dest"]), 2),
            "status": "pending",
            "createdAt": time.time(),
        }
        self._respond(*ok(matches[mid], 201))

    def pending_matches(self, qs):
        uid = qs.get("userId", [""])[0]
        result = [m for m in matches.values()
                  if m["toUserId"] == uid and m["status"] == "pending"]
        self._respond(*ok({"matches": result}))

    def respond_match(self, b):
        m = matches.get(b.get("matchId", ""))
        if not m: return self._respond(*err("match not found"))
        if b.get("accept"):
            m["status"] = "confirmed"
            m["cabPlate"] = "KA 01 AB " + str(uuid.uuid4().int % 9000 + 1000)
            m["pin"] = str(uuid.uuid4().int % 9000 + 1000)
            m["driverName"] = "Ravi K."
        else:
            m["status"] = "rejected"
        self._respond(*ok(m))

    # ── chat with long-polling ───────────────────────────────────

    @staticmethod
    def _chat_id(a: str, b: str) -> str:
        return "-".join(sorted([a, b]))

    def send_message(self, b):
        """Store message and wake all long-poll waiters. Blocks if chat ended or user blocked."""
        from_uid = b.get("fromUserId", "")
        to_uid = b.get("toUserId", "")
        text = (b.get("text") or "").strip()
        if not from_uid or not to_uid or not text:
            return self._respond(*err("missing fromUserId, toUserId, or text"))
        cid = self._chat_id(from_uid, to_uid)
        # Enforce ended chats
        if cid in ended_chats:
            return self._respond(*err("this conversation has ended", 403))
        # Enforce blocks (either direction)
        if to_uid in blocked.get(from_uid, set()):
            return self._respond(*err("you blocked this user", 403))
        if from_uid in blocked.get(to_uid, set()):
            return self._respond(*err("you are blocked by this user", 403))
        msg = {"fromUserId": from_uid, "toUserId": to_uid,
               "text": text, "ts": time.time(),
               "replyToText": b.get("replyToText")}
        messages.setdefault(cid, []).append(msg)
        _log_message(cid, msg)
        # Wake all long-polling GETs immediately
        with _chat_cond:
            global _message_version
            _message_version += 1
            _chat_cond.notify_all()
        self._respond(*ok(msg, 201))

    # ── block / end-chat ─────────────────────────────────────────

    def block_user(self, b):
        """POST /api/block — block a user by userId."""
        uid = b.get("userId", "")
        target = b.get("targetUserId", "")
        if not uid or not target:
            return self._respond(*err("missing userId or targetUserId"))
        blocked.setdefault(uid, set()).add(target)
        self._respond(*ok({"blocked": True, "targetUserId": target}))

    def unblock_user(self, b):
        """POST /api/unblock — unblock a user."""
        uid = b.get("userId", "")
        target = b.get("targetUserId", "")
        if not uid or not target:
            return self._respond(*err("missing userId or targetUserId"))
        blocked.get(uid, set()).discard(target)
        self._respond(*ok({"blocked": False, "targetUserId": target}))

    def list_blocked(self, qs):
        """GET /api/blocked — return the current user's blocked list."""
        uid = qs.get("userId", [""])[0]
        if not uid:
            return self._respond(*err("missing userId"))
        blist = list(blocked.get(uid, set()))
        self._respond(*ok({"blockedUserIds": blist}))

    def end_chat(self, b):
        """POST /api/chat/end — mark a conversation as ended (no more messages)."""
        uid = b.get("userId", "")
        peer = b.get("peerId", "")
        if not uid or not peer:
            return self._respond(*err("missing userId or peerId"))
        cid = self._chat_id(uid, peer)
        ended_chats[cid] = time.time()
        self._respond(*ok({"ended": True, "chatId": cid}))

    # ── groups ────────────────────────────────────────────────────

    @staticmethod
    def _log_group_message(group_id: str, msg: dict) -> None:
        path = os.path.join(LOG_DIR, f"group_{group_id}.jsonl")
        with open(path, "a") as f:
            f.write(json.dumps(msg) + "\n")

    @staticmethod
    def _load_group_messages(group_id: str) -> list[dict]:
        path = os.path.join(LOG_DIR, f"group_{group_id}.jsonl")
        if not os.path.exists(path):
            return []
        msgs = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        msgs.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
        return msgs

    def create_group(self, b):
        """POST /api/group/create — create a group with selected members."""
        uid = b.get("userId", "")
        name = b.get("name", "").strip()
        member_ids = b.get("memberIds", [])
        if not uid or not name or not member_ids:
            return self._respond(*err("missing userId, name, or memberIds"))
        # Ensure creator is in the group
        all_members = list(set([uid] + member_ids))
        gid = uuid.uuid4().hex[:10]
        groups[gid] = {
            "groupId": gid,
            "name": name,
            "createdBy": uid,
            "memberIds": all_members,
            "createdAt": time.time(),
        }
        self._respond(*ok(groups[gid], 201))

    def list_groups(self, qs):
        """GET /api/group/list — return groups the user is a member of."""
        uid = qs.get("userId", [""])[0]
        if not uid:
            return self._respond(*err("missing userId"))
        result = [g for g in groups.values() if uid in g["memberIds"]]
        # Include member names
        enriched = []
        for g in result:
            members = []
            for mid in g["memberIds"]:
                u = users.get(mid, {})
                members.append({"userId": mid, "name": u.get("name", mid[:8])})
            enriched.append({**g, "members": members})
        self._respond(*ok({"groups": enriched}))

    def send_group_message(self, b):
        """POST /api/group/message — broadcast to all group members."""
        from_uid = b.get("fromUserId", "")
        gid = b.get("groupId", "")
        text = (b.get("text") or "").strip()
        if not from_uid or not gid or not text:
            return self._respond(*err("missing fromUserId, groupId, or text"))
        g = groups.get(gid)
        if not g:
            return self._respond(*err("group not found"))
        if from_uid not in g["memberIds"]:
            return self._respond(*err("not a member"))
        msg = {"fromUserId": from_uid, "groupId": gid,
               "text": text, "ts": time.time(),
               "replyToText": b.get("replyToText"),
               "senderName": users.get(from_uid, {}).get("name", from_uid[:8])}
        group_messages.setdefault(gid, []).append(msg)
        self._log_group_message(gid, msg)
        with _chat_cond:
            global _message_version
            _message_version += 1
            _chat_cond.notify_all()
        self._respond(*ok(msg, 201))

    def get_group_messages(self, qs):
        """GET /api/group/messages — long-poll for group messages."""
        uid = qs.get("userId", [""])[0]
        gid = qs.get("groupId", [""])[0]
        if not uid or not gid:
            return self._respond(*err("missing userId or groupId"))
        try:
            since = float(qs.get("since", ["0"])[0])
            limit = int(qs.get("limit", ["50"])[0])
            before = float(qs.get("before", ["0"])[0]) or None
            poll = qs.get("poll", ["1"])[0] != "0"
        except ValueError:
            return self._respond(*err("bad params"))
        # Merge memory + file
        mem = group_messages.get(gid, [])
        file_msgs = self._load_group_messages(gid)
        all_msgs = file_msgs if len(file_msgs) >= len(mem) else mem
        if all_msgs and gid not in group_messages:
            group_messages[gid] = all_msgs
        filtered = [m for m in all_msgs if m["ts"] > since]
        if before:
            filtered = [m for m in filtered if m["ts"] < before]
        if not filtered and poll:
            self._wait_for_new_messages(uid, since, timeout_s=10.0)
            mem = group_messages.get(gid, [])
            file_msgs = self._load_group_messages(gid)
            all_msgs = file_msgs if len(file_msgs) >= len(mem) else mem
            filtered = [m for m in all_msgs if m["ts"] > since]
            if before:
                filtered = [m for m in filtered if m["ts"] < before]
        filtered.sort(key=lambda m: m["ts"], reverse=True)
        has_more = len(filtered) > limit
        page = filtered[:limit]
        self._respond(*ok({"messages": list(reversed(page)), "hasMore": has_more}))

    def group_inbox(self, qs):
        """GET /api/group/inbox — all groups with new messages since since."""
        uid = qs.get("userId", [""])[0]
        if not uid:
            return self._respond(*err("missing userId"))
        try:
            since = float(qs.get("since", ["0"])[0])
            poll = qs.get("poll", ["1"])[0] != "0"
        except ValueError:
            return self._respond(*err("bad since"))
        convs = self._build_group_inbox(uid, since)
        if not convs and poll:
            self._wait_for_new_messages(uid, since, timeout_s=10.0)
            convs = self._build_group_inbox(uid, since)
        self._respond(*ok({"conversations": convs}))

    def _build_group_inbox(self, uid: str, since: float) -> list[dict]:
        all_gids = set(group_messages.keys())
        if os.path.isdir(LOG_DIR):
            for fname in os.listdir(LOG_DIR):
                if fname.startswith("group_") and fname.endswith(".jsonl"):
                    all_gids.add(fname[6:-5])
        conversations = []
        for gid in all_gids:
            g = groups.get(gid, {})
            member_ids = g.get("memberIds", [])
            if uid not in member_ids:
                continue
            mem_msgs = group_messages.get(gid, [])
            file_msgs = self._load_group_messages(gid)
            all_msgs = file_msgs if len(file_msgs) >= len(mem_msgs) else mem_msgs
            if all_msgs and gid not in group_messages:
                group_messages[gid] = all_msgs
            new_msgs = [m for m in all_msgs if m["ts"] > since]
            if new_msgs or g:
                conversations.append({
                    "groupId": gid,
                    "groupName": g.get("name", "Group") if g else "Group " + gid[:6],
                    "memberIds": member_ids,
                    "messages": new_msgs,
                    "isGroup": True,
                })
        return conversations

    def _wait_for_new_messages(self, uid: str, since: float, timeout_s: float = 10.0):
        """Block until new messages arrive or timeout. Returns the version we saw."""
        global _message_version
        start_version = _message_version
        with _chat_cond:
            # Check if messages already exist (avoid race: message posted between
            # our last poll and the lock acquire)
            # We check after acquiring the lock to be safe.
            remaining = timeout_s
            while remaining > 0:
                # Quick re-check: has anything new been posted?
                if _message_version != start_version:
                    return _message_version
                wait_start = time.monotonic()
                if not _chat_cond.wait(timeout=min(remaining, 1.0)):
                    # timed out after 1s — loop to re-check
                    remaining -= (time.monotonic() - wait_start)
                    if remaining <= 0:
                        break
                    continue
                # Woken up — either new messages or spurious
                if _message_version != start_version:
                    return _message_version
                remaining -= (time.monotonic() - wait_start)
        return _message_version

    def get_messages(self, qs):
        """GET /api/messages — long-poll: wait up to 10s for new messages."""
        uid = qs.get("userId", [""])[0]
        peer = qs.get("peerId", [""])[0]
        if not uid or not peer:
            return self._respond(*err("missing userId or peerId"))
        try:
            since = float(qs.get("since", ["0"])[0])
            limit = int(qs.get("limit", ["50"])[0])
            before = float(qs.get("before", ["0"])[0]) or None
            poll = qs.get("poll", ["1"])[0] != "0"  # client can opt out of long-poll
        except ValueError:
            return self._respond(*err("bad params"))
        cid = self._chat_id(uid, peer)

        # Quick check: any messages already?
        mem = messages.get(cid, [])
        file_msgs = _load_messages(cid)
        all_msgs = file_msgs if len(file_msgs) >= len(mem) else mem
        if all_msgs and cid not in messages:
            messages[cid] = all_msgs
        filtered = [m for m in all_msgs if m["ts"] > since]
        if before:
            filtered = [m for m in filtered if m["ts"] < before]

        # If no new messages and long-poll enabled, wait
        if not filtered and poll:
            self._wait_for_new_messages(uid, since, timeout_s=10.0)
            # Re-query after wake
            mem = messages.get(cid, [])
            file_msgs = _load_messages(cid)
            all_msgs = file_msgs if len(file_msgs) >= len(mem) else mem
            if all_msgs and cid not in messages:
                messages[cid] = all_msgs
            filtered = [m for m in all_msgs if m["ts"] > since]
            if before:
                filtered = [m for m in filtered if m["ts"] < before]

        filtered.sort(key=lambda m: m["ts"], reverse=True)
        has_more = len(filtered) > limit
        page = filtered[:limit]
        self._respond(*ok({"messages": list(reversed(page)), "hasMore": has_more}))

    def inbox(self, qs):
        """GET /api/messages/inbox — long-poll: wait up to 10s for new messages."""
        uid = qs.get("userId", [""])[0]
        if not uid:
            return self._respond(*err("missing userId"))
        try:
            since = float(qs.get("since", ["0"])[0])
            poll = qs.get("poll", ["1"])[0] != "0"
        except ValueError:
            return self._respond(*err("bad since"))

        # Quick check
        convs = self._build_inbox(uid, since)
        if not convs and poll:
            self._wait_for_new_messages(uid, since, timeout_s=10.0)
            convs = self._build_inbox(uid, since)

        self._respond(*ok({"conversations": convs}))

    def _build_inbox(self, uid: str, since: float) -> list[dict]:
        """Build inbox response — scans both in-memory AND file-persisted
        conversations so messages survive server restarts."""
        # Discover all chat IDs: in-memory + log files on disk
        all_chat_ids = set(messages.keys())
        if os.path.isdir(LOG_DIR):
            for fname in os.listdir(LOG_DIR):
                if fname.startswith("chat_") and fname.endswith(".jsonl"):
                    cid = fname[5:-5]  # strip "chat_" prefix and ".jsonl" suffix
                    all_chat_ids.add(cid)

        conversations = []
        for cid in all_chat_ids:
            ids = cid.split("-")
            if uid not in ids: continue
            peer = ids[0] if ids[1] == uid else ids[1]
            mem_msgs = messages.get(cid, [])
            file_msgs = _load_messages(cid)
            all_msgs = file_msgs if len(file_msgs) >= len(mem_msgs) else mem_msgs
            # Also load into memory if missing (server restart recovery)
            if all_msgs and cid not in messages:
                messages[cid] = all_msgs
            # Check if this conversation is ended
            ended_at = ended_chats.get(cid)
            blocked_peer = peer in blocked.get(uid, set())
            new_msgs = [m for m in all_msgs if m["ts"] > since]
            if new_msgs:
                conversations.append({
                    "peerId": peer,
                    "peerName": users.get(peer, {}).get("name", peer[:8]),
                    "messages": new_msgs,
                    "ended": ended_at is not None,
                    "endedAt": ended_at,
                    "blocked": blocked_peer,
                })
            elif ended_at is not None or blocked_peer:
                # Return conversations even without new messages if they're ended/blocked
                # (so the client still shows them in the inbox list)
                conversations.append({
                    "peerId": peer,
                    "peerName": users.get(peer, {}).get("name", peer[:8]),
                    "messages": [],
                    "ended": ended_at is not None,
                    "endedAt": ended_at,
                    "blocked": blocked_peer,
                })
        return conversations

    def _find_compatible(self, intent: dict) -> list:
        """Return intents that would match this one (two-way check)."""
        if not intent["isOpen"]: return []
        results = []
        for i in intents.values():
            if i["userId"] == intent["userId"] or not i["isOpen"]: continue
            if haversine_km(intent["origin"], i["origin"]) > 0.5: continue
            if haversine_km(intent["dest"], i["dest"]) > intent["comfortRadiusKm"]: continue
            if haversine_km(i["dest"], intent["dest"]) > i["comfortRadiusKm"]: continue
            results.append({**i, "destGapKm": round(haversine_km(intent["dest"], i["dest"]), 3)})
        return sorted(results, key=lambda x: x["destGapKm"])


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    ip = local_ip()
    print(f"GoTogether server → http://0.0.0.0:{port}")
    print(f"  Local (simulator):  http://localhost:{port}")
    print(f"  LAN  (real device): http://{ip}:{port}")
    if ip.startswith("10.") or ip.startswith("172.") or ip.startswith("192.168."):
        print(f"  ⚠️  If your phone can't reach this IP, you may be on VPN.")
        print(f"     Check: ifconfig en0 | grep 'inet ' for your real WiFi IP.")
    print(f"  Health check:       http://localhost:{port}/api/health")
    print("  Long-poll chat active (≤10s hold, instant wake on message)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.server_close()
        print(" shut down")