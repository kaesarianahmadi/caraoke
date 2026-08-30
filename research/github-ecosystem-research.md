# GitHub Ecosystem Research — ActivityKit / WidgetKit / MusicKit / CarPlay

Collected 2026-08-29 via the GitHub Search + Repos API (rates limited; dates are
`pushed_at` / latest commit on default branch). Focus: Swift/SwiftUI projects that
use **ActivityKit + WidgetKit + MusicKit + CarPlay** — especially live lyrics on
CarPlay, which is Caraoke's product category.

## Verdict legend

- **🟢 Reference only** — license is clear & permissive, safe to read/learn from. Do not vendor code.
- **🟡 Copy with attribution** — permissive license; copying is legal if the license notice is preserved and the file header is attributed. (We are *not* copying any code for this PoC; we wrote it from scratch.)
- **🔴 Avoid entirely** — no license (unclear ownership), GPL/AGPL, or the code depends on sources that violate our constraints (scraped lyrics, unofficial Spotify APIs, undocumented endpoints).

---

## Highly relevant — live lyrics + Live Activity + CarPlay

| # | Repository | URL | License | Last commit | Relevant files | Feature covered | Production risks | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | **praveetgupta/driveverse** | https://github.com/praveetgupta/driveverse | MIT | 2026-07-22 | `DriveVerse/LiveActivity/LyricsAttributes.swift`, `LiveActivityController.swift`, `LiveActivityUpdatePolicy.swift`, `LiveActivityUpdateThrottle.swift`, `Core/Lyrics/LRCParser.swift`, `Core/NowPlaying/AppleMusicSource.swift`, `Core/Lyrics/LRCLIBClient.swift` | Real-time synced lyrics on **CarPlay + Lock Screen via Live Activity**; Apple Music (MusicKit) + Spotify sources; one-activity-per-session design; update throttling/coalescing | Uses **LRCLIB** (third-party lyric API) and a Spotify token flow — re-audited 2026-08-29 by direct clone: the flow is **official OAuth PKCE** (the earlier "unofficial" label was wrong); the real Spotify blocker is platform *policy*, not auth. Depends on iOS 26 behavior for CarPlay mirroring. Small (2★) but recent and well-tested. | 🟢 Reference only. **Architecture** (attributes tiny payload, one session-spanning activity, throttling, orphan cleanup, frequent-updates handling) is the best reference for Caraoke. **Do not copy** the LRCLIB client or Spotify auth (forbidden sources). |
| 2 | **tcastellanza/synced-lyrics** | https://github.com/tcastellanza/synced-lyrics | **None** | 2026-07-07 | `LyricsWidget/LyricsWidgetLiveActivity.swift`, `LyricsFetcher.swift`, `NowPlayingObserver.swift`, `LyricsModels.swift` | LRCLIB lyrics + **Live Activities for CarPlay**; shows the `.supplementalActivityFamilies([.small])` + `@Environment(\.activityFamily)` small-family pattern (exactly what Caraoke needs) | **No license** → ownership unclear, cannot copy. Uses LRCLIB (network). 0★. | 🔴 Avoid entirely (unlicensed). The CarPlay small-family *pattern* is documented by Apple and we reimplemented it independently. |
| 3 | **josephbinu06/LiveLyrics** | https://github.com/josephbinu06/LiveLyrics | **None** | 2026-03-06 | `LiveLyrics/Activity/LyricsActivityManager.swift`, `Services/LRCLIBService.swift`, `Services/LRCParser.swift`, `Services/LyricSyncEngine.swift`, `LiveLyricsWidget/LyricsLiveActivity.swift` | iPhone app: live activity feed of lyrics for the currently playing song | **No license**. LRCLIB dependency. No CarPlay evidence. 1★. | 🔴 Avoid entirely (unlicensed). |
| 4 | **aviwad/LyricFever** | https://github.com/aviwad/LyricFever | MIT | 2026-04-03 | `LyricFever/Models/LyricsParser/LyricsParser.swift`, `LyricProvider/LRCLIB/...`, `LyricProvider/Spotify/...`, `LyricProvider/NetEase/...`, `Players/AppleMusic/AppleMusicPlayer.swift` | Best-in-class macOS lyrics app (628★): synced lyrics from Spotify/Apple Music | Uses **unofficial Spotify API, NetEase scraping, LRCLIB** — all forbidden for us. macOS-only, not Live Activity/CarPlay. | 🟢 Reference only for the **LRC parser model** (MIT, clean, well-tested). Never copy the provider layer (forbidden sources). |

## Live Activity / Dynamic Island / WidgetKit (no lyrics)

