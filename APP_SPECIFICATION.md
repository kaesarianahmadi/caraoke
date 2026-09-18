# Caraoke — Complete Architecture & Component Specification Audit

> **Document Purpose:** Complete technical audit and component dictionary of the entire Caraoke codebase. Use this reference to identify specific components, files, data flows, and widget families when triaging defects or planning subsequent builds.

---

## 1. System Architecture & Cross-Process Topology

Caraoke is structured as a multi-target iOS system with an out-of-process Cloudflare Worker relay. The project bypasses traditional App Group filesystem containers (which require non-standard provisioning entitlements) by utilizing Apple Keychain Access Groups for zero-delay cross-process state synchronization.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        MAIN APP (Caraoke Target)                       │
│  - SwiftUI UI (Home, Settings, Paywall, Fullscreen Lyrics)              │
│  - RidePlaybackController (NowPlaying Coordinator & SyncEngine)        │
│  - RideAudioKeeper (Background silent audio loop to prevent suspension)│
│  - SpotifyAuth & AppleMusicSource (MediaPlayer observer)              │
│  - FallbackLyricsProvider (Concurrent race: LRCLIB vs YouTube Music)   │
│  - CaraokeActivityController (ActivityKit lifecycle & throttling)      │
└───────────────┬────────────────────────────────────────┬───────────────┘
                │                                        │
    Writes Payload & Settings                Registers Push Token &
    to Shared Keychain Access Group          Lyric Schedule via POST
    ("R3Y5ZR429L.app.caraoke.ios")           to Cloudflare Worker
                │                                        │
                ▼                                        ▼
┌───────────────────────────────┐        ┌───────────────────────────────┐
│ WIDGET EXTENSION (CaraokeWidgets)│        │   CLOUDFLARE WORKER RELAY     │
│  - CaraokeWidgetBundle        │        │   (Durable Objects: APNs)     │
│  - CaraokeWidget (Timeline)   │        │  - APNs ES256 JWT Generator   │
│    • Small (2x2)              │        │  - Line-boundary Alarms       │
│    • Medium (2x4 Vinyl disc)  │        │  - Dispatches APNs push to    │
│    • Large (4x4 Huge square)  │        │    Lock Screen Live Activity  │
│  - LyricsLiveActivity         │        │    when iOS suspends app      │
│    • Lock Screen Banner       │        └───────────────┬───────────────┘
│    • Dynamic Island           │                        │
│    • CarPlay Mirror Tile      │                        ▼
│  - Interactive AppIntents     │        ┌───────────────────────────────┐
│  - Autonomous WidgetResync    │◄───────┤    LOCK SCREEN LIVE ACTIVITY  │
└───────────────────────────────┘        └───────────────────────────────┘
```

---

## 2. Widget & Live Activity Component Specifications

### 2.1 Widget Extension Entry Point & Matrix

* **`iOS/CaraokeWidgetBundle.swift`**
  * **Role:** Entry point annotated with `@main` implementing `WidgetBundle`.
  * **Declared Widgets:**
    1. `LyricsLiveActivity()`: Dynamic Island and Lock Screen Live Activity.
    2. `CaraokeWidget()`: Persistent desktop/Home Screen widget supporting 3 size classes (`systemSmall`, `systemMedium`, `systemLarge`).
    3. `CaraokePlayerWidget()`: CarPlay stack tile — cover, identity, progress, transport intents (`systemSmall` only).
    4. `CaraokeLyricsWidget()`: CarPlay stack tile — lyrics only (`systemSmall` only).
    5. `CaraokeHybridWidget()`: CarPlay stack tile — lyric block over a player bar (`systemSmall` only).

### 2.1.1 CarPlay Widget Stack (`iOS/CarPlayWidgets.swift`)

* **Apple's constraint:** CarPlay renders *only* the `systemSmall` family — it scales that one family to the tile regardless of what else a widget declares. `.systemMedium` and `.systemLarge` never appear in the CarPlay widget picker, which is why the 4x4 widget cannot be a CarPlay stack entry.
* **Add path:** iPhone `Settings → General → CarPlay → [car] → Customize → Widgets` (up to five tiles per stack, two stacks side-by-side on widescreen head units).
* **Interaction:** On touchscreen head units a widget's `Button(intent:)` runs its `AppIntent` directly; on non-touch displays the system dims the widget and the buttons are inert. This is why the transport row is built from `PreviousTrackIntent` / `PlayPauseIntent` / `NextTrackIntent` rather than a static glyph.
* **Layer 1 — `CaraokePlayerWidget`:** Cover (tap = `ResyncWidgetIntent`), title/artist, 3 pt progress bar, interactive transport row.
* **Layer 2 — `CaraokeLyricsWidget`:** `LyricTileView` on the `.carPlaySmall` surface with zero player chrome.
* **Layer 3 — `CaraokeHybridWidget`:** The `.widgetLarge` layout folded into one small tile — lyric block at ~62% height, then a compact cover + identity + transport bar underneath.

---

### 2.2 Home Screen & Dashboard Widgets (`CaraokeWidget.swift`)

* **`iOS/CaraokeWidget.swift`**
  * **Role:** Declares the persistent `CaraokeWidget: Widget` with `StaticConfiguration` and `CaraokeWidgetProvider: TimelineProvider`.
  * **Timeline Architecture:** Instead of querying the app every few seconds (which rapidly exhausts iOS WidgetKit background execution budgets), `WidgetTimelineBuilder` precomputes timeline entries for every single lyric line for the remainder of the track using `trackStartEpochMs`. The widget transitions lines on its own clock without waking the main app.
  * **Supported Widget Families:**
    1. **Small Widget (`.systemSmall` — 2x2 grid, 158×158 pt):**
       * *Renderer:* `LyricTileView` with surface `.widgetSmall`.
       * *Layout:* Compact header row (track title and artist), active lyric hero row (wrapped up to 2 rows), 2 following preview lines, and bottom progress bar. No interactive transport buttons due to tight touch target constraints.
       * *Deep Link:* Tapping anywhere launches `caraoke://lyrics` to open the full-screen karaoke page.
    2. **Regular / Medium Widget (`.systemMedium` — 2x4 grid, 338×158 pt):**
       * *Renderer:* `VinylWidgetView(entry: entry)`.
       * *Layout:* Two-column horizontal split.
         * **Left Column (60% width):** Compact track identity header, 3 lines of lyrics (1 previous line at 42% opacity, 1 active line in semibold white wrapping up to 2 rows, 1 next line at 62% opacity), and an interactive transport bar (`PreviousTrackIntent`, `PlayPauseIntent`, `NextTrackIntent`).
         * **Right Column:** Large realistic spinning vinyl record with track cover center-label (or square album art based on settings).
         * **Autonomous Resync:** The cover/vinyl is an interactive button bound to `ResyncWidgetIntent`. If out of sync, an overlay refresh icon appears; tapping directly queries Spotify and LRCLIB in the background without launching the app.
    3. **Huge / Large Widget (`.systemLarge` — 4x4 grid, 375×375 pt):**
       * *Renderer:* `LyricTileView` with surface `.widgetLarge`.
       * *Layout:* Lyrics dominate the top 75% of the widget (allowing multiple previous lines, wrapped active hero line, and upcoming lines). The bottom 25% houses a dedicated player bar: square album cover (with resync capability), track title and artist, and large interactive transport buttons (`Previous`, `Play/Pause`, `Next`).
       * *Theme Tint:* Dynamically tints its background using the average color extracted from the album artwork (`artworkColorHex`).

