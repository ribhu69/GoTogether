#!/usr/bin/env python3
"""
GoTogether local test server.  Single file, stdlib only, in-memory store.

Run:  python3 server.py          # listens on 0.0.0.0:8080
      python3 server.py 9000     # custom port

iOS Simulator → http://localhost:8080
Android Emulator → http://10.0.2.2:8080
Real devices → http://<mac-local-ip>:8080
"""
import json, time, math, uuid, sys, socket
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs


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
        if path == "/api/health":          self.health()
        elif path == "/api/intents":       self.search_intents(qs)
        elif path == "/api/match/pending": self.pending_matches(qs)
        else: self._respond(*err("not found", 404))

    def do_POST(self):
        path = urlparse(self.path).path
        body = self._body()
        if path == "/api/register":       self.register(body)
        elif path == "/api/verify":       self.verify(body)
        elif path == "/api/intent":       self.upsert_intent(body)
        elif path == "/api/match/request": self.request_match(body)
        elif path == "/api/match/respond": self.respond_match(body)
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
                           "matches": len(matches), "ts": time.time()}))

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
        if not u: return self._respond(*err("user not found"))
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
        # Return compatible intents so the client can show "who'd be notified"
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
        self._respond(*ok({"intents": results}))

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
    print(f"  Health check:       http://localhost:{port}/api/health")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.server_close()
        print(" shut down")
