# Dynamic Lyrics (`com.bing.lyrics`) — full extraction inventory

Source: `/Applications/Dynamic Lyrics.app` from a donor Mac (macOS 26.6.2, arm64), pulled
2026-11-01 by ssh over Tailscale into `rea/dynamic-lyrics/raw/`. Personal identifiers — host name,
tailnet IP, account name — are deliberately not recorded here.

## 1. Bundle identity

| Field | Value |
|:--|:--|
| `CFBundleIdentifier` | `com.bing.lyrics` |
| Display name | Dynamic Lyrics |
| Version | `2.0.3` build `177` |
| Variant | **Mac Catalyst** (`CFBundleSupportedPlatforms = [MacOSX]`, fat `x86_64`+`arm64`) |
| Min OS | 14.6 |
| Team ID | `NAC5X5LCW4` |
| Category | `public.app-category.music` |
| `LSUIElement` | `true` (menu-bar/agent app, no Dock icon) |
| `NSSupportsLiveActivities` | `true` |
| Exemption | `ITSAppUsesNonExemptEncryption = false` |
| Binary size | app 28.5 MB, widget 19.6 MB |

URL schemes: `spotify-lyrics-quick-start`, `spotify-lyrics`, `dynamic-lyrics`.
`LSApplicationQueriesSchemes`: `spotify`.

## 2. Critical property: the binaries are NOT encrypted

- No `LC_ENCRYPTION_INFO*` load command in either Mach-O (verified `otool -l`).
- Symbol table intact (`LC_SYMTAB`, 7 148 symbols), Swift metadata sections present
  (`__swift5_typeref`, `__swift5_fieldmd`, `__swift5_protocols`, `__swift5_capture`, …).

Consequence: no decryption step needed. Swift type/method surface, Objective-C selector table,
string literals and **source file paths leak directly** — see §4. The iOS build is encrypted,
so CarPlay evidence must come from iOS artifacts (existing `rea/findings-carplay-lyric-sync.md`).

## 3. Widget extension

`Contents/PlugIns/lyricsWidgetExtension.appex` — `com.bing.lyrics.lyricsWidget`,
`NSExtensionPointIdentifier = com.apple.widgetkit-extension`; links `WidgetKit` + `MediaPlayer` + `ScriptingBridge`.

## 4. Leaked first-party source map

198 distinct `.swift` paths in the app binary, 164 in the widget binary; 82 after filtering
third-party libraries → `out/first-party-sources.txt`. Grouped:

| Area | Files |
|:--|:--|
| App shell | `lyrics/lyricsApp.swift`, `Dynamic_Lyrics/lyricsApp.swift`, `Dynamic_Lyrics/lyricsApp.swift` |
| Core state (TCA) | `LyricsXCore/LyricsXCoreModel.swift`, `Composable/LyricsXCoreModel.swift`, `LyricsXCore/LyricsMusicPlayerModel.swift`, `Composable/LyricsMusicPlayerModel.swift`, `LyricsXCore/LyricsSearchingModel.swift`, `Composable/LyricsSearchingModel.swift` |
| Music players | `Manager/MusicPlayerManager.swift`, `MusicPlayer/SPTWebSessionManager.swift`, `MusicPlayer/SPTWebSession.swift`, `MusicPlayer/SPTWebConfiguration.swift`, `MusicPlayer/ObjCBridge.swift`, `MusadoraKit/SPlayer.swift`, `MusadoraKit/APlayer.swift`, `MusadoraKit/AnimatedArtworkView.swift`, `Helper/MusicPlayerTimerHelper.swift` |
| Lyrics engine | `Data/LyricsBrain.swift`, `Manager/LyricsManager.swift`, `WebAPI/LyricsServiceManager.swift`, `WebAPI/MusixmatchTrackingClient.swift`, `LyricsService/QQMusicQrcDecrypter.swift`, `LyricsService/RegexPattern.swift`, `LyricsCore/RegexPattern.swift` |
| Notch / floating UI | `Notch/MacNotchView.swift`, `Notch/NotchHomeView.swift`, `Dynamic_Lyrics/MacNotchView.swift`, `Dynamic_Lyrics/NotchHomeView.swift`, `Mac/MacFloatingLyricsView.swift`, `Dynamic_Lyrics/MacFloatingLyricsView.swift`, `Dynamic_Lyrics/DraggableNSView.swift` |
| Full-screen lyrics | `FullLyrics/NowPlayingLyricsView.swift`, `Dynamic_Lyrics/NowPlayingLyricsView.swift` |
| Search / upload | `LyricsSearch/LyricsSearchView.swift`, `LyricsSearch/UploadLyricsView.swift`, `Dynamic_Lyrics/LyricsSearchView.swift`, `Dynamic_Lyrics/UploadLyricsView.swift` |
| Intents | `AppIntent/{ControlFloatingLyricsToggleIntent,HadShowFloatingLyricsIntent,JustOpenAppIntent,MusicActionAppIntent,ShowFloatingLyricsIntent,ShowPremiumIntent}.swift`, `lyricsWidgetExtension/MusicActionAppIntent.swift` |
| Monetization | `Store/PremiumView.swift`, `Dynamic_Lyrics/StoreBrain.swift`, `Helper/StoreBrain.swift`, `Dynamic_Lyrics/RefundView.swift` |
| Config / misc | `Config/ConfigManager.swift`, `Helper/KeychainHelper.swift`, `Setting/MacGeneralSettingsView.swift`, `Tips/TipsCenter.swift`, `TranslationEmptyView/TranslationEmptyView.swift` |

