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

   Deployment, build bumps and pushes require explicit user authorization.

## Verify

Start a song and Live Lyrics, then lock the phone. Verify actual APNs delivery
through the current track, track changes, pause/resume and seeks. Route reachability
does not prove APNs readiness; a current-track schedule alone cannot follow a new
track while the app is suspended.

Local access-boundary regression: `node relay/worker.test.mjs`.

## Notes / limits

- Playback sessions are routed by Live Activity push token, not one global ride.
- Line-boundary pushes only; the progress bar recalculates at each push.
  A per-10s heartbeat keeps the last line's activity fresh until `endAt`.
- APNs is rate-tolerant at this volume; no retry/backoff implemented yet —
  if a push fails (device offline), the next boundary push self-heals.

## Security

- Durable Objects persist lyric schedules and activity push tokens. Successful end
  handling deletes a session; do not promise immediate deletion after network failure.
- Provider JWTs are cached and signed with the server-side APNs key. Do not log keys
  or full activity tokens.
- Crash ingestion retains the most recent 20 reports. Public GET/DELETE `/crashes`
  routes were removed locally after an unauthenticated HTTP 200 was observed on
  2026-11-14; the deployed service remains exposed until an authorized deployment.
- No relay deployment or live APNs registration/push was performed during this audit.