| # | Repository | URL | License | Last commit | Relevant files | Feature covered | Production risks | Verdict |
|---|---|---|---|---|---|---|---|---|
| 5 | **apple/sample-food-truck** | https://github.com/apple/sample-food-truck | MIT | 2023-08-18 | `App/Orders/OrderDetailView.swift`, `App/Truck/Cards/TruckOrdersCard.swift`, `FoodTruckKit/...` | Apple's canonical SwiftUI sample using WidgetKit + ActivityKit (Live Activities) + SwiftUI architecture | Pre-17.2: no CarPlay small family. No lyrics. Large. | 🟢 Reference only — canonical, safe, MIT. |
| 6 | **1998code/iOS16-Live-Activities** | https://github.com/1998code/iOS16-Live-Activities | MIT | 2026-04-26 | `SwiftPizzaApp` ActivityKit/WidgetKit/Dynamic Island demo + full docs | ActivityKit + Dynamic Island demo (420★) | iOS 16 era; no CarPlay small family; no lyrics. | 🟢 Reference only — safe, MIT. |
| 7 | **mikonyaa/LiveActivityDynamicIslandKit** | https://github.com/mikonyaa/LiveActivityDynamicIslandKit | MIT | 2026-07-12 | `Sources/LiveActivityKit/...`, `Examples/LiveActivityDemo/...`, `Tests/LiveActivityKitTests.swift` | Swift package abstracting Live Activities + Dynamic Island; has lifecycle + tests | Adopting it = third-party dependency (violates no-deps). No lyrics/CarPlay. | 🟢 Reference only — patterns (lifecycle, throttling) are useful; do **not** add as a dependency. |
| 8 | **simonberner/ladi-simulator** | https://github.com/simonberner/ladi-simulator | MIT | 2023-02-16 | `LADISimulator/Model/GameSimulator.swift`, `GameWidget/GameLiveActivity.swift`, `GameWidget/LiveActivityView.swift` | Live Activity **simulator** for sports scores | iOS 16 era; no CarPlay; no lyrics. | 🟢 Reference only — simulator pattern is a good testing idea. |
| 9 | **batikansosun/iOS-16-Live-Activities-Dynamic-Island** | https://github.com/batikansosun/iOS-16-Live-Activities-Dynamic-Island | **None** | 2022-10-10 | `GroceryDeliveryApp/GroceryDeliveryAppAttributes.swift`, `DeliveryTrackWidget/DeliveryTrackWidget.swift` | Delivery Live Activity + Dynamic Island demo (89★) | **No license**. iOS 16 era; no CarPlay. | 🔴 Avoid entirely (unlicensed). |

## MusicKit / Apple Music (players, widgets, SDK wrappers)

| # | Repository | URL | License | Last commit | Relevant files | Feature covered | Production risks | Verdict |
|---|---|---|---|---|---|---|---|---|
| 10 | **muse-application/muse-macos** | https://github.com/muse-application/muse-macos | MIT | 2024-04-23 | `MusicApp` Apple Music player (SwiftUI) | Full SwiftUI Apple Music player for macOS (57★) | macOS; no Live Activity/CarPlay; no lyrics. | 🟢 Reference only — clean MusicKit usage (authorization, player) for a future MusicKit source. |
| 11 | **jjotaum/AmuseKit** | https://github.com/jjotaum/AmuseKit | MIT | 2026-04-22 | `Sources/AmuseKit` Apple Music API wrapper | Swift package for Apple Music API on iOS/macOS/tvOS/watchOS | Adding it = third-party dependency; Apple Music API is fine (not "undocumented") but network is out of PoC scope. | 🟢 Reference only — prefer Apple's MusicKit framework directly. |
| 12 | **sora0077/AppleMusicKit** | https://github.com/sora0077/AppleMusicKit | MIT | 2019-05-23 | `AppleMusicKit` API wrapper | Old Apple MusicKit wrapper | **Stale (2019)**; superseded by Apple MusicKit framework. | 🔴 Avoid entirely (obsolete; not useful). |
| 13 | **linkzhong/apple-music-widget** | https://github.com/linkzhong/apple-music-widget | MIT | 2026-08-09 | `Widget/NowPlayingWidget.swift`, `Widget/Provider.swift`, `App/LyricsService.swift`, `App/MusicBridge.swift` | macOS widget with **smoothly scrolling synced lyrics** in WidgetKit | macOS WidgetKit timeline, not Live Activity; not CarPlay. Scrolling lyrics inside a widget is a known push-budget risk. | 🟢 Reference only — its scrolling technique does **not** transfer to CarPlay Live Activity constraints. |
| 14 | **aalemoro/Rota-iOS** | https://github.com/aalemoro/Rota-iOS | MIT | 2026-07-26 | `Rota for iOS` Apple Music home-screen widget, synced lyrics | iOS companion to Rota: artwork-first Apple Music widget with synced lyrics | Widget (timeline) not Live Activity; macOS-focused sibling. 1★. | 🟢 Reference only. |
| 15 | **Dimillian/Musix** | https://github.com/Dimillian/Musix | MIT | 2017-09-05 | `Musix` macOS Apple Music client | Old macOS Apple Music client (18★) | **Stale (2017)**. | 🔴 Avoid entirely (obsolete). |

