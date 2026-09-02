# Caraoke Lyric Relay (mechanism #2)

Background lyric updates for the locked-phone / driving case. iOS suspends the
app ~30 s after backgrounding (measured on device in Phase C), so no app code
can keep pushing Live Activity updates. The relay solves it with Apple's
documented store-safe path: **APNs push-updated Live Activities**.

Flow:

```text
App (Ride Mode starts, lyrics fetched)
  ├─ computes full lyric schedule (lines + wall-clock startEpochMs)
  ├─ POSTs {activityPushToken, trackTitle, trackArtist,
  │         startEpochMs, lines:[{t,text}], endAtEpochMs}
  │         → https://caraoke-lyrics-relay.<subdomain>.workers.dev/sessions
  └─ relay (this worker) fires an APNs live-activity push at each line
     boundary; lyrics keep advancing while the phone is locked in the car
```

One Durable Object holds the single active ride; a DO alarm wakes at each
line boundary, pushes the new line, and re-arms. When `endAtEpochMs` passes it
sends the `end` event and forgets the session.

## Cost

Cloudflare Workers free tier: 100k requests/day, Durable Objects included
(DO writes are metered but trivial at MVP scale). This is a handful of pushes
per song per user — effectively $0.

## Deploy (once, ~10 minutes)

Prereqs: a free Cloudflare account and the **APNs Auth Key** from Apple:

1. **Create the APNs key** — developer.apple.com → *Account → Certificates,
   Identifiers & Profiles → Keys* → ➕ → tick **Apple Push Notifications
   service (APNs)** → **Continue → Register → Download**.
   - You get `AuthKey_<KEYID>.p8` **once**, keep it safe.
   - Note the **Key ID** (shown in the keys table) and your **Team ID**
     (account → Membership).

2. **Deploy this folder:**

   ```sh
   cd relay
   npx wrangler@latest deploy
   ```

3. **Set the secrets** (the APNs key is the ONLY server-side secret):

   ```sh
   npx wrangler secret put APNS_KEY_P8        < AuthKey_XXXXXXXXXX.p8
   npx wrangler secret put APNS_KEY_ID        # e.g. ABC123DEFG
   npx wrangler secret put APNS_TEAM_ID       # 10-char team id
   npx wrangler secret put APP_BUNDLE_ID      # app.caraoke.ios
   ```

4. **Point the app at it.** In `CaraokePOC/Sources/CaraokeCore/FeatureFlags.swift`
   set:

   ```swift
   static let relayBaseURL: URL? = URL(string: "https://caraoke-lyrics-relay.<your-subdomain>.workers.dev")
   ```

   Then bump `CURRENT_PROJECT_VERSION` in `CaraokePOC/project.yml` and push —
   CI builds + uploads the next TestFlight build automatically.

## Verify

Start a song, start Ride Mode, lock the phone. Lyrics on the Lock Screen /
Dynamic Island should keep advancing for the full song. Without it, they
freeze ~30 s after locking (with it, they run the whole drive).

## Notes / limits

- One session at a time (one DO, named `caraoke-ride`) — matches the product:
  one active ride per device.
- Line-boundary pushes only; the progress bar recalculates at each push.
  A per-10s heartbeat keeps the last line's activity fresh until `endAt`.
- APNs is rate-tolerant at this volume; no retry/backoff implemented yet —
  if a push fails (device offline), the next boundary push self-heals.

## Security

- No user accounts, no lyrics stored server-side beyond one session window
  (the DO deletes on end).
- The APNs provider token is minted per request from `APNS_KEY_P8` — never
  logged, never exposed.
- The endpoint is open (fires pushes to tokens the relay was given) — the
  session POST carries only the device's own activity token, so abuse is
  limited to pushing that device's own activity.