---

### 2.3 Live Activities & Dynamic Island (`LyricsLiveActivity.swift`)

* **`iOS/LyricsLiveActivity.swift`**
  * **Role:** Declares `LyricsLiveActivity: Widget` implementing `ActivityConfiguration(for: LyricsActivityAttributes.self)`.
  * **Surface Renderers & Layouts:**
    1. **Lock Screen Live Activity Banner (`FamilyAdaptiveTile` -> `.lockBanner`):**
       * Native iOS 26 translucent dark glass aesthetic (relies on system glass material; does not draw an opaque card).
       * Compact track title and artist header.
       * Centered vertical lyric block showing the previous line, active semibold hero line, and next line.
       * Bottom progress bar with elapsed (`positionMs`) and remaining time indicators.
    2. **CarPlay Supplemental Tile (`.carPlaySmall`):**
       * Enabled via `.supplementalActivityFamilies([.small])`.
       * Automatically rendered on the Apple CarPlay dashboard and Apple Watch Smart Stack (iOS 17.2+).
       * Paints its own dark background card for contrast because CarPlay dashboard does not apply system background blur.
       * **Build 46 typography:** renders at `LyricType.carPlayLyric` (12 pt), the only surface below the shared 18 pt scale, because the dashboard mirror is the smallest surface and 18 pt overran it. No `minimumScaleFactor` and no `.truncationMode` anywhere — a line that does not fit carries onto the next row at the same size (hero allowance is 3 rows inside a 119 pt block, worst case 81 pt).
       * **Build 46 identity rule:** the title/artist row is an *intro*, shown from song start until the first lyric line arrives, then removed so the lyrics own the tile and the active line stays vertically centred.
    3. **Dynamic Island — Compact Leading (`compactLeading`):**
       * Dynamic status icon: animated music note glyph when playing, pause icon when paused. Zero distracting colored dots.
    4. **Dynamic Island — Compact Trailing (`compactTrailing`):**
       * `IslandCompactText`: 13px semibold white text displaying the active lyric line (or state message like "Finding lyrics…" or "Ride ended") with tail truncation.
    5. **Dynamic Island — Minimal (`minimal`):**
       * Used when multiple Live Activities share the island. Displays a 10px music note plus an 11px truncated lyric text capsule.
    6. **Dynamic Island — Expanded Presentation (`DynamicIslandExpandedRegion`):**
       * *Leading Region:* Play/pause glyph.
       * *Center Region:* 16pt bold white active lyric line (up to 2 lines) plus 13pt 55% opacity next lyric preview line. Shows skeleton loader bars when loading, or empty-state messaging when no lyrics exist.
       * *Bottom Region:* "Caraoke" pill badge with an integrated 3px slim track progress bar. Deliberately omits transport buttons per safety and usability design guidelines.

* **`iOS/LyricsActivityAttributes.swift`**
  * **Role:** Conforms to `ActivityAttributes`. Defines `ContentState` serialized by ActivityKit on every update.
  * **Payload Properties:** Minimal footprint (`title`, `artist`, `currentLine`, `previousLines`, `nextLine`, `upcomingLines`, `isPlaying`, `progress`, `status`, `positionMs`, `durationMs`). Omits heavy image binary data to prevent IPC bottlenecks.

