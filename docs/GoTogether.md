# GoTogether: product, risk and revenue doc

Status: POC (mock data, no backend). Regulatory and pricing statements below are working assumptions to validate with counsel and with real data, not facts.

## 1. Problem and idea

Solo travellers leaving an airport take an individual cab. Many are going the same way. GoTogether matches a rider with a verified co-rider whose destination is within a configurable radius (default 7 km) and whose departure time is close, and splits the fare.

Primary user: solo traveller, business or leisure, who wants to save money and is willing to share if the co-rider is verified and traceable.

## 2. Core flow

1. Onboard: phone OTP, government ID + liveness selfie, emergency contact. No match until all three exist.
2. Search: airport, destination, leave time, radius, time window, verified-only, same-gender-only.
3. Match list: sorted by destination gap then time gap, showing masked ID, rating, trips, saving.
4. Request, co-rider accepts, cab assigned. Trip PIN, plate, driver shown.
5. In trip: share trip link, SOS (alerts contact, dials 112), complete.
6. Trip record kept with both riders' verified IDs, cab and driver.

## 3. Matching and fare (as built in the POC)

- Distance between destinations: haversine. Production should use routing: detour minutes for the first drop-off, not straight-line km.
- Filters: destination gap <= radius, |departure gap| <= window, verified, gender.
- Fare estimate: `150 + 22 × 1.3 × km`. Shared total = farther solo fare + 20% of the nearer one, split pro-rata to solo fares. Example: solo ₹1000 and ₹600 give a total of ₹1120, paying ₹700 and ₹420 (saves ₹300 and ₹180). All constants are placeholders to be calibrated against real fares.
- Rule to keep: a shared fare must never exceed the solo fare.

## 4. Safety and traceability (your main concern)

Layered, because no single control is enough.

**Before matching**
- Gov ID via e-KYC / DigiLocker (Aadhaar, passport, DL) plus liveness selfie matched to the ID photo. Re-verify on device change or suspicious activity.
- Verified phone, device fingerprint, one account per ID. Banned ID means banned for good.
- Emergency contact required.

**At match time**
- Co-riders see name, rating and a masked ID reference only. Exact drop address is revealed to the driver, not the co-rider. Show the neighbourhood only.
- Verified-only is the default. Same-gender and women-only pools as options.
- Both riders confirm the match.

**At boarding**
- Meet at a designated, staffed, CCTV-covered airport pickup point.
- Trip PIN so each rider boards the right cab and the right co-rider.

**During trip**
- Live location share link, route-deviation and long-stop detection, in-app masked calling.
- SOS: notifies emergency contact with live location, plate, co-rider ID, and dials 112. A 24x7 trust & safety desk should be able to take over.
- Drop-off order is shown to both riders in advance.

**After trip**
- Immutable trip record (both riders, cab, driver, route, timestamps) for emergencies and police requests via a documented legal process.
- Two-way ratings, report flow, fast ban.

**Traceability vs privacy**
These conflict. Under India's DPDP Act (2023), collect only what is needed, get explicit consent, set retention limits, and keep the raw ID with a KYC vendor or encrypted vault. The app stores a token and masked reference. Define in advance who can retrieve identity (police request with legal process, internal Trust & Safety with audit trail).

## 5. Risks and open questions

| Area | Risk | Mitigation / question |
|---|---|---|
| Regulatory | Ride-sharing rules for commercial cabs vary by state; aggregator guidelines may apply if we book or price the ride | Get legal advice early. Start as matching layer plus payment split, or partner with a licensed operator |
| Operating model | Do riders book the cab themselves (we only match), or do we book it? | See section 6 |
| Cold start | Too few riders per airport per window, so no matches | One airport, one terminal; match by flight arrival time, not "now"; pre-book; guarantee solo fallback at no extra cost |
| Detour and fairness | First drop-off is hurt by the second | Cap detour (e.g. 15 min); order by route; show times before accept |
| No-shows, delays | Flight delay, co-rider cancels | Flight-number tracking, free re-match, small cancellation fee after accept |
| Safety incident | Harassment, stalking, assault | Section 4; insurance; 24x7 desk; incident playbook |
| Fake identity | Forged ID, borrowed account | Liveness, vendor-grade KYC, device binding |
| Driver acceptance | Drivers may not like multi-drop | Transparent pricing, fair pay for extra stop |
| Luggage, capacity | Two riders and bags in one cab | Ask luggage count; vehicle-size aware matching |
| Payments | Collecting and splitting money | Use a licensed gateway with split settlement; avoid holding funds ourselves |
| Liability | Who is responsible in an accident or crime | Terms, insurance, operator partnership |
| Privacy | KYC data breach | Vendor vault, encryption, minimal retention, DPDP compliance |
| Trust loop | One bad event ends the brand | Safety is the product, not a feature |

