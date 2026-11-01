# Dynamic Lyrics — iOS build extraction (v2), decrypted

Companion to `INVENTORY.md` (Mac 2.0.3). This is the **iOS** artefact, obtained remotely over
Tailscale on 2026-11-01 and decrypted locally from the recovered FairPlay enrollment model.

## 1. Acquisition pipeline (reproducible)

Host: a donor Mac on the operator's tailnet (macOS 26.6.2, arm64), reached by ssh over Tailscale.
Personal identifiers — host name, tailnet IP, account name — are deliberately not recorded here.

```bash
brew install ipatool                       # 2.7.0
/opt/homebrew/bin/ipatool auth login -e '<apple-id>' -p '***'   # 2FA once, never stored
ipatool purchase  -b com.bing.lyrics --platform iphone       # alreadyOwned=true
ipatool download  -b com.bing.lyrics --platform iphone -o dl-ios.ipa    # 26.7 MB
ipatool download  -b com.bing.lyrics --platform macos  -o dl-macos.ipa  # 15.1 MB, xar/pkg

# FairPlay recovery: needs an App-Store enrollment for the same account
sudo unfairplay setup --app "<extracted iOS .app>" --ipa dl-ios.ipa
# -> success=true, decrypted_pages=4548, selector=e4cb189b:00000002
unfairplay decrypt --input dl-ios.ipa --output dl-ios-decrypted.ipa --strip-account-data
```

Gotchas hit, worth keeping:
- `ipatool auth login` **writes to the login keychain**; over ssh this fails with
  `-25308 User interaction is not allowed`. Fix: `security unlock-keychain -p <pw> "$HOME/Library/Keychains/login.keychain-db"`
  in the *same* ssh command, then login succeeds (no second 2FA needed on the retry).
- `unfairplay setup` accepted the **extracted Payload app**, not an installed `/Applications` copy —
  no iOS-app install/wrapper bookkeeping was required.
- `ipatool download --platform macos` produces a **xar/pkg**, not a zip; `unzip` rejects it.
- Installing the iOS build into `/Applications` via `mas` does not work as a manual copy; a real
  wrapper needs `BundleMetadata.plist` (NSKeyedArchiver `MIBundleMetadata`) plus installer bookkeeping.

## 2. Identity: iOS vs Mac

| Field | iOS (this doc) | Mac (INVENTORY.md) |
|:--|:--|:--|
| Version | **2.0.7 (181)** | 2.0.3 (177) |
| `CFBundleSupportedPlatforms` | `iPhoneOS` | `MacOSX` (Catalyst) |
| `UIDeviceFamily` | 1, 2 | — |
| `MinimumOSVersion` / `LSMinimumSystemVersion` | 17.0 | 14.6 |
| `NSSupportsLiveActivities` | **true** | true |
| `NSSupportsLiveActivitiesFrequentUpdates` | **true** | — |
| `UIBackgroundModes` | **`audio`** | n/a |
| `aps-environment` entitlement | **production** | — |
| App group | **`group.com.bing.lyrics`** | `NAC5X5LCW4.com.bing.lyrics` |
| Binary | 14.0 MB, `cryptid 1` → decryptable | 28.5 MB, plaintext |
| Widget appex binary | 9.7 MB, `cryptid 1` | 19.6 MB, plaintext |
| Widget bundle id | `com.bing.lyrics.lyricsWidget` | same |
| Linked iOS-only frameworks | **`ActivityKit`, `CarPlay`, `libswiftCarPlay`** | none of these |
| Locales | 8 (`ar en es fr ja ko zh-Hans zh-Hant`) | same 8 |
| App UI strings | 377 EN keys | 355 EN keys |
| Widget UI strings | 34 | 34 (identical set) |
| App Intents | 11 | 6 |

App-group identifier **differs between platforms** (`group.*` vs team-prefixed) — if we mirror their
architecture, keep the group id platform-local and abstract it behind one constant.

## 3. Entitlements (iOS, from the signed IPA)

App: `application-identifier = NAC5X5LCW4.com.bing.lyrics`, `aps-environment = production`,
app group `group.com.bing.lyrics`.
Widget: app group only.
Note what is **absent** vs the Mac build: no AppleEvents / ScriptingBridge exceptions, no
`audio-input` in the app entitlement set (the mic purpose string still exists for ShazamKit) —
the Mac version's 9-player AppleScript bridge is a Mac-only mechanism.