## CarPlay framework (custom CarPlay apps — the path Caraoke does NOT take)

| # | Repository | URL | License | Last commit | Relevant files | Feature covered | Production risks | Verdict |
|---|---|---|---|---|---|---|---|---|
| 16 | **aws-samples/aws-serverless-fullstack-swift-apple-carplay-example** | https://github.com/aws-samples/aws-serverless-fullstack-swift-apple-carplay-example | MIT-0 | 2024-12-17 | `mobile/mobile/CarPlaySceneDelegate.swift`, `Views/CarPlayMapView.swift`, `mobileApp.swift` | Full-stack CarPlay app (CPTemplate UI) + AWS backend (133★) | Custom **CarPlay framework app** — contradicts Caraoke's D1 (system-rendered Live Activity). AWS backend = networking. | 🟢 Reference only — proves the *other* architecture; not applicable to our Live-Activity approach. |
| 17 | **gastonmorixe/swiftui-carplay-ui-demo** | https://github.com/gastonmorixe/swiftui-carplay-ui-demo | **None** | 2024-11-18 | `MyTrips/CarPlayHelloWorld.swift`, `CarPlaySceneDelegate.swift`, `CarPlayView.swift` | SwiftUI CarPlay demo (3★) | **No license**. Custom CarPlay UI, not Live Activity. | 🔴 Avoid entirely (unlicensed). |
| 18 | **below/CarSample** | https://github.com/below/CarSample | **None** | 2022-07-09 | `CarSample/CarPlaySceneDelegate.swift`, `AppDelegate.swift` | iOS 14 CarPlay sample (33★) | **No license**. Old; custom CarPlay app path. | 🔴 Avoid entirely (unlicensed). |
| 19 | **Kaiede/SwiftCarUI** | https://github.com/Kaiede/SwiftCarUI | MIT | 2024-01-16 | `Sources/SwiftCarUI/...` | Reactive SwiftUI-style wrapper over CarPlay | Abandoned/0★; wrapper = dependency; custom CarPlay path. | 🔴 Avoid entirely (not useful; custom-CarPlay path). |
| 20 | **asecretcompany/yourpods-source** | https://github.com/asecretcompany/yourpods-source | **GPL-3.0** | 2026-08-18 | `YourPods/YourPods/Audio/AudioManager.swift`, `Networking/...`, CarPlay app | Podcast app with CarPlay (25★) | **GPL-3.0** — cannot be copied into a proprietary app. | 🔴 Avoid entirely (GPL). |

---

## Key takeaways for Caraoke

1. **One project does exactly our product** (driveverse, MIT): live lyrics on CarPlay + Lock Screen via one session-spanning Live Activity. Its **architecture** — tiny `ContentState` (title/artist/currentLine/nextLine/progress/isPlaying), one activity per listening session (not per track), update coalescing/throttling, orphan cleanup, `NSSupportsLiveActivitiesFrequentUpdates` handling — is the blueprint to learn from. We reimplemented these ideas from scratch; we did **not** copy its LRCLIB client or Spotify auth (forbidden sources).
2. **CarPlay small-family presentation** is achieved via `.supplementalActivityFamilies([.small])` + branching on `context.activityFamily == .small` (confirmed by [Apple docs](https://developer.apple.com/documentation/widgetkit/activityfamily) and [The.Swift.Dev](https://www.theswift.dev/posts/make-a-live-activity-fit-the-landscape-dynamic-island)). We implemented this independently.
3. **Most lyric repos lean on LRCLIB / unofficial Spotify / NetEase** — all off-limits for Caraoke. The clean path is MusicKit (Apple's official framework) with a lyrics partnership or user-supplied LRC files, not scraping.
4. **Avoid unlicensed (≈half the ecosystem) and GPL** repos entirely; use only MIT/MIT-0 as reference, and never vendor third-party dependencies in the PoC.
5. **No custom CarPlay app** (CarPlay framework) — Caraoke's locked decision D1 is a system-rendered Live Activity, so CarPlay-framework samples are out of scope.

## Sources consulted

- [Apple Developer — ActivityFamily](https://developer.apple.com/documentation/widgetkit/activityfamily)
- [The.Swift.Dev — Make a Live Activity fit the landscape Dynamic Island](https://www.theswift.dev/posts/make-a-live-activity-fit-the-landscape-dynamic-island)
- [Dynamic Lyrics on CarPlay — fixes](https://addcarwidgets.com/blog/dynamic-lyrics-carplay-not-working)
- [9to5Mac — Live lyrics now available in CarPlay](https://9to5mac.com/2026/05/29/live-lyrics-now-available-in-carplay-with-new-app-update/)
- GitHub Search/Repos API for all repository rows above.
