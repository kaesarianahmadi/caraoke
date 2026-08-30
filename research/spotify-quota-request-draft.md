# Spotify Extended Quota — Request Draft

Paste-adapt this into the Spotify Developer Dashboard
(developer.spotify.com/dashboard → your app → Extensions & Quotas / "Request
Extended Quota"). Fill the bracketed parts. Submit AFTER enrolling in the
Apple Developer Program if possible — a public TestFlight/App Store timeline
makes the request credible.

---

**Subject / Use case:** Caraoke — live lyrics companion for CarPlay (iPhone)

**Describe your app and how it uses the Spotify Web API:**

Caraoke is an iPhone app that displays time-synced song lyrics during shared
car rides, mirroring the current lyric line onto the car's CarPlay screen via
an iOS Live Activity. The app never plays audio itself and never modifies
playback — it reads the user's currently-playing track and position to keep a
community-sourced lyric display in sync.

Spotify integration is read-only and limited to:
- OAuth 2.0 authorization code + PKCE (scopes: `user-read-currently-playing`,
  `user-read-playback-state`)
- Polling `GET /v1/me/player/currently-playing` at a low fixed rate
  (5 s while actively playing, 15 s while idle)

**How many users do you expect?** Launch phase: TestFlight beta ≈100 users;
first App Store year target ≈2,000–10,000 installs. Polling is bounded at
≈12 requests/user/hour of active listening (throttled + cached client-side).

**Why do you need extended quota?** Spotify's Development Mode caps connected
users at 25, which prevents any public TestFlight distribution. The app is
built and in device testing; extended quota is required for beta and launch.

**Compliance commitments:**
- Official Web API endpoints only; no scraping, no unofficial endpoints
- Tokens stored in the iOS Keychain, never synced off-device
- No user data sold, shared, or used for advertising; no listening history
  stored server-side (the app has no server)
- Low-rate polling with exponential backoff honoring `Retry-After`
- App displays lyrics attributed to their community source; support contact:
  [your support email]

---

## Hedging note (internal, do not submit)

Spotify's platform policy restricts *synchronizing sound recordings with
visual media*. Our read: displaying separately sourced lyric text next to
playback state is not audio-visual synchronization, and multiple Spotify-
compatible lyric apps are live on the App Store (Musixmatch has agreements;
smaller apps operate in the same gray zone we've chosen). Mitigations ready:
Spotify is flag-gateable in one commit if Spotify objects, and the App Store
listing will not advertise Spotify support until the integration is approved
and device-tested.