Third-party: TCA/`ComposableArchitecture` (swift-dependencies, swift-sharing, swift-navigation, perception,
case-paths), Alamofire, Kingfisher, SnapKit, RNCryptor, OpenCC, SwiftyBeaver,
KeyboardShortcuts, SwiftUIIntrospect, FirebaseAnalytics, GoogleAppMeasurement.

## 5. Feature inventory

### 5.1 Screen / presentation layer
- **Mac notch panel** — `Dynamic_Lyrics.NotchPanel`, `MacNotchView.swift`; config keys
  `_macNotchAddWidth`/`macNotchAddWidthKey`, `macNotchAnimationOnSwitchSongKey`,
  `macNotchBottomLyricsTwoLineKey`, `macNotchBottomLyricsShowTransKey`,
  `macNotchBottomLyricsUseArtworkColorKey`, `macNotchLyricsShowTransKey`,
  `macNotchOpenOnHoverKey`, `_closedNotchSize`, `_hasNotch`.
- **Floating lyrics window** — `MacFloatingLyricsView.swift` + `DraggableNSView.swift`
  (AppKit drag; `LSUIElement` agent app).
- **Full-screen lyrics view** — `FullLyrics/NowPlayingLyricsView.swift`.
- **Menu-bar "Dynamic Notch"** — control items `ControlFloatingLyricsToggleIntent`,
  `HadShowFloatingLyricsIntent`, `ShowFloatingLyricsIntent`, `JustOpenAppIntent`, `ShowPremiumIntent`.
- **iOS-only surface implied by keys** (not present in Mac build): `dynamicIsland`,
  `dynamicIslandBottomLyrics`, `DynamicIslandFontSize`, `DynamicIslandSize`, `DynamicIslandHide`,
  `dynamicIslandLyricsUseArtworkColorKey`, `dynamicIslandShowTransKey`, `dynamicIslandPannel`,
  `expandDynamicIsland`, `hideDynamicIslandOnPause`.

### 5.2 Lyrics retrieval — 13 providers
| Provider | Endpoint |
|:--|:--|
| own API | `https://api.musiclyrics.cn/{get_lyrics,sync_lyrics,check_lyrics,report_lyrics,get_lyrics_fix_list,singer_config,sys_config,alert_config}` |
| lrclib | `https://lrclib.net/api/{get,search}` |
| NetEase | `http://music.163.com/api/{search/pc,song/lyric}` |
| QQ Music | `https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg`, `.../qqmusic/fcgi-bin/lyric_download.fcg`, `.../splcloud/fcgi-bin/smartbox_new.fcg` |
| Kugou | `http://lyrics.kugou.com/{search,download}` |
| Xiami | `http://api.xiami.com/web`, `http://h.xiami.com` |
| Gecimi | `http://gecimi.com/api/lyric` |
| Crintsoft (MiniLyrics format) | `http://search.crintsoft.com/searchlyrics.htm` |
| ViewLyrics | `http://viewlyrics.com` |
| Lyricsify | `https://www.lyricsify.com` |
| Syair | `syair.info` (ATS exception only) |
| Musixmatch | `WebAPI/MusixmatchTrackingClient.swift` |
| ShazamKit | `ShazamKit`, `shazamID`, `shazamRecognitionIntervalKey`, `shazamTrackDidUpdate`, `shazamTimer` → **mic-based song recognition** |

Lyrics formats handled: plain LRC, QQ Music QRC (`QQMusicQrcDecrypter.swift`), Musixmatch richsync.