* **`iOS/LyricsActivityController.swift` (`CaraokeActivityController`)**
  * **Role:** `@MainActor` singleton/manager for the Live Activity lifecycle.
  * **Key Responsibilities:**
    * Eagerly requests the Live Activity on Ride Mode activation (`startIdle()`) so the banner is visible before audio begins.
    * Monitors system permissions (`ActivityAuthorizationInfo().areActivitiesEnabled`).
    * Captures and delivers APNs push tokens (`activity.pushTokenUpdates`) to `LyricsRelayClient`.
    * Integrates `ActivityUpdatePolicy` and `ActivityUpdateThrottle` to coalesce rapid line changes (enforcing a minimum 1.5-second spacing to prevent iOS rate-limiting, while permitting instant track skips and play/pause toggles).

---

### 2.4 Widget Supporting & Styling Components

* **`iOS/VinylWidgetView.swift`**
  * **Role:** Dedicated SwiftUI layout for the medium 2x4 Home Screen widget.
  * **Key Features:** Proportional width calculation (60% lyrics, 40% vinyl disc), static rendering to avoid flash during WidgetKit timeline transitions, AppIntents transport integration, and embedded resync button.
* **`iOS/WidgetArtworkBackground.swift`**
  * **Role:** Dynamic background renderer shared across both targets (`Caraoke` and `CaraokeWidgets`). If theme is `.artwork`, generates a smooth linear gradient using the dominant album cover hex color; otherwise falls back to solid OLED black or Ivory white.
* **`iOS/SharedWidgetStore.swift`**
  * **Role:** Cross-process storage engine using the shared Keychain (`R3Y5ZR429L.app.caraoke.ios`).
  * **Stored Items:** `SharedWidgetPayload` (track metadata, timestamps, all timed lines), `SharedWidgetSettings` (theme, vinyl vs square cover style), and Spotify OAuth credentials for out-of-process background widget calls.
* **`iOS/WidgetResync.swift`**
  * **Role:** Standalone background resynchronization engine executed inside the widget extension process when `ResyncWidgetIntent` is triggered. Directly queries Spotify's `/v1/me/player` API, re-anchors clock drift, fetches LRCLIB lyrics if track changed, updates `SharedWidgetStore`, and reloads WidgetKit timelines.
* **`iOS/WidgetSettingsView.swift`**
  * **Role:** In-app settings sheet for customizing widgets.
  * **Features:** Live interactive preview of the medium widget, theme picker (Artwork / OLED Dark / Ivory Light), cover style toggle (Vinyl disc vs Album square), and step-by-step troubleshooting guide for real-time widget updates.

---

## 3. Frontend / In-App UI Components (`iOS/`)

* **`iOS/CaraokeApp.swift`**
  * **Role:** Application root `@main`.
  * **Lifecycle:** Initializes `CrashReporter`, applies saved theme mode, mirrors bundled Spotify Client ID to shared Keychain, and re-verifies Live Activity persistence upon `scenePhase == .active`.
* **`iOS/HomeView.swift`**
  * **Role:** Primary dashboard screen.
  * **Visual Hierarchy:**
    1. *Header:* Caraoke wordmark, Help/FAQ button (`https://caraoke.live/docs`), and Settings gear.
    2. *Status & Action Banners:* Setup instructions and system permission status.
    3. *Live Activities Card:* Master toggle, diagnostic states, and lock screen guide.
    4. *Widgets Section:* Interactive widget preview linking to `WidgetSettingsView`.
    5. *Music Sources Section:* Apple Music vs Spotify connection tiles and source selector.
    6. *Floating Mini-Player:* Persistent bottom dock displaying album artwork, track title, artist, source badge, and playback controls. Tapping expands `LyricsPageView`.
    7. *URL Scheme Handler:* Routes `caraoke://lyrics` deep links to immediate full-screen presentation.
* **`iOS/LyricsPageView.swift`**
  * **Role:** Immersive full-screen karaoke lyrics stage.
  * **Visual Design:** Full viewport cover artwork color wash (`CoverArtworkView.wash`), header with track metadata and dismiss chevron, auto-scrolling lyrics list (`ScrollViewReader`) pinned to center at 45% viewport height, dynamic line highlighting, and bottom transport bar with scrub progress.
* **`iOS/SettingsView.swift`**
  * **Role:** Modal settings screen.
  * **Sections:** Caraoke Plus premium banner, Connect Music (Apple Music authorization and Spotify custom Client-ID configuration), Appearance selector (`AppearanceSheet`), Support & About (Terms, Privacy, Docs, Developer contact), and build version telemetry.
* **`iOS/PaywallView.swift`**
  * **Role:** Dark OLED conversion paywall.
  * **Offers:** Monthly ($1.99, 3-day free trial), Yearly ($9.99, 3-day free trial, recommended), and Founding Lifetime ($14.99, 45% discount).
  * **Actions:** In-app purchase via `PurchaseManager`, Restore Purchases, legal links.
* **`iOS/SpotifySetupView.swift`**
  * **Role:** Dedicated onboarding sheet for Spotify developer credentials.
  * **Guide:** Walkthrough for creating a free app on `developer.spotify.com`, setting redirect URI `caraoke://spotify-callback`, pasting Client ID, and executing initial OAuth connection.
* **`iOS/LyricTileView.swift`**
  * **Role:** The universal core rendering component used across all surfaces (`lockBanner`, `carPlaySmall`, `widgetSmall`, `widgetMedium`, `widgetLarge`, and `home`).
  * **Design Contract:** Eliminates font-shrinking bugs by enforcing wrapped lines at standard typography rules (`LyricType`), calculating strict vertical pixel budgets (`LyricTileLayout`), and vertically centering lyric blocks.
