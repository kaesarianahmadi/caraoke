# Caraoke PoC — Live Lyrics on CarPlay

An **original** SwiftUI proof of concept for Caraoke: put the current lyric
line (plus the next line) on CarPlay through a system-rendered Live Activity.

- Zero third-party dependencies (LRCLIB, Spotify, MediaPlayer, StoreKit 2 are
  all dependencies-free — system frameworks + public HTTP APIs)
- Zero copyrighted lyrics (the demo fixture is an original in-house song;
  live lyrics come from LRCLIB's community database with attribution)
- No scraped lyrics, no browser cookies, no unofficial Spotify APIs, no
  undocumented Apple Music endpoints
- No backend: Apple Music via public MediaPlayer, Spotify via official
  OAuth PKCE + Web API, LRCLIB keyless

## What's in the PoC

| Piece | File | Notes |
|---|---|---|
| Lyric timing engine | `Sources/CaraokeCore/LyricTrack.swift` | Binary-search current/next line by playback ms; pure Foundation, platform-neutral |
| Timed lyric parser | `Sources/CaraokeCore/TimedLyricParser.swift` | Reads `startMs<TAB>line` rows from a TSV fixture |
| LRC parser | `Sources/CaraokeCore/LRCParser.swift` | Standard LRC dialect (multi-tags, offset, fractions) |
| Track matcher | `Sources/CaraokeCore/TrackMatcher.swift` | Normalization + duration-tolerant matching over vendor-agnostic `LyricsCandidate` |
| Lyrics seam | `Sources/CaraokeCore/LyricsRepository.swift` | Provider-agnostic protocol + `TrackSignature` + errors; providers swap in one commit |
| LRCLIB provider | `Sources/CaraokeCore/LRCLIBLyricsProvider.swift` | Keyless `/api/get`→`/api/search` fallback, User-Agent etiquette, 429 backoff, stale-serving |
| Lyrics cache | `Sources/CaraokeCore/LyricsDiskCache.swift` | Cache-first when fresh, stale-serving offline, 30-day TTL; no in-app clear control |
| **Spotify source** | `Sources/CaraokeCore/SpotifySource.swift` | Official Web API `currently-playing` polling (2 s active / 15 s idle by default) |
| **Spotify auth core** | `Sources/CaraokeCore/SpotifyAuthCore.swift` | Official OAuth authorization-code + PKCE (RFC 7636), token policy + endpoint client |
| **Entitlements** | `Sources/CaraokeCore/EntitlementModel.swift` | Monthly, yearly and lifetime product identifiers; actual price and availability come from StoreKit |
| Now-playing seam | `Sources/CaraokeCore/NowPlaying.swift` | `NowPlayingSource` protocol + `NowPlayingState` (moved to Core for testability) |
| Update policy | `Sources/CaraokeCore/ActivityUpdatePolicy.swift` | Chooses Live Activity updates for meaningful playback changes |
| Update throttle | `Sources/CaraokeCore/ActivityUpdateThrottle.swift` | Coalesces rapid updates; delivery timing depends on the system |
| Demo fixture | `Sources/CaraokeCore/Resources/demo_lyrics.tsv` | **Original** lyrics, no copyright |
| Snapshot builder | `Sources/CaraokeCore/LyricSnapshotBuilder.swift` | Turns position into the small payload the UI renders |
| Ride Mode state | `Sources/CaraokeCore/RideModeModel.swift` | On/off master switch + ride duration |
| App shell | `iOS/CaraokeApp.swift`, `iOS/HomeView.swift` | Home screen with the Ride Mode switch + live preview + gear → Settings |
| Shared app model | `iOS/AppModel.swift` | One ViewModel instance shared by UI and App Intents |
| Ride controller | `iOS/RideModeViewModel.swift` | Fake timed clock (1 s ticks) → snapshots → Live Activity |
| Live Activity | `iOS/LyricsLiveActivity.swift` | Lock Screen banner + Dynamic Island + **CarPlay small family** |
| Shared tile | `iOS/LyricTileView.swift` | One view used by all three surfaces |
| Activity controller | `iOS/LyricsActivityController.swift` | Session-spanning lifecycle: request/watch/end + orphan cleanup |
| Apple Music source | `iOS/AppleMusicSource.swift` | Public MediaPlayer `systemMusicPlayer` reading — no MusicKit token, no backend |
| **Spotify auth (iOS)** | `iOS/SpotifyAuth.swift` | Keychain token store + `ASWebAuthenticationSession` PKCE flow |
| **Purchases** | `iOS/PurchaseManager.swift` | StoreKit 2: products, purchase, restore, `Transaction.updates` listener |
| **Paywall** | `iOS/PaywallView.swift` | Three plans, yearly recommended, lifetime secondary (PRD D6: after first lyric moment) |
| **Settings** | `iOS/SettingsView.swift` | LRCLIB attribution + sponsor link, ride stats, cache reset, support links |
| Ride intents | `iOS/RideModeIntents.swift` | `LiveActivityIntent` start/stop — the one legal background start |
| Widget refresh | `iOS/TransportIntents.swift`, `iOS/CaraokeWidget.swift` | One-shot manual resync. Dated timeline entries advance lyrics; playback events and timeline recovery request new bakes. |
| Widget bundle | `iOS/CaraokeWidgetBundle.swift` | Entry point |
| StoreKit config | `Caraoke.storekit` | Local StoreKit testing in Xcode (verify/resync when opening in Xcode) |
| Secrets template | `iOS/Resources/Secrets.example.plist` | Copy to `Secrets.plist`, add your Spotify client ID (gitignored) |
| Attribution | `THIRD_PARTY_NOTICES.md` | MIT notice for modules ported from DriveVerse |
| Unit tests | `Tests/CaraokeCoreTests/LyricTimingTests.swift` | XCTest timing tests (run in Xcode) |
| Test harness | `Tests/main.swift` | Standalone runner (no XCTest): timing, LRC, matcher, policy, throttle, LRCLIB provider (mocked network), Spotify PKCE/token/parser, entitlements |

Modules noted as ported come from [DriveVerse](https://github.com/praveetgupta/driveverse)
(MIT © 2026 Praveet Gupta). A direct audit (2026-08-29,
`../research/driveverse-verification.md`) selected only App-Store-safe pieces;
`THIRD_PARTY_NOTICES.md` records exactly what was adapted and what was
deliberately left out (the location-based background keep-alive).

## The CarPlay small layout

`LyricsLiveActivity.swift` registers the small activity family:

```swift
.supplementalActivityFamilies([.small])
```

and `LyricTileView` branches on `context.activityFamily == .small` to render a
compact tile (current line up to 2 lines, next line in caption) — the layout
CarPlay uses for Live Activities. This is the Apple-documented pattern
([ActivityFamily](https://developer.apple.com/documentation/widgetkit/activityfamily)).

## Ride Mode start/stop

`HomeView` shows one master `Live Lyrics` toggle. With
`RideModeViewModel.useSimulatedPlayback = false` (shipped default), the real
pipeline runs: Apple Music / Spotify → `NowPlayingCoordinator` → `SyncEngine`
→ LRCLIB / YouTube Music lyrics → Live Activity, with the locked-phone relay
armed per track. The bundled demo clock remains only as the simulated path
behind that flag; it is off because it does not survive iOS suspension.
`stopRide()` ends the activity.

## Support docs & shipped behavior

Canonical user docs: <https://caraokeapp.com/docs>. `caraoke.live/docs`
returns 401 and is not linkable. Deep links: `#carplay`, `#dynamic-island`,
`#widgets`, `#standby`, `#locked-phone`, `#problems`, `#client-id`,
`#premium`, `#logs`, `#support`.

- **Setup path:** Home gear → **Connect music** (Apple Music, or Spotify
  expanded inline) → Home → **Live Lyrics** → iOS Settings → Caraoke →
  Live Activities. There is no "Music Sources → Advanced" screen.
- **Spotify is a limited beta.** Built-in shared credentials use a Spotify
  development-mode app with a 5-user allowlist (403 for everyone else). The
  fix is the user's own free Client ID; the redirect URI must be exactly
  `caraoke://spotify-callback`. Paste it in Connect music → Spotify →
  **Save & Connect**.
- **Lyrics providers:** `FallbackLyricsProvider` races LRCLIB and YouTube
  Music (InnerTube) concurrently and takes the first valid synced result.
  No NetEase provider exists. If neither returns synced lyrics, the song
  plays without lines; title, artist, and progress still update.
- **Locked-phone limit:** iOS suspends Caraoke about 30 s after backgrounding.
  The relay advances the *current* track only — track change, pause, or seek
  while suspended can leave the tile on the prior line until the user taps
  Resync (immediate sample/re-arm) or reopens Caraoke (normal polling resumes,
  but no forced immediate sample/re-arm). There is no guaranteed continuous
  background sync. iOS ends a Live Activity after roughly 8 hours; Low Power
  Mode / Focus / Live Activities off can delay or hide updates.
- **Resync:** tap Resync (arrow.clockwise) or album art / vinyl on the widget
  or touchscreen CarPlay tile, or tap Resync in the phone Lyrics page header
  (the widget-extension fallback repairs Spotify only). Opening Caraoke only
  resumes polling. Then toggle Live Lyrics off/on, confirm Connect music
  matches the playing app, and seek once after resuming. Lock Screen and
  Dynamic Island have no Resync control.

For timing or refresh bugs, collect a fresh, uniquely named USB log archive —
never reuse an older one:

```sh
sudo log collect --device-name "Your iPhone" --last 10m \
  --output ~/Desktop/caraoke-build84-20261114-0135.logarchive
```

Include the build number, iOS version, iPhone model, CarPlay connection type,
and music source. Logs may contain device/app activity; review before sharing.

## No copyrighted lyrics

The fixture is an original twelve-line song about the two cats
(`demo_lyrics.tsv` and `iOS/DemoLyrics.swift`). Nothing is scraped and no
lyric text is copied from any existing song.

## Verification

This machine has only CommandLineTools (no Xcode, no iOS SDK), so:

- **Everything in `Sources/CaraokeCore`** — timing, parsers, matcher, LRCLIB
  provider (mocked `URLProtocol`), Spotify PKCE/token client/parser,
  entitlements — compiles and runs on macOS via the standalone harness.
- **iOS UI/ActivityKit/StoreKit layer** is validated with `swiftc -parse`
  (syntax-only), since ActivityKit/WidgetKit need an iOS SDK.
- **XCTest timing tests** live in `Tests/CaraokeCoreTests/LyricTimingTests.swift`
  and run under `swift test` in an Xcode environment. The core depends on Yams
  for the LRCLIB Lyricsfile YAML format.
- When this Mac is CPU-starved (React-heavy apps running), build with
  `-Onone`; `-O` works but takes far longer under load.

To run the standalone tests:

```sh
git clone --depth 1 --branch 6.2.2 https://github.com/jpsim/Yams.git /tmp/caraoke-yams
cmake -S /tmp/caraoke-yams -B /tmp/caraoke-yams-build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/caraoke-yams-build
swiftc -Onone -module-cache-path .build/modulecache \
  -I /tmp/caraoke-yams-build/swift -L /tmp/caraoke-yams-build/lib -lYams \
  Sources/CaraokeCore/*.swift Tests/main.swift -o .build/testrunner
DYLD_LIBRARY_PATH=/tmp/caraoke-yams-build/lib .build/testrunner
```

LRCLIB word-timed Lyricsfile records are split into phrases at actual source
word timestamps, with a maximum of four whitespace-delimited words per phrase.
Malformed, overlapping or unsupported timing falls back to the source line
schedule; no invented timestamps are used. Line-only provider results remain
available but may fill more than two display rows. A two-second preference window
favors a valid LRCLIB word-timed result over the first line-only provider result.
The same timed phrases flow through the phone, widget payload and relay. Device
sync, Word-level timing coverage, and licensed use still require validation.
Local verification: 326 standalone checks passed with Yams 6.2.2; per-file
iOS syntax parsed; XcodeGen generated the app/widget project. A live LRCLIB
`Los Dol` record produced source-timed phrases at 14750 ms and 17419 ms; an
executable exercised the widget entry and relay schedule at that boundary.
No iOS typecheck, CarPlay render or phone playback accuracy test was possible
locally. `swift test` is blocked by this machine's CLT `PlatformPath` error.

### Release audit — 2026-11-14

### Build 86 device follow-up

The drive archive `drive_20261114_172600.logarchive` contains repeated stale
widget self-fetches: 97 Spotify HTTP 204 responses in one minute starting at
13:12, repeatedly rebaking an expired payload. `204` supplied no track data;
it does not establish why playback was absent. Concurrent automatic repairs are
now coalesced with a five-second retry interval; explicit Resync is not gated.
The extension can be restarted by iOS, so the in-memory gate is per process.
Two separate CPU reports recorded 92% and 85% average CPU over 17 and 19 seconds,
both with `Action taken: none`. The samples do not prove a CPU root cause.

The CarPlay lyrics-only and hybrid tiles now show a centered resync action when
the payload is known expired, or during its repair pulse. This detects expired
data, not every instance of lyric drift. Hybrid metadata is limited to one row
each to preserve lyric space. CarPlay lyric chunks use four words; the medium
Home Screen widget now segments its active lyric too. Segmentation is visual,
not a new timestamp or a guarantee that the whole provider line has four words.
The player tile now fits its cover, metadata, progress and controls within a
162-point design canvas with explicit spacing, scaled for smaller hosts. The
lyrics area itself is a resync target on both lyric tiles; the centered glyph
is shown for known expiry, not every drift. Artwork color is cached on artwork
change instead of being recomputed during Home view rendering; this removes the
symbolicated render-path computation but artwork decoding still occurs on the
main actor. Real iOS/CarPlay layout, hit testing and Sentry recovery are unverified.

LRCLIB searches synced lyrics after a plain-only exact match. CarPlay-only rows
now retain identity as they move from upcoming to active to previous, with a
bottom-entry transition. Competitor video shows individual rows moving upward;
binary symbols reveal clock/scroll modifiers but do not prove which drives that
view. Actual widget motion and refresh timing still require a head-unit test.
Native macOS renders exercised before/after/repeated lyric states, not animation.
The renderer's bounded font search has no proven device CPU result.
Provider coverage is not a latency guarantee: Caraoke races LRCLIB and YouTube
Music; the competitor binary exposes additional providers, but their availability,
licensing and timestamp quality for these songs were not established.
Earlier traces showed CarPlay timeline deferrals, so scheduling remains unchanged.

- Resync samples the selected player in the app process, restores a persisted
  ride's playback pipeline, re-arms the current relay schedule, and bypasses
  unchanged-snapshot deduplication. Phone Resync uses the same system intent.
  Session/generation checks prevent late repairs from restarting stopped rides.
- Spotify ignores older overlapping poll responses. Explicit phone transport
  source selection takes precedence over an old widget payload; failed commands
  no longer leave an optimistic play/pause state behind.
- Build 86 originally placed the lyrics-only Resync below the lyrics and the
  Hybrid control on its cover. Current code places a centered action over both
  lyric areas when the timeline is known expired; it cannot detect all drift.
  Exact competitor lyrics-only placement is not established.
- Display segmentation inserts whole-word visual breaks, at most five words per
  segment before native wrapping. Provider lines/timestamps remain unchanged;
  no per-word synchronization or new provider is invented.
- Phone typography, controls, offline Help & setup, canonical documentation links,
  localized purchase pricing, billing disclosures and purchase error handling updated.
  A RevenueCat failure/cancellation cannot start a second StoreKit purchase.
- Local standalone gate: 318 checks passed; iOS files and conditional extension
  intent branches parsed. Actual SpotifySource smoke confirmed an old delayed
  response cannot replace a newer sample. Native macOS snapshots exercised the
  actual compact lyric renderer at 162×118, 162×100 and 342×138. Mobile documentation
  navigation exercised at 390 px: no horizontal overflow or broken section anchors.
- Local `swift test` was unavailable because Command Line Tools could not resolve
  SDK `PlatformPath`. CI run 43558544159 passed the build-86 iOS compile and SPM
  tests; run 43614549750 completed successfully for build 87. Neither proves
  physical CarPlay behavior, sandbox purchases, or locked-phone endurance.
- Native macOS AppIntents smoke exercised typed continuation/normal-stop results
  and rejected replaced/stopped sessions. This does not prove iOS system dispatch.
- Relay regression (`node relay/worker.test.mjs`) rejects public diagnostic reads
  and deletes while retaining crash ingestion. The deployed `/crashes` route still
  returned unauthenticated HTTP 200; no report body was fetched. An authorized relay
  deployment is required to remove that live exposure.
- Corrected privacy/terms drafts disclose the relay and SDK data flows; mobile
  privacy/terms pages were checked at 390 px with no viewport overflow. These local
  drafts require review/publication; the currently published policy remains outdated.

**Release blockers retained:** Sentry hang/watchdog issues remain unresolved,
including [7798393633](https://caraokeapp.sentry.io/issues/7798393633/),
[7814932213](https://caraokeapp.sentry.io/issues/7814932213/) and new build-86
issue [7848028568](https://caraokeapp.sentry.io/issues/7848028568/). Its latest
build-86 stack was symbolicated locally with matching dSYM UUID
`17F989CE-8910-31AA-8C9D-334FF084142E`: `HomeView.widgetsSection` →
`RideModeViewModel.artworkColorHex` → `UIImage.averageColorHex` → JPEG decoding
and IOSurface allocation during SwiftUI rendering. This identifies the sampled
path, not the cause of every hang. A candidate fix is computing and caching
artwork color once per artwork change off the UI update path; device verification
is still required. Spotify [7791303967](https://caraokeapp.sentry.io/issues/7791303967/)
records 5xx responses.
Relay route reachability does not verify APNs delivery;
TelemetryDeck ingestion does not grant analytics query access. The existing
inaudible audio keep-alive is an App Review policy risk, not a guaranteed approved
background mode. Spotify production access and lyric-provider/content rights also
need clearance. Do not represent this audit as App Store approval or perfect sync.