### 5.3 Player integration
- `MediaPlayer.framework` (`MPNowPlayingInfoCenter`) — 6 `NowPlaying` refs.
- **Spotify**: OAuth (`accounts.spotify.com/authorize`, `/api/token`), scopes to
  `api.spotify.com/v1/me/{player,library/contains,library/playlists}`, custom
  `SPTWebSession*` + `SPTWebConfiguration` (web-playback), deep links via `spotify-lyrics*` schemes.
- **Apple Music**: `MusicKit` (1 145 symbol refs) + `amp-api.music.apple.com/v1/catalog/`,
  `api.music.apple.com/v1/me/library/playlists/`, `MusadoraKit` wrapper.
- **ScriptingBridge / AppleEvents → 9 players** (temporary-exception entitlement):
  `com.apple.Music`, `com.apple.iTunes`, `com.spotify.client`, `com.coppertino.Vox`,
  `com.audirvana.Audirvana{-Studio,-Plus,-Origin}`, `com.swinsian.Swinsian`.
- Notification `com.bing.lyrics.MusicPlayer.Update` — app↔widget/IPC bus.

### 5.4 CarPlay — mechanism confirmed from their own strings

Mac build links **no** `CarPlay.framework` and defines no `CP*` symbols (verified). The mechanism is
nevertheless fully documented by their own UI copy (`Contents/Resources/en.lproj/Localizable.strings`,
355 keys) and confirmed by keys present in **both** binaries
(`carPlayCompatibilityModeKey`, `carplayLyricsGlobalDelayKey`, `isCarplayConnectedKey`,
`isCarplayIndependentDelayKey`, `_isCarplay`, `_carplayLyricsGlobalDelay`,
`_isCarplayIndependentDelay`, `UNAuthorizationOptions.carPlay`):

| Their string (EN) | Mechanism it proves |
|:--|:--|
| *"Show lyrics on the Dynamic Island, Lock Screen, CarPlay, and Apple Watch"* | CarPlay lyrics = mirrors the **Live Activity**, not a native CarPlay app |
| *"You can add widgets to desktop, CarPlay, StandBy, etc."* | CarPlay is also a **widget host** (iOS 26 CarPlay widget pages) |
| *"Enable Live Activities to show lyrics on CarPlay"* / *"Show lyrics on the Dynamic Island, Lock Screen, CarPlay, and Apple Watch"* | hard precondition: `NSSupportsLiveActivities` must be granted, else CarPlay shows nothing |
| *"CarPlay Compatibility Mode"* — *"If lyric updates in CarPlay Live Activities are delayed after the phone is locked, please enable Compatibility Mode to fix the issue."* | the post-lock update-delay bug and their fix |
| *"CarPlay Delay"* / *"Set Delay Separately for CarPlay"* (`isCarplayIndependentDelayKey`) | per-CarPlay lyric offset, independent of the global offset |
| *"If CarPlay live activity overlaps, turn this switch on to fix it."* (`carPlayCompatibilityModeKey`) | second CarPlay-specific layout workaround |
| *"Display background on Watch and CarPlay"* | background/artwork rendering variant |
| *"Enable Live Activities to show lyrics on CarPlay"* | same gate restated at widget level (`Localizable.strings` of the appex, 34 keys) |