## 4. Live Activities + Dynamic Island

Declared surface:
- `NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates` = true.
- Binary imports the whole ActivityKit surface: `Activity.request(attributes:content:pushType:)`,
  `Activity.update(_:alertConfiguration:)`, `Activity.end(_:dismissalPolicy:)`,
  `activityStateUpdates`, `activityUpdates`, `pushTokenUpdates`, `pushToStartTokenUpdates`,
  `ActivityUIDismissalPolicy.immediate`, `ActivityAuthorizationError.denied`.
- Widget-side types: `lyricsWidgetExtension.LiveActivityHelper`, `LiveActivityBackground`,
  `LAPlayer`, `RefreshKeeper`, `RefreshPlayer`; attributes struct **`LyricsWidgetAttributes`**
  with a `ContentState` (attribute names visible in the metadata string table; layout not recoverable).
- Keys: `showLiveActivityKey`, `liveActivityShowTransKey`, `liveActivityAutoHideTimeKey`,
  `refreshLiveActivityRealTimeKey`, `showRefreshLiveActivityBtnKey`,
  `smallLiveActivityUseArtworkBgKey`, `liveActivityProtectedDataAvailableKey`,
  `dynamicIslandLyricsUseArtworkColorKey`, `dynamicIslandShowTransKey`, `DynamicIslandFontSize`,
  `DynamicIslandSize`, `dynamicIslandBottomLyrics`, `expandDynamicIsland`, `hideDynamicIslandOnPause`.
- iOS 27 fast path: notification `didStartiOS27LiveActivityAutoRefresh` —
  *"After enabling Experimental Mode, you no longer need to tap the Start button for Live Activities"*.
- Entry points: `Lock Screen & Dynamic Island Lyrics`, `Show lyrics on the Dynamic Island, Lock Screen,
  CarPlay, and Apple Watch`, `Enable Live Activities to show lyrics on CarPlay`.

## 5. CarPlay — final verdict

Three independent checks agree:

