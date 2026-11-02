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
"""
import json, time, math, uuid, sys, socket, os
from http.server import HTTPServer, BaseHTTPRequestHandler
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
messages: dict[str, list] = {}     # chatId → [{fromUserId, toUserId, text, ts}]

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

# ── router ───────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # quiet

    def do_GET(self):
        path = urlparse(self.path).path
        qs = parse_qs(urlparse(self.path).query)
        if path == "/" or path == "/dashboard": self.dashboard()
        elif path == "/api/health":          self.health()
        elif path == "/api/intents":       self.search_intents(qs)
        elif path == "/api/match/pending": self.pending_matches(qs)
        elif path == "/api/locations":     self.get_locations(qs)
        elif path == "/api/messages":      self.get_messages(qs)
        elif path == "/api/me":            self.me(qs)
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
        else: self._respond(*err("not found", 404))

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n)) if n else {}

    def _respond(self, status, data, ct):
        self.send_response(status)
        self.send_header("Content-Type", ct)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

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
            fresh = loc_age is not None and loc_age <= 30
            rows.append(f"""<tr>
                <td>{u['name']}</td>
                <td class="{'green' if u['phoneVerified'] else 'red'}">{'✓' if u['phoneVerified'] else '✗'}</td>
                <td>{intent.get('dest',{}).get('name','—') if intent else '—'}</td>
                <td class="{'green' if intent and intent['isOpen'] else ''}">{'Open' if intent and intent['isOpen'] else 'Closed'}</td>
                <td class="{'green' if fresh else 'orange'}">{f'{loc_age}s' if loc_age is not None else '—'}</td>
                <td class="mono">{uid[:8]}</td>
            </tr>""")
        return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GoTogether Dashboard</title>
<style>
  *{box-sizing:border-box} body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:20px;background:#f0f2f5;color:#1a1a2e}
  h1{margin:0 0 4px;font-size:24px} .sub{color:#666;margin:0 0 20px;font-size:13px}
  .cards{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:24px}
  .card{background:#fff;border-radius:12px;padding:18px 24px;min-width:110px;text-align:center;box-shadow:0 2px 8px #0000000d}
  .card .num{font-size:32px;font-weight:700;color:#1a1a2e}
  .card .label{font-size:11px;color:#888;text-transform:uppercase;letter-spacing:.5px;margin-top:4px}
  table{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px #0000000d}
  th,td{padding:12px 16px;text-align:left;font-size:13px}
  th{background:#f7f8fa;font-weight:600;color:#555;text-transform:uppercase;font-size:11px;letter-spacing:.3px}
  tr:not(:last-child) td{border-bottom:1px solid #f0f0f0}
  td{color:#333;font-weight:450}
  td:first-child{font-weight:600;color:#1a1a2e}
  .green{color:#2e7d32!important;font-weight:600} .red{color:#c62828!important} .orange{color:#e65100!important}
  .mono{font-family:'SF Mono',Monaco,monospace;font-size:11px;color:#888}
  @media(prefers-color-scheme:dark){body{background:#0f0f1a;color:#e0e0e0} .card,.table{background:#1a1a2e} th{background:#16213e;color:#aaa} td{color:#ccc} td:first-child{color:#e0e0e0} tr:not(:last-child) td{border-color:#2a2a3e} .sub{color:#999}}
</style></head>
<body>
<h1>🚕 GoTogether</h1><p class="sub">Dashboard · auto-refresh 3s · {now:.0f}</p>
<div class="cards">
<div class="card"><div class="num">{len(users)}</div><div class="label">Users</div></div>
<div class="card"><div class="num">{len([i for i in intents.values() if i['isOpen']])}</div><div class="label">Open</div></div>
<div class="card"><div class="num">{len(locations)}</div><div class="label">Locations</div></div>
<div class="card"><div class="num">{len(messages)}</div><div class="label">Chats</div></div>
<div class="card"><div class="num">{len(matches)}</div><div class="label">Matches</div></div>
</div>
<table><tr><th>Name</th><th>Phone</th><th>Dest</th><th>Intent</th><th>GPS</th><th>ID</th></tr>
{''.join(rows) if rows else '<tr><td colspan="6" style="color:#999;text-align:center;padding:30px">No users registered yet</td></tr>'}
</table>
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
            if now - loc.get("ts", 0) > 30: continue
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
            if now - loc.get("ts", 0) > 30: continue
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

    # ── chat ────────────────────────────────────────────────────

    @staticmethod
    def _chat_id(a: str, b: str) -> str:
        return "-".join(sorted([a, b]))

    def send_message(self, b):
        from_uid = b.get("fromUserId", "")
        to_uid = b.get("toUserId", "")
        text = (b.get("text") or "").strip()
        if not from_uid or not to_uid or not text:
            return self._respond(*err("missing fromUserId, toUserId, or text"))
        cid = self._chat_id(from_uid, to_uid)
        msg = {"fromUserId": from_uid, "toUserId": to_uid,
               "text": text, "ts": time.time()}
        # In-memory + file persistence
        messages.setdefault(cid, []).append(msg)
        _log_message(cid, msg)
        self._respond(*ok(msg, 201))

    def get_messages(self, qs):
        uid = qs.get("userId", [""])[0]
        peer = qs.get("peerId", [""])[0]
        if not uid or not peer:
            return self._respond(*err("missing userId or peerId"))
        try:
            since = float(qs.get("since", ["0"])[0])
        except ValueError:
            return self._respond(*err("bad since"))
        cid = self._chat_id(uid, peer)
        # Merge in-memory + file (pick whichever has more messages)
        mem = messages.get(cid, [])
        file_msgs = _load_messages(cid)
        all_msgs = file_msgs if len(file_msgs) >= len(mem) else mem
        # Sync in-memory with file (for restarts)
        if all_msgs and cid not in messages:
            messages[cid] = all_msgs
        result = [m for m in all_msgs if m["ts"] > since]
        self._respond(*ok({"messages": result}))

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
    srv = HTTPServer(("0.0.0.0", port), Handler)
    ip = local_ip()
    print(f"GoTogether server → http://0.0.0.0:{port}")
    print(f"  Local (simulator):  http://localhost:{port}")
    print(f"  LAN  (real device): http://{ip}:{port}")
    if ip.startswith("10.") or ip.startswith("172.") or ip.startswith("192.168."):
        print(f"  ⚠️  If your phone can't reach this IP, you may be on VPN.")
        print(f"     Check: ifconfig en0 | grep 'inet ' for your real WiFi IP.")
    print(f"  Health check:       http://localhost:{port}/api/health")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.server_close()
        print(" shut down")