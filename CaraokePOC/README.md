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
| Lyrics cache | `Sources/CaraokeCore/LyricsDiskCache.swift` | Cache-first when fresh, stale-serving offline, 30-day TTL, clearable from Settings |
| **Spotify source** | `Sources/CaraokeCore/SpotifySource.swift` | Official Web API `currently-playing` polling (5 s active / 15 s idle) |
| **Spotify auth core** | `Sources/CaraokeCore/SpotifyAuthCore.swift` | Official OAuth authorization-code + PKCE (RFC 7636), token policy + endpoint client |
| **Entitlements** | `Sources/CaraokeCore/EntitlementModel.swift` | One "Caraoke Plus" entitlement; $1.99/mo · $11.99/yr · $20 lifetime product model |
| Now-playing seam | `Sources/CaraokeCore/NowPlaying.swift` | `NowPlayingSource` protocol + `NowPlayingState` (moved to Core for testability) |
| Update policy | `Sources/CaraokeCore/ActivityUpdatePolicy.swift` | Sends Activity updates only on real line/track/pause changes |
| Update throttle | `Sources/CaraokeCore/ActivityUpdateThrottle.swift` | Coalesces rapid line changes; never drops a line |
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

`HomeView` shows one master `Toggle`; `RideModeViewModel.toggle()` starts a
fake 1-second clock that walks the demo track, updates the on-screen preview
and pushes the snapshot into the Live Activity; `stopRide()` cancels the clock
and ends the activity.

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
  and run under `swift test` in an Xcode environment (the package manifest is
  macOS-13-compatible and has no dependencies).
- When this Mac is CPU-starved (React-heavy apps running), build with
  `-Onone`; `-O` works but takes far longer under load.

To run the standalone tests:

```sh
swiftc -Onone -module-cache-path .build/modulecache \
  Sources/CaraokeCore/*.swift Tests/main.swift -o .build/testrunner
.build/testrunner
```