| Check | Result |
|:--|:--|
| `CarPlay.framework` linked? | **yes** (app + widget) |
| Any CarPlay *API* imported? | **no** — only `__swift_FORCE_LOAD_$_swiftCarPlay` |
| `CP*` classes in the decrypted binary | **one anonymized generic binding** (`So10CPListItemCRbzlXX` in Kingfisher's `ImageDataProvider` conformance list); no `CPTemplate`, `CPSearchTemplate`, `CPInterfaceController` |
| `UIApplicationSceneManifest` | `UISceneConfigurations = {}` — **no CarPlay scene role declared** |

Reading: they link the framework (and use `CPListItem` at most generically) but ship **no CarPlay
app scene**. CarPlay lyrics reach the car through (a) Live-Activity mirroring and (b) the CarPlay
widget surface, with `carPlayCompatibilityModeKey` fixing post-lock update delay and overlapping
layouts, and `isCarplayIndependentDelayKey` giving CarPlay its own lyric offset.
`IsCarPlayConnectDidChanged` (`isCarplayConnectedKey`) is the state-change notification that flips
the per-CarPlay behaviour.

## 6. The refresh engine (the actual IP)

Recovered pieces that explain the wake loop measured in earlier sessions:

| Symbol | Meaning |
|:--|:--|
| `LyricsXCore.LyricScrollSegment` | per-line segment: `startProgress`, `endProgress`, `duration`, `curve` (`Curve.init(rawValue:)` — a Bezier-ish enum), **`nextRefreshInterval`**, `init(lineDuration:)` |
| `lyricsWidgetExtension.ClockAnimationModifier` | `start`, `duration`, `refreshTime`, `contentWidth/Height`, `viewWidth` |
| `lyricsWidgetExtension.ClockHandEffectPeriod` | period model for the same clock animation |
| `lyricsWidgetExtension.RefreshKeeper` / `RefreshPlayer` | **ObjC classes**, both keeping an audio player: selector `audioPlayerDidFinishPlaying:successfully:`, plus `callObserver`/`CXCallObserverDelegate` on the keeper |
| `lyricsWidgetExtension.SwingAnimationModifier`, `ScrollAnimationModifier`, `ScrollAniText`, `ScrollText` | scroll/swing presentation |
| `LyricsXCore.MusicPlayerManager.needReloadLiveActivityFlag` (`Combine.Published`) | reload coalescing flag |
| `lyricsWidgetExtension.LiveActivityHelper` | ObjC-visible LA control surface |

Design reading: lyric lines are converted into (progress, duration, curve) segments; each segment
carries its own `nextRefreshInterval`, which is what schedules the next widget/Live-Activity reload —
i.e. reloads are **lyric-timed**, not fixed-rate. `RefreshKeeper`/`RefreshPlayer` keep the process
alive with silent audio + call-observer handling, consistent with `UIBackgroundModes = [audio]`.
Their measured cadence (1 × entry, `.atEnd`, ~1.6 s wakes in `rea/findings-carplay-lyric-sync.md`)
therefore matches: one baked entry, reloaded on the lyric clock.

## 7. iOS-only code and features (delta vs the Mac build)

28 first-party source paths exist only in the iOS targets:

```
AppIntent/{ControlLiveActivityToggleIntent,RefreshAppIntent,ToggleLiveActivityIntent,WidgetRefreshAppIntent}.swift
Helper/{BackgroundTaskHelper,LiveActivityHelper,LiveActivityRefresher}.swift
lyricsWidgetExtension/WidgetRefreshAppIntent.swift
FloatingLyrics/FloatingLyricsView.swift           (also Dynamic_Lyrics/FloatingLyricsView.swift)
Home/{MainView,BottomToolView}.swift
MusicPlayer/SpotifyiOS.swift                       (official Spotify iOS SDK instead of SPTWebSession)
Navigation/*, UIKitNavigation/*, UIKit/NavigationStackControllerUIKit.swift
```

iOS-only UI copy (22 keys) is almost entirely **membership/restore hardening**:
*"Your membership could not be confirmed. Please try again later or restore purchases."*,
*"Your purchase was successful, but your membership has not finished syncing. Please do not pay again."*,
*"Clear this app's Keychain data"*, plus `Lock Screen & Dynamic Island Lyrics` and
*"Live Lyrics on CarPlay"*.

Leaked absolute build paths reveal their repo layout:

```
/Users/bing/Desktop/bing/Lyrics-iOS/lyrics/...           (app target: Composable/, Config/, Helper/, Shared/Data/AppIntent/)
/Users/bing/Desktop/bing/Lyrics-iOS/LyricsXCore/Sources/LyricsXCore/Composable/Manager/LyricsManager.swift
```

App Intents (11) — `extract.actionsdata`: `ControlFloatingLyricsToggleIntent`,
`ControlLiveActivityToggleIntent`, `HadShowFloatingLyricsIntent`, `JustOpenAppIntent`,
`MusicActionAppIntent`, `MusicActionAppIntent18`, `RefreshAppIntent`, `ShowFloatingLyricsIntent`,
`ShowPremiumIntent`, `ToggleLiveActivityIntent`, `WidgetRefreshAppIntent`.

Privacy manifest: only `NSPrivacyAccessedAPICategoryUserDefaults` (reason `1C8F.1`).

Assets: `singerConfig.plist` (Chinese singer/song name mapping) and `systemConfig.plist`
(`musicLyrics.access` AuthKey for `api.musiclyrics.cn`, `filtrate.filterKeys` regexes that strip
credits from lyrics, `matchQuality`, `localLyrics`, `fromMusic/fromServer/upload` flags).

## 8. Framework delta (iOS vs Mac, from `otool -L`)

**iOS-only:** `ActivityKit`, `CarPlay` (+`libswiftCarPlay`), `CallKit` (+`libswiftCallKit`),
`ClockEffect` *(bundled)*, `SpotifyiOS` *(bundled)*, `UIKit`, `AVFAudio`, `AVKit`, `CoreMedia`,
`CoreTelephony`, `DeveloperToolsSupport`, `LinkPresentation`, `MessageUI`, `SafariServices`,
`_MusicKit_SwiftUI`, `_StoreKit_SwiftUI`.
**Mac-only:** `AppKit`, `Carbon`, `CoreVideo`, `IOKit`, `ScriptingBridge`, `ServiceManagement`, `WebKit`.

Reading: the Mac build swaps `UIKit` for `AppKit` and `SpotifyiOS` for a web-session shim
(`SPTWebSession*`), uses `ScriptingBridge`/`Carbon` for its 9-player AppleScript bridge, and keeps
`WebKit` for the OAuth flow. `CallKit` + `CoreTelephony` on iOS pair with the `CXCallObserverDelegate`
on `RefreshKeeper` — lyrics updates pause during a phone call.

Bundled third-party frameworks (iOS): `SpotifyiOS`, `ClockEffect`, `FirebaseAnalytics`,
`GoogleAppMeasurement(+IdentitySupport)`, `GoogleAdsOnDeviceConversion`.

`ClockEffect.framework` (72 KB, 62 symbols, built with the iOS 15.5 SDK / Xcode 13.4.1) — public surface:

```swift
enum ClockEffectPeriod { case secondHand, hourHand, miniuteHand /*sic*/, custom(Double) }
extension SwiftUI.View {
    func clockEffect(period: ClockEffectPeriod, timezone: TimeZone, anchor: UnitPoint) -> some View
}
```

It ships **unencrypted even in the Store IPA** (`cryptid 0`, `cryptsize 16384`). It drives
`lyricsWidgetExtension.ClockAnimationModifier` / `ClockHandEffectPeriod` — the ticking-hand effect
tied to lyric progress.

iOS-only photos/AV surface: `NSPhotoLibraryAddUsageDescription` (*"save lyrics image to album"*),
`AVFAudio`/`AVKit`, `PHPickerResultImageDataProvider` (Kingfisher's PHPicker bridge).

## 9. Gaps

1. **Widget family list** is still not in any plist: both the iOS appex and the Mac appex declare
   only `NSExtensionPointIdentifier`, and neither binary contains `systemSmall`/`accessoryRectangular`
   literals (`WidgetFamily` is built by WidgetKit). Only a runtime render shows it.
2. **Live Activity layout** (`LyricsWidgetAttributes.ContentState` fields) lives in Swift metadata
   without a string table; names are visible, structure needs reflection.
3. **Mac 2.0.7 does not exist for this account** — the `--platform macos` download (`macos-2.0.7-personalized.ipa`,
   misnamed) contains **2.0.3 (177)** and its Mach-O is byte-identical to the installed Mac app
   (SHA-256 `a1fdd3ffa2620d25…`), unpacked via `pkgutil --expand-full` into `raw/mac_pkg/`.
   So the Mac line is genuinely behind the iOS line, and no Mac delta remains to mine.
4. Apple Watch: neither target ships a Watch app (`WatchKit` strings come from linked SDK code);
   watch lyrics are the Live Activity mirrored to the watch face.

## 10. Local artefacts

```
raw/ios-2.0.7-personalized.ipa       26.7 MB  (SC_Info retained; account-bearing — do not share)
raw/ios-2.0.7-decrypted.ipa          16.6 MB  (--strip-account-data applied)
raw/macos-2.0.7-personalized.ipa     15.1 MB  (xar/pkg)
raw/ios/Payload/…                    personalized copy
raw/iosd/Payload/…                   decrypted copy (analysis source)
out/ios-app-symbols-demangled.txt    6 835 lines
out/ios-widget-symbols-demangled.txt 55 573 lines
out/ios-widget-objc-metadata.txt     20 977 lines
out/ios-strings-app.txt              40 315 lines
out/ios-strings-widget.txt           20 456 lines
out/ios-source-tree-paths.txt        89 leaked absolute build paths
```

All of `raw/` and `out/` are gitignored (`.gitignore` 52–54). The decrypted IPA is a third-party
app; keep it local, do not redistribute.

## 11. Source Mac — left exactly as found (**cleanup completed 2026-11-01**)

- `ipatool` (brew), `mas` (brew) were **installed by me for this job and are now uninstalled**;
  `unfairplay` and `/tmp/upwork/` removed. Their brew set is back to its pre-job list
  (tailscale, openjdk@21, jmeter, postgresql@14, git, …). No credentials of ours on that machine.
- FairPlay **enrollment model** — **deleted** (`~/Library/Application Support/unfairplay/` removed).
  It was tied to that Mac + that Apple Account and could have decrypted their other IPAs.
- `~/dl/` (IPAs, JSON report, extracted copies, backup) — **deleted**; directory removed.
- `/Applications/Dynamic Lyrics.app` — deleted during cleanup, then **restored** from the
  byte-identical local copy: version `2.0.3`, platform `MacOSX`, identifier `com.bing.lyrics`,
  `codesign -v` passes (rc=0), launches.
- `pmset` — `sleep` back to `1`, `disablesleep` back to `0`.

