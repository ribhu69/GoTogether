# GoTogether

Airport cab-sharing for solo travellers: match with a verified co-rider heading within ~7 km of your destination and split the fare.

- `ios/` SwiftUI (iOS 17+). `cd ios && xcodegen generate && open GoTogether.xcodeproj`
- `android/` Kotlin + Jetpack Compose + Material 3. `cd android && ./gradlew :app:installDebug`
- `server/` Python 3 stdlib HTTP server (in-memory store). `cd server && ./start.sh`
- `docs/GoTogether.md` product doc: risks, safety model, revenue

Both apps are POCs with the same features: onboarding gate (phone OTP `123456`, simulated ID + selfie, emergency contact), search, radius/time matching, fare split, trip with PIN, share and SOS. The iOS app connects to the server for **live two-device matching**; the Android app uses local mock data only.

---

## Two-device testing (iOS)

This is the fastest way to see two devices discover each other live.

### 1. Start the server

```bash
cd server
./start.sh
```

This prints the LAN IP — both real devices on the same WiFi use that IP.

### 2. Build and run the iOS app on two devices

```bash
cd ios
xcodegen generate
open GoTogether.xcodeproj
```

Select each device in Xcode and run (⌘R).

### 3. Onboard both devices

On **each** device:

1. Tap the server URL field and enter `http://<LAN-IP>:8080` (the IP printed by `start.sh`)
2. Toggle **"Use server for live matching"** ON
3. Fill in name, phone, gender
4. Tap **Send OTP** → enter `123456` → **Verify OTP**
5. Pick ID type, enter any 4 digits → **Simulate ID + selfie check**
6. Fill in emergency contact
7. Tap **Register on server**

### 4. Make both devices visible

On **each** device, from the map screen:

1. Pick a destination (make them close — e.g. both pick "Indiranagar" or two nearby areas)
2. Set comfort radius to 5–7 km
3. Toggle **Open** ON (green)

Within seconds, each device shows the other's name as a green pin on the map and in the "Nearby Open" tab.

### 5. Test a match

1. On Device A, tap a green pin → **Share ride**
2. Device B sees an incoming match request in "Nearby Open" → tap **Accept**
3. Both devices get a confirmed trip with cab plate, PIN, driver name

---

## Server API

Base URL: `http://<host>:8080`

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Server status + counts |
| POST | `/api/register` | Create user |
| POST | `/api/verify` | Verify phone (OTP: `123456`) or ID |
| POST | `/api/intent` | Upsert travel intent (one per user) |
| GET | `/api/intents?userId=…&lat=…&…` | Search open intents |
| POST | `/api/match/request` | Request to share with an intent |
| GET | `/api/match/pending?userId=…` | Pending incoming match requests |
| POST | `/api/match/respond` | Accept or reject a match |

The server is single-file, stdlib-only Python 3 with an in-memory store. Restarting the server clears all data.

---

## Architecture

```
┌──────────────┐     HTTP (poll every 4s)     ┌──────────────┐
│  iOS Device A │ ──────────────────────────→  │              │
└──────────────┘                               │   server.py  │
                                               │   :8080      │
┌──────────────┐     HTTP (poll every 4s)     │              │
│  iOS Device B │ ──────────────────────────→  └──────────────┘
└──────────────┘
```

- Each device **upserts** its travel intent (origin, destination, comfort radius) to the server
- Each device **polls** for compatible open intents + pending match requests every 4 seconds
- When Device A requests a match, the server creates a pending match for Device B
- Device B's next poll picks it up and shows an Accept/Reject prompt
- On acceptance, both sides get a confirmed trip record