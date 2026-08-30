# driveverse — Direct Audit (2026-08-29)

Cloned `github.com/praveetgupta/driveverse` (HEAD, 2026-07-22) and read the full
source. This answers: *"Can we rebrand it and start from there instead of
building Caraoke from scratch?"*

## What it actually is (verified)

| Fact | Evidence |
|---|---|
| MIT License © 2026 Praveet Gupta — rebrand/sublicense/sell is **legally allowed** (keep the copyright notice) | `LICENSE` |
| ~4,050 lines Swift, full Xcode project: app target + Live Activity widget + **13 test files**, iOS 26.0 target, Swift 5, **zero third-party dependencies** | file inventory, `project.pbxproj` |
| It was itself built with an AI agent (a complete `CLAUDE.md` build brief) | `CLAUDE.md` |
| Apple Music detection = **public MediaPlayer framework** (`MPMusicPlayerController.systemMusicPlayer` + notifications + 1 s poll). **No MusicKit, no developer token, no backend needed** | `Core/NowPlaying/AppleMusicSource.swift` |
| Spotify = **official OAuth authorization-code + PKCE** (`accounts.spotify.com`, `ASWebAuthenticationSession`) — *not* "unofficial" as our research doc first said | `Core/Auth/SpotifyAuth.swift` |
| Live Activity lifecycle is genuinely production-grade: one session-spanning activity, foreground-only `Activity.request` + `LiveActivityIntent` bypass for background start, update throttling/coalescing (never drops a line), orphan cleanup, `activityStateUpdates` watcher, 30 s grace end | `LiveActivity/LiveActivityController.swift`, `Policy`, `Throttle`, `App/DriveModeIntents.swift` |
| CarPlay = `.supplementalActivityFamilies([.small])` + `activityFamily == .small` branch (same pattern we implemented independently) | `DriveVerseWidgets/LyricsLiveActivity.swift` |
| Drive Mode keep-alive = **coarse background location session** (3 km accuracy, never stores fixes) purely to keep the process alive and keep LA-update permission | `Core/KeepAlive/BackgroundKeeper.swift` |
| Lyrics = **LRCLIB public API only** (unkeyed, community database), 30-day local cache, normalization + duration-tolerant matching fallback chain | `Core/Lyrics/*`, `CLAUDE.md` §4–5 |

## Why "rebrand and ship to the App Store" fails (author's own words)

1. **The lyrics are not store-legal.** README: *"It is **not** okay for the App
   Store without a proper licensed lyrics provider, so please don't ship it
   there."* CLAUDE.md §5: *"this app must not be distributed on the App Store
   without a licensed lyrics provider."* Every lyric line comes from LRCLIB —
   fine for personal use, not a defensible foundation for a paid product.
2. **The keep-alive will be rejected in App Review.** Code comment:
   *"using location purely as a keep-alive would be rejected in App Review…
   a store build would need push-updated activities instead."* The mechanism
   that keeps lyrics flowing on a long drive is exactly what a store build
   cannot use. The store-safe path is push-based activity updates — which
   requires the backend we were always going to build.
3. **There is no backend to inherit.** The app is 100% client-side ("No
   account… no server, no analytics"). "All the backends it uses" = none;
   LRCLIB is someone else's public API. Lyrics licensing + a tiny secret-holding
   backend + StoreKit/RevenueCat paywall — the actual business layer — **do not
   exist in the repo at all** (no IAP code anywhere).
4. Spotify is dead for a paid product regardless of code quality: Spotify's
   platform policy restricts syncing its recordings with visual media. (The
   blocker is policy, not the auth flow.)

## Verdict

**Rebrand-and-ship as-is: NO** — it legally can, but it ships unlicensed
lyrics + a review-rejected background mechanism, and inherits none of the
commercial layer. The repo is ~90% the same *concept*, but the 10% that makes
Caraoke a business is precisely the part it never solved.

**Use as a donor of hard-won modules: YES** — this is the real value.

## Port plan (into CaraokePOC, keeping our identity + license hygiene)

**Port (MIT, keep attribution notice):**
1. `LiveActivityController` + `LiveActivityUpdatePolicy` + `LiveActivityUpdateThrottle`
   — lifecycle correctness we have not solved yet (orphan cleanup, coalescing,
   background-update realities, session-spanning activity).
2. `NowPlayingSource` protocol + `AppleMusicSource` — replaces our assumed
   MusicKit path with the simpler **no-token MediaPlayer** approach. Note: uses
   media-library authorization (`MPMediaLibrary.authorizationStatus()`).
3. `DriveModeIntents` (`LiveActivityIntent` start/stop) — the one legal way a
   background context may start/restart an activity.
4. `LRCParser` + `LyricsMatcher` + track normalization — feed them from *our*
   licensed provider later; they are source-agnostic.

**Replace / build (the actual product):**
1. LRCLIB → licensed lyric provider (e.g. Musixmatch commercial API) behind our
   `LyricsRepository`; lyrics cost shapes pricing/lifetime decisions.
2. Location keep-alive → App-Store-safe background strategy: push-updated
   activities (APNs + frequent-update entitlement) backed by a small backend —
   or accept foreground-limited behavior for early TestFlight builds and be
   honest about it.
3. Their UI → Caraoke identity from OpenDesign (the PRD's four states, our
   palette, our onboarding); keep MIT attribution in the repo/legal docs.
4. Spotify → cut for MVP.

**Keep ours:** CaraokeCore timing engine (41/41 tests pass), the PRD state
model, original fixtures.

## Unchanged constraint

Nothing here dodges the build wall: iOS 26.0 target needs Xcode 26 + a real
device for Apple Music detection — impossible on this Mac (CLT only). Fork or
original, cloud CI or a modern Mac is still the gate.