## 6. Operating models

| Model | How it works | Pro | Con |
|---|---|---|---|
| A. Match-only | Riders book their own cab; app matches and splits | Fastest, least regulation | Clumsy settlement; driver unaware; weak control of safety |
| B. Book via partner | Use ride-hail or prepaid-taxi APIs and book a shared cab | Real pricing, tracking, driver identity | Needs partnership and API access |
| C. Operator partner | Airport taxi operators or fleets run the shared product | Compliance and supply | Margin sharing, slower start |

Suggested path: A as a pilot to validate demand and safety signals, then B or C once matching density is proven.

## 7. Revenue

| Stream | Mechanism | Notes |
|---|---|---|
| Service fee | Flat ₹20-40 per rider per trip, or 8-12% of the fare | Charge on the saving, so the user still wins. First model to test |
| Partner commission | 10-15% from cab operators / prepaid taxi / aggregator for demand | Needs model B or C |
| Subscription (Plus) | ₹100-200/month: women-only pools, priority matching, fee waiver, lounge-style perks | Strong for frequent flyers |
| Corporate | Employee airport travel on company account, policy, expense export, duty of care | Higher margin, safety is a selling point |
| Airport / brand partnerships | Sponsored offers: eSIM, forex, parking, lounge | Only after trust and volume exist |
| Insurance add-on | Per-trip cover, revenue share with insurer | Also reduces risk |

Illustrative unit economics (to be replaced by real data): solo fare ₹900, shared fare ₹600 per rider. Take ₹40 fee per rider plus 5% partner commission on ₹1200 total = ₹80 + ₹60 = ₹140 per shared trip of two. Costs: KYC ₹15-40 per new user, payment fees ~2%, support, safety desk, insurance. Margin depends on density and repeat rate. KYC is a one-time cost per user.

Do not monetise by selling user location or trip data.

## 8. Go to market

1. One airport (e.g. BLR), one or two terminals, a handful of destination zones.
2. Seed demand through corporates, frequent-flyer communities, co-working spaces.
3. Referral: both sides get a ride discount.
4. Marketing message: "save 30-40%, with verified people only".
5. Expand by airport once the match rate and safety numbers hold.

## 9. Metrics

- Match rate (requests matched / requests), time to match.
- Saving per rider, shared fare / solo fare.
- Repeat rate at 30 days, NPS, share of trips rated 4+.
- Safety: SOS per 10k trips, incident rate, time to resolve, ban rate.
- Verification: completion rate, fraud catch rate.
- Unit economics: contribution margin per trip, CAC.

## 10. Production architecture (beyond the POC)

- Backend: matching service with time-window plus spatial index (H3 / geohash), real-time via websockets, push notifications.
- Routing: Google Maps / MapKit / Mapbox to compute true detour and ETA.
- Flight data: arrival feed for time-aligned matching and delay handling.
- Identity: KYC vendor with e-KYC, liveness, face match. Token vault.
- Payments: gateway with split settlement and refunds.
- Safety: ops console, SOS routing, call masking, audit log, law-enforcement request workflow.
- Mobile: iOS SwiftUI, Android Compose, shared API contract (OpenAPI). Matching logic must live on the server in production; the POC keeps a copy on each client for demo only.

## 11. Roadmap

- v0 (done): POC, mock data, both platforms.
- v1: backend, real KYC, maps, payments, flight arrivals, pilot at one airport.
- v2: partner bookings, Plus, women-only pools, corporate accounts.
- v3: more airports and railway stations, more cities.

## 12. Decisions needed from you

1. Operating model (A / B / C).
2. First airport and city.
3. Women-only pool at launch or later.
4. Fee model (flat vs percentage).
5. Who handles KYC (vendor choice) and data retention length.