* **`iOS/AppTheme.swift`**
  * **Role:** Design tokens and graphical helpers.
  * **Tokens:** Pure OLED Black (`0x000000`), Zinc dark surface (`0x121214`), Ivory White light mode (`0xFAFAFA`), Brand Orange accent (`0xFF9845`), status green/orange/red.
  * **Sub-views:** `CoverArtworkView` (album art / vinyl disc fallback), `VinylRecordView` (realistic record grooves and spinning label), and CoreImage-based average color extraction (`averageColorHex`).
* **`iOS/AppearanceSettings.swift`**
  * **Role:** State manager for Auto / Light / Dark modes. Modifies `overrideUserInterfaceStyle` across all active UIWindowScenes.
* **`iOS/CaraokeLogo.swift` & `iOS/SpotifyLogo.swift`**
  * **Role:** Resolution-independent vector shapes drawn using pure SwiftUI `Shape` paths matching official branding SVGs.
* **`iOS/DemoLyrics.swift`**
  * **Role:** Bundled copyright-free demo track ("Road Trip Anthem" by Cibul & Njun) for offline testing, App Store review, and simulator runs.

---

## 4. State Management, Audio & Background Engine

* **`iOS/RideModeViewModel.swift`**
  * **Role:** Master ViewModel powering all SwiftUI screens.
  * **State:** Published properties for Ride Mode toggle (`isOn`), active lyric lines (`currentLine`, `previousLines`, `nextLine`, `upcomingLines`, `allLines`), playback clock (`positionMs`, `durationMs`), `lyricStatus`, artwork data, and active music source selection (`.appleMusic`, `.spotify`, `.auto`).
  * **Bindings:** Bridges between UI actions and `RidePlaybackController`.
* **`iOS/RidePlaybackController.swift`**
  * **Role:** The master pipeline coordinator.
  * **Data Flow:**
    1. Listens to `AppleMusicSource` and `SpotifySource` via `NowPlayingCoordinator`.
    2. Feeds track metadata into `SyncEngine` for millisecond-level position extrapolation.
    3. Triggers lyrics retrieval from `FallbackLyricsProvider` (caching results to disk).
    4. Updates `CaraokeActivityController` (Live Activity) with throttled snapshots.
    5. Syncs state to `SharedWidgetStore` for WidgetKit consumption.
    6. Registers background push schedules with `LyricsRelayClient`.
    7. Controls `RideAudioKeeper` background audio loop.
* **`iOS/RideAudioKeeper.swift`**
  * **Role:** Background execution keeper. Loops the inaudible `ride-keeper.wav` (~-68 dBFS) in an `.playback` + `.mixWithOthers` session so iOS does not suspend Caraoke 30 s after the screen locks.
  * **Build 46 — the freeze fix:** observes `AVAudioSession.interruptionNotification` and `routeChangeNotification` and re-arms the player. Previously a CarPlay navigation prompt, Siri request, or phone call paused the keeper with nothing to resume it; iOS then suspended the process and the lyric tile froze mid-song while the music kept playing. `players` are reused across interruptions rather than rebuilt.
  * **Role:** Background process persistence manager.
  * **Technique:** Plays an inaudible, looping audio sample (`ride-keeper.wav`, ~-68 dBFS) configured with `AVAudioSession.Category.playback` and `[.mixWithOthers]`. This keeps Caraoke alive in the background under iOS `audio` background modes without interrupting or ducking the user's music, allowing the app to detect track skips and keep Live Activities updated.
* **`iOS/TransportControl.swift`**
  * **Role:** Unified transport routing engine for widget buttons and in-app controls.
  * **Logic:** Dispatches `playPause`, `next`, and `previous` commands to either `MPMusicPlayerController.systemMusicPlayer` (Apple Music) or Spotify Web API (`/v1/me/player/*` targeting active `device_id`).
* **`iOS/TransportIntents.swift`**
  * **Role:** Interactive `AppIntent` definitions (`PreviousTrackIntent`, `PlayPauseIntent`, `NextTrackIntent`, `ResyncWidgetIntent`) callable from iOS 17+ widgets.
* **`iOS/RideModeIntents.swift`**
  * **Role:** `LiveActivityIntent` definitions (`StartRideModeIntent`, `StopRideModeIntent`, `CaraokeShortcuts`) allowing Siri and Shortcuts to toggle Ride Mode even when the app is suspended.
* **`iOS/AppModel.swift`**
  * **Role:** Singleton bridge ensuring background `LiveActivityIntent` executions share the identical `RideModeViewModel` instance with the foreground UI.
* **`iOS/LyricsRelayClient.swift`**
  * **Role:** HTTP client communicating with the Cloudflare Worker. Registers the full lyric schedule and Live Activity push token once per song so the server can push APNs updates when the phone is locked.
* **`iOS/CrashReporter.swift`**
  * **Role:** Dual-layer crash and diagnostics reporter combining `NSSetUncaughtExceptionHandler` with Apple `MetricKit` (`MXMetricManagerSubscriber`), uploading crash logs to the relay `/crashes` endpoint.

---

## 5. Music Sources & Authentication

* **`iOS/AppleMusicSource.swift`**
  * **Role:** Zero-backend Apple Music playback observer.
  * **Implementation:** Uses Apple's public `MediaPlayer` framework (`MPMusicPlayerController.systemMusicPlayer`). Observes system music player notifications and polls every 1 second. Operates without developer tokens or MusicKit backend requirements.
* **`iOS/SpotifyAuth.swift`**
  * **Role:** iOS-specific Spotify authentication manager.
  * **Implementation:** Executes OAuth 2.0 PKCE via `ASWebAuthenticationSession` against `accounts.spotify.com/authorize`. Persists tokens and Client ID in `SharedKeychain` so widget extensions can execute background token refreshes.