Also from the same file: global vs per-lyric delay stacking (*"The global delay will apply to all
lyrics and will be added to the delay set for each lyric"*), Live Activity auto-start
(*"After turning it on, there is no need to click 'Start showing lyrics' … but there will be a task
that stays in the background"*), iOS 27 experimental mode, Dynamic Island width/independence
(*"Swipe left on the Music Smart Island to have Dynamic Lyrics displayed independently"*),
Control Center/Control Widget toggles, Premium gating of background rendering, and the
Spotify OAuth failure/repair flow.

**Replication verdict:** CarPlay support does not require the CarPlay framework — it requires
(i) Live Activity screen mirroring, (ii) support for the CarPlay widget surface, (iii) a per-CarPlay
delay setting, (iv) two compatibility workarounds for post-lock delays and overlapping layouts.
This matches the CarPlay findings already recorded in `rea/findings-carplay-lyric-sync.md`.

### 5.5 Monetization
StoreKit 2 subscription: product IDs `com.bing.lyrics.premium`, `.premium.month`, `.premium.year`.
Persistence: `GenericID.Subscription` / `MultiValueSubscription`, `getSavedPremiumInfo()`,
`insertIfNotDuplicateSubscriptionID:error:`, `deleteSubscriptionsOverLimit:`,
`dedupeSubscriptionEvent:`, `routingSubscription`. `RefundView.swift` present.
Support links: `dynamic-lyrics.super.site/english/common-problem/get-a-free-premium`,
`.../configuring-a-custom-client-id` (BYO Spotify client ID), App Store review link
`apps.apple.com/app/id6476125287?action=write-review`.

### 5.6 Persistence / IPC
| Mechanism | Evidence |
|:--|:--|
| App Group | `NAC5X5LCW4.com.bing.lyrics` (identical entitlement in app **and** widget) |
| `UserDefaults` / `NSUserDefaults` | 61 / 32 refs — the settings + live-state channel |
| Keychain | 16 refs, `Helper/KeychainHelper.swift` (Spotify tokens / premium) |
| iCloud / `NSUbiquitousKeyValueStore` / CloudKit | 5 / 1 / 1 refs — settings sync |
| sqlite | 16 refs (libsqlite3 linked; local cache) |
| Push | Firebase Cloud Messaging, `didRegisterForRemoteNotificationsWithDeviceToken` |
| RNCryptor | local payload crypto |

### 5.7 Permissions / sandbox
App: sandboxed; `network.client`; `files.user-selected.read-only`; `audio-input`
(mic → Shazam); `automation.apple-events` + 9-player temporary exception;
app group. Widget: sandboxed + same app group (`metadata/entitlements-widget.xml`).
Usage strings: *"We need media info to search for lyrics"*, *"We requires permission to use
microphone to recognize songs"*.

### 5.8 Module membership (verified by source-path presence per binary)

| Source | app | widget appex |
|:--|:--|:--|
| `Manager/LyricsManager.swift` | ✔ | ✔ |
| `Manager/MusicPlayerManager.swift` | ✔ | ✔ |
| `MusicPlayer/SPTWebSession.swift` | ✔ | ✔ |
| `lyricsWidgetExtension/MusicActionAppIntent.swift` | — | ✔ |
| `Data/LyricsBrain.swift` | ✔ | — |
| `Mac/MacFloatingLyricsView.swift` | ✔ | — |

App binary carries 198 distinct `.swift` paths; widget 164, of which **163 also appear in the app** —
only `lyricsWidgetExtension/MusicActionAppIntent.swift` is widget-exclusive. The widget extension
is **not** a thin view: it links the whole shared lyrics/player/web-session core, and the app group
(`NAC5X5LCW4.com.bing.lyrics`, entitled in both targets) is the state channel. Replication lesson:
one shared core module + app-group defaults, not a bespoke widget IPC protocol.

### 5.9 Recovered concrete API surface (symbol tables, no decryption needed)

The **widget** binary is the symbol-rich one (62 219 symbols; app binary exposes 7 024, mostly
Objective-C + imports). `out/first-party-symbols-widget.txt` (1 788 entries) is the raw material for
re-implementation. Highlights:

- `LyricsXCore.LyricsManager` — `getLyrics`, `fetchLyrics`, `searchAppleMusicLyric`,
  `searchLyricsPublisher`, `updateLyricsProvider`, `currentLyrics`, `currentTrack`,
  `currentLyricsError`, `isPureMusic`, `markAsPureMusic`, `removePureMusicMark`,
  `genLyricsFromFile`, `saveFile`, `clearLyricsDirectoryInAppGroup`,
  **`moveLyricsToAppGroup`**, `currentIsShowTrans`, `isFromWidget`, `musicLyricsDelegate`.
- `LyricsXCore.MusicPlayerManager` — `updateCurrentPlayer`, `updateWidgetCurrentTrack`,
  `updateWidgetCurrentArtworkImage`, `updateWidgetCurrentPlayState`,
  `updateWidgetCurrentConnectState`, `updateWidgetSkipBtnState`.
- `LyricsService.LyricsProviders.*` — one class per provider, each with
  `lyricsSearchPublisher` / `lyricsFetchPublisher` / `tokenLyricsPublisher` / `service`:
  `Gecimi`, `Kugou`, `LrcLib`, `NetEase`, `QQMusic`, `Syair`, `ViewLyrics`, `Xiami`, plus the
  aggregators `Group` (fan-out), `Service` and `Unsupported`.
- Widget extension types: `LyricsBrain`, `LyricsConfigManager`, `LyricsServiceManager`,
  `MusixmatchTrackingClient`, `ConfigManager`, `LiveActivityBackground`, `DefaultArtworkImage`,
  `FullLyricsAlignmentType`, `LyricsViewType`, `ScrollAniText`/`ScrollText`,
  `ScrollAnimationModifier`, `SwingAnimationModifier`, `ClockAnimationModifier`,
  `ClockHandEffectPeriod`, `ShazamRecognitionInterval`, `MusicPlayerTimerHelper`, `URLTool`.
- App-side extras: `MusicPlayer.MusicPlayers.Agent` / `.Virtual`, `MusicPlayer.MusicTrack`,
  `MusicPlayer.PlaybackState`.

`AudioToolbox`-adjacent `MusicPlayer` module carries 513 first-party symbols in the widget —
i.e. the player stack really is shared into the extension.

### 5.10 Localization

8 locales: `ar, en, es, fr, ja, ko, zh-Hans, zh-Hant` — each with `Localizable.strings`
(plus an `InfoPlist.strings` inside the widget appex).

## 6. Artifacts in this directory

```
rea/dynamic-lyrics/
├── INVENTORY.md                 ← this file
├── raw/Dynamic Lyrics.app/      ← full 167-file bundle (28.5 MB app + widget appex)
└── out/
    ├── symbols-arm64-demangled.txt   (7 024 syms, swift-demangle'd)
    ├── symbols-widget-demangled.txt  (62 219 syms — widget is the symbol-rich binary)
    ├── first-party-symbols-widget.txt (1 788 recovered API entries)
    ├── first-party-symbols-app.txt
    ├── objc-metadata.txt             (3.8 MB — otool -oV dump)
    ├── strings-app.txt               (118 290 strings)
    ├── strings-widget.txt            (79 084 strings)
    ├── mangled-names.txt / mangled-demangled.txt
    ├── localizable-app-en.json        (355 UI strings — richest behaviour source)
    ├── localizable-widget-en.json     (34 strings)
    └── first-party-sources.txt       (82 leaked source paths)
rea/metadata/
├── Info-app.plist, Info-widget.plist
├── entitlements-app.xml, entitlements-widget.xml
└── codesign-app.txt
```

## 7. Framework delta vs the iOS build (one line)

Mac links `AppKit`, `Carbon`, `CoreVideo`, `IOKit`, `ScriptingBridge`, `ServiceManagement`, `WebKit`;
iOS links `UIKit`, `ActivityKit`, `CarPlay`, `CallKit`, `AVFAudio`, `AVKit`, `ClockEffect`,
`SpotifyiOS` instead. Full table in `INVENTORY-IOS.md` §8.

## 8. Gaps / next steps for full replication
0. **Wording correction (2026-11-01).** An earlier summary in this session claimed the Mac and iOS
   builds were "the same bytes". That was wrong: the Mac target is **Catalyst and lags at 2.0.3
   (177)** — `ipatool download --platform macos` returns a binary byte-identical to the installed
   app (SHA-256 `a1fdd3ffa2620d25…`), while the iOS target is already **2.0.7 (181)**. All
   CarPlay / Live Activity / Dynamic Island code exists only in the iOS build; see
   `INVENTORY-IOS.md` for the decrypted iOS extraction.
1. **Widget family list & timeline policy** — neither appex declares `NSExtensionAttributes`, and
   neither binary contains `WidgetFamily` literals, so families are decided at runtime by WidgetKit.
   Timeline policy is inferred from behaviour (archived teardown in
   `rea/findings-carplay-lyric-sync.md`: entry count 1, `.atEnd`, ~1.6 s wakes) and is now
   explained by `LyricsXCore.LyricScrollSegment.nextRefreshInterval` (see `INVENTORY-IOS.md` §6).
2. **iOS binary** — done 2026-11-01: decrypted via recovered FairPlay enrollment model; see
   `INVENTORY-IOS.md` (Live Activity model, CarPlay verdict, refresh engine, 28 iOS-only sources).
3. **Cloud API contract** — `api.musiclyrics.cn` is their own service; live calls would need
   an AuthKey (observed in the archived teardown).
4. No obfuscation and no anti-debug shims (zero refs to `ptrace`/`PT_DENY_ATTACH`/`sysctl`/
   `dlopen`/`task_for_pid`/frida/cycript in either binary), but the Mach-O is signed with the
   **hardened runtime** (`flags=0x10000(runtime)`) and runs under `com.apple.security.app-sandbox`,
   so `lldb` cannot attach to the live signed process. Runtime introspection requires copying the
   binary and stripping its signature (`codesign --remove-signature`) or disabling SIP — only worth
   it if Spotify web-session internals are ever needed.
