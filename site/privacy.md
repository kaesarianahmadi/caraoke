# Privacy Policy — Caraoke (draft for review)

Draft for review — not yet published. Effective date: pending legal review. Contact: support@caraoke.app

## Status

This policy is being corrected to match the app's actual data flows and must
be reviewed before publication. Caraoke has no user accounts, but it does use
a lyrics relay, crash reporting, usage analytics, Spotify authorization, and
purchase infrastructure.

## What the app processes, and where it goes

| Data | Where it lives / goes | Purpose |
|---|---|---|
| Spotify OAuth tokens and your Client ID | Device shared Keychain; token requests go to Spotify | Read currently-playing track and playback state, and send playback control commands (play, pause, skip) |
| Track title, artist, duration, playback position | On-device; title/artist sent to LRCLIB and YouTube Music; duration also to LRCLIB | Match synchronized lyrics to the playing track |
| Live Activity push token, track title/artist, full lyric schedule, track start/end times, playing state | Posted to the Caraoke lyrics relay (Cloudflare Worker + Durable Object) | Push line-by-line lyrics while iOS has suspended the app |
| Cached lyrics | Device Caches folder (no in-app clear control currently) | Offline use and fewer provider requests |
| Crash reports and diagnostics | Sentry, plus the relay's crash storage (most recent 20 records) | Diagnose crashes, watchdog terminations, and non-fatal errors |
| Usage signals | TelemetryDeck | Aggregate feature usage: `paywall_viewed`, `purchase_completed` (product ID), `playback_source` (source type), `ride_started` |
| Purchase and subscription records | Apple StoreKit and RevenueCat | Entitlements, purchase validation, restore |

## Third parties

- **LRCLIB (lrclib.net) and YouTube Music (InnerTube):** Caraoke races both
  providers when matching a song. Requests include the track title and artist;
  LRCLIB also receives duration. No Caraoke account is used. Their own terms
  and privacy policies apply.
- **Caraoke lyrics relay (Cloudflare):** receives the Live Activity push
  token, track title/artist, full lyric schedule, start/end times, and playing
  state. One Durable Object is used per device, keyed by the push token. The
  relay also stores crash payloads (currently the most recent 20 records).
  Security review and deployment of access controls for these records are
  unresolved; do not treat crash reports as private or access-controlled.
- **Sentry:** receives crash and non-fatal error diagnostics, including stack
  traces and device/app metadata. Automatic session tracking and
  watchdog-termination tracking are enabled.
- **TelemetryDeck:** receives the usage signals listed above. It is designed
  for privacy-friendly analytics, but it is still a third-party analytics
  service.
- **RevenueCat:** receives purchase and subscription records and entitlement
  state, linked to the app user identifier RevenueCat uses. Apple StoreKit
  remains the transaction source.
- **Spotify:** if you connect it, Caraoke requests
  `user-read-currently-playing`, `user-read-playback-state`, and
  `user-modify-playback-state`. This means Caraoke can read playback state and
  send playback control commands. Disconnecting removes the local token; it
  does not revoke the authorization grant at Spotify. Revoke access in your
  Spotify account settings.
- **Apple:** Apple Music playback is read through MediaPlayer; purchases are
  processed by Apple.

## Retention and deletion

- Clearing the lyrics cache removes cached lyric text from the device.
  Disconnecting Spotify removes the stored Spotify token from the shared
  Keychain.
- Stopping a ride deletes the relay session only if the end request reaches
  the relay. If the app goes offline before that request succeeds, the session
  may remain until it expires. The most recent 20 crash records may remain in
  relay storage until cleared; no deletion timeline is guaranteed. Sentry,
  TelemetryDeck, RevenueCat, and Cloudflare retain data under their own
  policies.
- Uninstalling the app removes local app data, but it is not a guaranteed
  deletion of records already held by the relay, Sentry, TelemetryDeck,
  RevenueCat, Cloudflare, or Apple. Contact support@caraoke.app to request
  deletion; deletion of server-side records is not guaranteed.

## What we do not do

- No advertising and no sale of personal data
- No Caraoke accounts and no listening-history profile
- No promise that data is anonymous; the app uses the third-party services
  listed above

## Your controls

Settings → "Clear downloaded lyrics cache" removes cached lyrics. Disconnect
Spotify to remove its stored token. Stop Live Lyrics to end the relay session.
For other requests, contact support.

Children: Caraoke is not designed for children and offers no accounts. If you
believe a child's information was submitted, contact support.

This draft must be reviewed and published with an effective date before it is
relied on. Changes will be posted on this page.