* **`Sources/CaraokeCore/SpotifyAuthCore.swift`**
  * **Role:** Platform-agnostic RFC 7636 PKCE crypto generator (SHA-256 code challenge and verifier), token model, and refresh policy logic.
* **`Sources/CaraokeCore/SpotifySource.swift`**
  * **Role:** Official Spotify Web API polling client (`/v1/me/player/currently-playing`). Polls every 2 seconds when active, 15 seconds when idle. Handles 403 allowlist restrictions gracefully.
* **`Sources/CaraokeCore/NowPlaying.swift`**
  * **Role:** Platform-neutral definitions of `MusicSource`, `NowPlayingState`, and `NowPlayingSource` protocol.
* **`Sources/CaraokeCore/NowPlayingCoordinator.swift`**
  * **Role:** Combine-based playback arbiter (`NowPlayingArbiter`). Resolves conflicting playback streams between Apple Music and Spotify based on runtime pin (`.auto`, `.appleMusic`, `.spotify`). Under `.auto`, active local playback from Apple Music takes precedence over network-polled Spotify playback.

---

## 6. Lyrics Engine & Synchronization (`Sources/CaraokeCore/`)

* **`Sources/CaraokeCore/SyncEngine.swift`**
  * **Role:** High-precision lyrics extrapolation engine.
  * **Capabilities:** Evaluates playback clock reports on a 250ms tick. Tolerates network jitter (≤500ms ignored to prevent UI jumpiness), slews drift smoothly (500–1000ms), and snaps immediately on manual seeks (>1000ms). Emits `LyricsPosition` with current, previous, and upcoming lines.
* **`Sources/CaraokeCore/FallbackLyricsProvider.swift`**
  * **Role:** Concurrent racing lyrics repository.
  * **Mechanism:** Uses Swift structured concurrency (`withTaskGroup`) to race `LRCLIBLyricsProvider` (fast, ~300ms) and `YouTubeMusicLyricsProvider` (~1.4s). Whichever provider returns valid synced lyrics first wins; the slower task is immediately cancelled.
* **`Sources/CaraokeCore/LRCLIBLyricsProvider.swift`**
  * **Role:** Keyless REST API client for `https://lrclib.net`.
  * **Strategy:** Cache-first lookup -> exact match `GET /api/get` -> search match `GET /api/search` -> fallback to stale cache on network failure. Enforces rate limits (HTTP 429 backoff).
* **`Sources/CaraokeCore/YouTubeMusicLyricsProvider.swift`**
  * **Role:** Keyless InnerTube API (`WEB_REMIX`) client retrieving licensed Musixmatch and LyricFind lyrics syndicated by YouTube Music.
  * **Pipeline:** 3-stage POST flow: `/youtubei/v1/search` (finds video ID) -> `/youtubei/v1/next` (resolves lyrics `browseId`) -> `/youtubei/v1/browse` (extracts timed lyric cue blocks).
* **`Sources/CaraokeCore/LRCParser.swift`**
  * **Role:** Pure standard LRC parser supporting multi-timestamp lines, fractional seconds, and `[offset:±ms]` adjustments.
* **`Sources/CaraokeCore/TimedLyricParser.swift`**
  * **Role:** Parser for tab-separated offline fixture files (`demo_lyrics.tsv`).
* **`Sources/CaraokeCore/LyricTrack.swift`**
  * **Role:** High-performance lyric track data structure. Uses binary search (`lineIndex(at:)`) to locate active lines at millisecond timestamps in $O(\log n)$ time.
* **`Sources/CaraokeCore/LyricLine.swift`**
  * **Role:** Value struct storing `startMs`, `text`, and optional `translation`.
* **`Sources/CaraokeCore/LyricSnapshot.swift` & `LyricSnapshotBuilder.swift`**
  * **Role:** Immutable point-in-time snapshots consumed by Live Activities and UI rendering passes.
* **`Sources/CaraokeCore/LyricStatus.swift`**
  * **Role:** 6-state lifecycle enum (`playing`, `paused`, `noLyrics`, `loading`, `stale`, `idle`) driving badges and empty states.
* **`Sources/CaraokeCore/LyricType.swift`**
  * **Role:** Design type system and vertical pixel budget calculator. Defines uniform 18pt typography with wrapping rules to prevent text clipping across widgets.
* **`Sources/CaraokeCore/LyricsDiskCache.swift`**
  * **Role:** Local filesystem cache with atomic JSON storage, 30-day TTL, and offline fallback.
* **`Sources/CaraokeCore/TrackMatcher.swift`**
  * **Role:** String sanitization engine. Strips bracketed metadata, feat clauses, and remasters, bucketing durations to 5-second intervals to generate reliable cache keys.
* **`Sources/CaraokeCore/WidgetShared.swift`**
  * **Role:** Foundation models (`SharedWidgetPayload`, `SharedWidgetSettings`) and `WidgetTimelineBuilder` calculating standalone widget timelines.
* **`Sources/CaraokeCore/ActivityUpdatePolicy.swift` & `ActivityUpdateThrottle.swift`**
  * **Role:** Pure value-type throttling rules preventing Live Activity update spam.
* **`Sources/CaraokeCore/RideModeModel.swift`**
  * **Role:** State machine recording total ride duration and active session state.
* **`Sources/CaraokeCore/FeatureFlags.swift`**
  * **Role:** Build-time configuration toggles (`spotifyEnabled`, `relayBaseURL`).
* **`Sources/CaraokeCore/FixtureLoader.swift`**
  * **Role:** Module loader for bundled demo lyrics.

---

## 7. Monetization & Purchases

* **`iOS/PurchaseManager.swift`**
  * **Role:** Dual-layer purchase controller supporting native Apple StoreKit 2 transactions alongside RevenueCat SDK integration.
  * **Features:** Entitlement verification (`isEntitled`), product loader (`CaraokeProducts.all`), purchase processing, transaction listener, and purchase restoration.
* **`Sources/CaraokeCore/EntitlementModel.swift`**
  * **Role:** Pure data declarations of StoreKit product IDs (`caraoke.plus.monthly`, `caraoke.plus.yearly`, `caraoke.plus.lifetime`) and paywall card configurations (`PaywallContent`).
* **`CaraokePOC/Caraoke.storekit`**
  * **Role:** Local StoreKit testing configuration file simulating subscription renewals, grace periods, and lifetime non-consumables in Xcode.

---

## 8. Backend / Cloudflare Relay (`relay/`)

* **`relay/worker.js`**
  * **Role:** Cloudflare Worker utilizing Durable Objects (`LyricSessionDO`).
  * **Capabilities:**
    * Generates ES256 JWT APNs provider tokens using Apple `.p8` private keys.
    * Communicates over HTTP/2 with Apple APNs (`api.push.apple.com/3/device/*`).
    * Schedules wake alarms at lyric line boundaries to push Live Activity updates when the device is locked and iOS has suspended the Caraoke app.
    * Endpoints: `POST /sessions` (register/update/end sessions), `POST /crashes` (ingest crash reports), `GET /health` (uptime monitor).
* **`relay/wrangler.toml`**
  * **Role:** Cloudflare Wrangler deployment configuration defining worker name, compatibility date, and Durable Object bindings.

---

## 9. Configuration, Assets & Infrastructure

* **`CaraokePOC/project.yml`**
  * **Role:** XcodeGen project generator specification. Defines `Caraoke` (iOS Application), `CaraokeWidgets` (Widget Extension), and `CaraokeCoreTests` targets, framework embeddings, bundle IDs, and compile exclusions.
* **`CaraokePOC/iOS/Info.plist`**
  * **Role:** Main app metadata: specifies `UIBackgroundModes` (`audio`), `NSSupportsLiveActivities` (`true`), `NSSupportsLiveActivitiesFrequentUpdates` (`true`), URL schemes (`caraoke://`), and privacy descriptions.
* **`CaraokePOC/iOS/WidgetInfo.plist`**
  * **Role:** Extension metadata defining `com.apple.widgetkit-extension` and Live Activity compatibility flags.
* **`CaraokePOC/iOS/Caraoke.entitlements` & `CaraokeWidgets.entitlements`**
  * **Role:** Code signing entitlements configuring APNs production environment and shared Keychain access group `$(AppIdentifierPrefix)app.caraoke.ios`.
* **`CaraokePOC/iOS/Resources/Secrets.plist`**
  * **Role:** Secret property list storing `SpotifyClientID` and `REVENUECAT_API_KEY`. (Gitignored).
* **`CaraokePOC/iOS/Resources/ride-keeper.wav`**
  * **Role:** 1-second inaudible audio sample (~-68 dBFS) looped by `RideAudioKeeper`.
* **`CaraokePOC/Assets.xcassets`**
  * **Role:** Application icon sets (`AppIcon`) formatted for all standard iOS, CarPlay, and App Store resolutions.
* **`CaraokePOC/profiles/`**
  * **Role:** Provisioning profiles (`Caraoke_TF_Store_Push.mobileprovision` and `Caraoke_Widgets_TF_Store.mobileprovision`) for TestFlight distribution.
* **`.github/workflows/ci.yml`**
  * **Role:** GitHub Actions continuous integration and deployment pipeline. Builds targets with XcodeGen, executes unit tests, codesigns with Apple distribution certificates, and pushes builds directly to Apple TestFlight.

---

## 10. Master Component Dictionary

| File Path | Architecture Layer | Primary Target | Component / Class / Struct | Exact Responsibility & Presentation Role |
|:---|:---|:---|:---|:---|
| **`iOS/CaraokeApp.swift`** | App Lifecycle | Caraoke | `struct CaraokeApp: App` | Application entry point; initializes crash reporter, theme, and window hierarchy. |
| **`iOS/HomeView.swift`** | Presentation | Caraoke | `struct HomeView: View` | Main dashboard; status cards, widget preview, source pickers, and floating mini-player. |
| **`iOS/LyricsPageView.swift`** | Presentation | Caraoke | `struct LyricsPageView: View` | Immersive full-screen karaoke view; auto-scrolling lyric stage and dark artwork gradient wash. |
| **`iOS/SettingsView.swift`** | Presentation | Caraoke | `struct SettingsView: View` | Settings screen; music source setup, appearance picker, support, and legal information. |
| **`iOS/WidgetSettingsView.swift`** | Presentation | Caraoke | `struct WidgetSettingsView: View` | Dedicated widget setup screen with live interactive preview and theme/vinyl toggles. |
| **`iOS/PaywallView.swift`** | Presentation | Caraoke | `struct PaywallView: View` | OLED paywall modal showcasing premium features, pricing tiers, and purchase actions. |
| **`iOS/SpotifySetupView.swift`** | Presentation | Caraoke | `struct SpotifySetupView: View` | Step-by-step Spotify developer app connection sheet with Client ID input. |
| **`iOS/LyricTileView.swift`** | UI Engine | Both Targets | `struct LyricTileView: View` | Universal lyric tile renderer across all surfaces (Lock Screen, CarPlay, Small/Medium/Large widgets). |
| **`iOS/CaraokeWidgetBundle.swift`** | Widget Extension | CaraokeWidgets | `struct CaraokeWidgetBundle: WidgetBundle` | Widget extension `@main` entry bundling `LyricsLiveActivity` and `CaraokeWidget`. |
| **`iOS/CaraokeWidget.swift`** | Widget Extension | CaraokeWidgets | `struct CaraokeWidget: Widget` | Persistent widget configuration supporting `.systemSmall`, `.systemMedium`, and `.systemLarge`. |
| **`iOS/VinylWidgetView.swift`** | Widget Extension | CaraokeWidgets | `struct VinylWidgetView: View` | Medium (2x4) widget; 3 lyric lines left, spinning vinyl disc / cover right, AppIntents transport. |
| **`iOS/CarPlayWidgets.swift`** | Widget Extension | CaraokeWidgets | `CaraokePlayerWidget`, `CaraokeLyricsWidget`, `CaraokeHybridWidget` | The three `.systemSmall` CarPlay widget-stack tiles (cover/controls, lyrics only, hybrid lyric+player) with interactive AppIntent transport. |
| **`iOS/WidgetArtworkBackground.swift`**| Widget Extension | Both Targets | `struct WidgetArtworkBackground: View` | Dynamic background renderer generating artwork-tinted gradients or theme fills. |
| **`iOS/LyricsLiveActivity.swift`** | Live Activity | CaraokeWidgets | `struct LyricsLiveActivity: Widget` | ActivityKit configuration; renders Lock Screen Banner, CarPlay Small tile, and Dynamic Island. |
| **`iOS/LyricsActivityAttributes.swift`**| Live Activity | Both Targets | `struct LyricsActivityAttributes` | Deliberately compact Codable `ContentState` serialized during ActivityKit updates. |
| **`iOS/LyricsActivityController.swift`**| State / Manager | Caraoke | `class CaraokeActivityController` | Controls Live Activity lifecycle, token capture, and update throttling. |
| **`iOS/SharedWidgetStore.swift`** | Storage / IPC | Both Targets | `enum SharedWidgetStore` | Cross-process store using shared Keychain access group (`R3Y5ZR429L.app.caraoke.ios`). |
| **`iOS/WidgetResync.swift`** | Widget Engine | CaraokeWidgets | `enum WidgetResync` | Standalone widget-side resynchronization engine querying Spotify and LRCLIB in background. |
| **`iOS/TransportIntents.swift`** | AppIntents | CaraokeWidgets | `struct PlayPauseIntent`, etc. | Interactive AppIntents driving playback directly from widget buttons. |
| **`iOS/TransportControl.swift`** | Playback Routing| Both Targets | `enum TransportControl` | Routes transport commands between Apple Music (`MediaPlayer`) and Spotify Web API. |
| **`iOS/RidePlaybackController.swift`**| Playback Engine | Caraoke | `class RidePlaybackController` | Central playback orchestrator linking music sources, sync engine, lyrics repo, and widgets. |
| **`iOS/RideModeViewModel.swift`** | ViewModel | Caraoke | `class RideModeViewModel` | Master ObservableObject powering all home screen UI, transport, and live status. |
| **`iOS/RideAudioKeeper.swift`** | Background Engine| Caraoke | `class RideAudioKeeper` | Looping silent audio session (`ride-keeper.wav`) preventing iOS 30s background suspension; build 46 resumes itself across audio-session interruptions and route changes (the lyric-freeze fix). |
| **`iOS/RideModeIntents.swift`** | AppIntents | Caraoke | `struct StartRideModeIntent`, etc. | Siri and Shortcuts automations for toggling Ride Mode in background. |
| **`iOS/AppModel.swift`** | State Bridge | Caraoke | `class AppModel` | Singleton bridge sharing `RideModeViewModel` state with background `LiveActivityIntent`. |
| **`iOS/AppleMusicSource.swift`** | Audio Source | Caraoke | `class AppleMusicSource` | Native Apple Music observer using public `MediaPlayer` framework (zero developer tokens). |
| **`iOS/SpotifyAuth.swift`** | Authentication | Caraoke | `class SpotifyAuth` | ASWebAuthenticationSession PKCE flow and token manager for Spotify. |
| **`iOS/PurchaseManager.swift`** | Monetization | Caraoke | `class PurchaseManager` | Dual-engine purchase coordinator using StoreKit 2 and RevenueCat. |
| **`iOS/CrashReporter.swift`** | Reliability | Caraoke | `class CrashReporter` | Uncaught exception handler and MetricKit subscriber delivering crash logs to relay. |
| **`iOS/AppTheme.swift`** | Styling | Both Targets | `enum AppTheme`, `CoverArtworkView`| Color tokens (OLED black, Ivory white), vinyl disc graphics, and average color extraction. |
| **`iOS/AppearanceSettings.swift`** | Styling | Caraoke | `enum AppearanceSettings` | Persisted Auto/Light/Dark appearance preferences updating window interface styles. |
| **`iOS/CaraokeLogo.swift`** | Assets | Caraoke | `struct CaraokeLogo: View` | Pure SwiftUI resolution-independent vector brand mark. |
| **`iOS/SpotifyLogo.swift`** | Assets | Caraoke | `struct SpotifyLogo: View` | Pure SwiftUI resolution-independent vector Spotify brand mark. |
| **`iOS/DemoLyrics.swift`** | Fixture | Both Targets | `enum DemoLyrics` | Bundled copyright-free original demo track ("Road Trip Anthem" by Cibul & Njun). |
| **`iOS/LyricsRelayClient.swift`** | Networking | Caraoke | `class LyricsRelayClient` | HTTP client registering timed lyric schedules with Cloudflare Worker relay. |
| **`CaraokeCore/SyncEngine.swift`** | Core Engine | Both Targets | `class SyncEngine` | Millisecond-level position extrapolator with jitter suppression and drift correction. |
| **`CaraokeCore/FallbackLyricsProvider.swift`**| Lyrics Engine| Both Targets | `class FallbackLyricsProvider` | Concurrent racer dispatching requests to LRCLIB and YouTube Music simultaneously. |
| **`CaraokeCore/LRCLIBLyricsProvider.swift`**| Lyrics Engine | Both Targets | `class LRCLIBLyricsProvider` | Keyless client for LRCLIB API with cache-first and rate-limit compliance. |
| **`CaraokeCore/YouTubeMusicLyricsProvider.swift`**| Lyrics Engine| Both Targets| `class YouTubeMusicLyricsProvider`| Keyless InnerTube client extracting Musixmatch/LyricFind synced lyrics. |
| **`CaraokeCore/LyricsDiskCache.swift`**| Storage | Both Targets | `class LyricsDiskCache` | Atomic disk cache storing raw provider responses with 30-day freshness TTL. |
| **`CaraokeCore/TrackMatcher.swift`** | String Normalizer| Both Targets | `enum TrackMatcher` | Normalizes song titles and artist names, stripping noise to generate durable cache keys. |
| **`CaraokeCore/LyricTrack.swift`** | Data Structure | Both Targets | `struct LyricTrack` | Core timing structure providing $O(\log n)$ binary search lookup for active lines. |
| **`CaraokeCore/LyricLine.swift`** | Model | Both Targets | `struct LyricLine` | Timed lyric line model carrying timestamp, text, and optional translation. |
| **`CaraokeCore/LyricSnapshot.swift`** | Model | Both Targets | `struct LyricSnapshot` | Point-in-time immutable lyric state rendered by UI and Live Activity. |
| **`CaraokeCore/LyricStatus.swift`** | Model | Both Targets | `enum LyricStatus` | 6-state lifecycle enum (`playing`, `paused`, `noLyrics`, `loading`, `stale`, `idle`). |
| **`CaraokeCore/LyricType.swift`** | Layout / Specs | Both Targets | `enum LyricType`, `LyricSurface` | Strict typography scale (18pt) and vertical row capacity calculator. |
| **`CaraokeCore/WidgetShared.swift`** | Models / Timeline| Both Targets | `struct SharedWidgetPayload`, etc. | Cross-process models and `WidgetTimelineBuilder` computing independent timelines. |
| **`CaraokeCore/NowPlaying.swift`** | Models | Both Targets | `struct NowPlayingState`, etc. | Playback state models and source protocols. |
| **`CaraokeCore/NowPlayingCoordinator.swift`**| Arbiter | Both Targets | `class NowPlayingCoordinator` | Combines Apple Music and Spotify streams, prioritizing active local playback. |
| **`CaraokeCore/SpotifySource.swift`** | Networking | Both Targets | `class SpotifySource` | Polling client for official Spotify Web API currently-playing endpoint. |
| **`CaraokeCore/SpotifyAuthCore.swift`**| Auth Core | Both Targets | `enum SpotifyPKCE`, etc. | RFC 7636 PKCE crypto verification, token model, and expiry policies. |
| **`CaraokeCore/ActivityUpdatePolicy.swift`**| Policy | Both Targets | `struct ActivityUpdatePolicy` | Evaluates whether line/track state changed before triggering Live Activity update. |
| **`CaraokeCore/ActivityUpdateThrottle.swift`**| Throttle | Both Targets | `struct ActivityUpdateThrottle` | Coalesces rapid line updates to 1.5s minimum interval to preserve system budget. |
| **`CaraokeCore/EntitlementModel.swift`**| Store Models | Both Targets | `enum CaraokeProducts`, etc. | StoreKit product identifiers and paywall offer definitions. |
| **`CaraokeCore/LRCParser.swift`** | Parser | Both Targets | `enum LRCParser` | Standard LRC file parser handling timestamps, offsets, and line sorting. |
| **`CaraokeCore/TimedLyricParser.swift`**| Parser | Both Targets | `enum TimedLyricParser` | Compact TSV parser for offline demo fixtures. |
| **`CaraokeCore/RideModeModel.swift`** | State Machine | Both Targets | `struct RideModeModel` | Pure Foundation state machine tracking ride duration. |
| **`CaraokeCore/FeatureFlags.swift`** | Configuration | Both Targets | `enum FeatureFlags` | Build-time toggles for Spotify connectivity and relay URL. |
| **`CaraokeCore/FixtureLoader.swift`** | Utilities | Both Targets | `enum FixtureLoader` | Bundle loader for offline demo track fixtures. |
| **`relay/worker.js`** | Backend | Cloudflare | Cloudflare Worker / Durable Object | Generates APNs ES256 JWTs and dispatches background pushes at line boundaries. |
| **`relay/wrangler.toml`** | Backend Config | Cloudflare | Wrangler Configuration | Defines worker bindings, routes, and Durable Object namespace. |
| **`CaraokePOC/project.yml`** | Project Specs | XcodeGen | XcodeGen Configuration | Complete project definition, target dependencies, entitlements, and build settings. |
| **`CaraokePOC/Caraoke.storekit`**| Testing Config| Xcode | StoreKit Configuration | Local StoreKit testing environment simulating subscriptions and IAPs. |
