# Competitor teardown: how CarPlay lyric apps actually sync

Date: 2026-10-26, 01:30–02:00. Method: 7 IPAs pulled from the App Store with
ipatool 2.7.0 (user's Apple ID, free licenses via `--purchase`), unpacked and
inspected: bundle inventory, Info.plists, entitlements, asset catalogs,
localized resources. Binaries are FairPlay-encrypted (`LC_ENCRYPTION_INFO_64`),
so code-level RE is closed — this teardown is structural, and structural was
enough to answer every open question.

## 1. The apps

| App | Bundle | Widget ext | LA | LA-frequent | BG audio | App Group | Push |
|:--|:--|:--|:--|:--|:--|:--|:--|
| **Dynamic Lyrics** (the user's competitor, installed on their phone) | com.bing.lyrics | 1 × widgetkit | ✓ | ✓ | ✓ | ✓ | ✓ |
| Dynamic Lyrics - Ride & Play | com.mobime.lyrica | 1 × widgetkit | ✓ | ✓ | — | ✓ | ✓ |
| Dynamic Lyrics Karaoke (Gameville) | com.carplay.lyrics.DynamicLyrics | 1 × widgetkit | ✓ | ✓ | ✓ | ✓ | ✓ |
| Lyrify | com.serkandyck.dynamic.lyrics.DynamicLyrics | 1 × widgetkit | ✓ | ✓ | ✓ | ✓ | — |
| Lyri | com.carplaylyrics.app.ios | 1 × widgetkit | ✓ | ✓ | ✓ | ✓ | ✓ |
| Musixmatch | com.musixmatch.lyrics | 2: widgetkit **+ Notification Service ext** | ✓ | ✓ | ✓ | ✓ | ✓ |
| (Vibe, "Dynamic Lyric: Car Widget", LyricLane failed to download — region/paid) | | | | | | | |

All rows verified by direct plist/entitlement reads (no inference). Musixmatch's
Notification Service extension is how it decodes server-push Live Activity
payloads off the APNs pipe — push-LA at scale.

**Every single one**: one WidgetKit extension (widgets + Live Activity in the
same binary), Live Activities enabled, background audio to stay alive, an App
Group for app↔extension state. **Nobody ships a CarPlay app scene** (no
CPTemplate scene configuration, no CarPlay entitlement anywhere). Nobody has a
second extension. The architecture is uniform — and it is *our* architecture
minus the App Group (we use the shared keychain instead, which works).

Lyrify leaks its backend in Info.plist:
`SpotifyTokenRefreshURL = https://lyrics-worker.serkandayicik.workers.dev/refresh`
— a Cloudflare Worker that holds user Spotify refresh tokens server-side.
That is the infrastructure behind server-polled, push-updated Live Activities:
their lyric updates keep flowing even with the app suspended. We cannot copy
this without storing users' Spotify credentials on a server, which this
project's privacy rules forbid. This is their moat, not their trick.

## 2. What actually animates on CarPlay (four independent sources)

**a. Our own stamps (build 71, tonight, §11 of findings-carplay-lyric-sync.md).**
Healthy 63–72-entry timelines baked with fresh anchors; N/e/b frozen for 75 s
on screen. The bake machinery is provably fine.

**b. The system's own renderer logs** (WidgetRenderer_CarPlay,
com.apple.chrono, from the same logarchive, /tmp/wrc.txt):
- `Evaluated inner view with result: LIVE … reasons: [timelineAdvancedOrNewArchive]`
  fires when a NEW archive lands (a reload), not as per-entry ticks.
- After loading our 72-entry timeline: `Scheduling staleness check in
  1199.78s` — the renderer plans its next self-evaluation ~20 minutes out.
- Every view evaluation in the window for every app (including Apple's own
  Weather tile) has reason `foreground`, `newEnvironment`,
  `layerSeparationChanged`, or `newArchive`. **No widget on CarPlay advances
  entry-by-entry on this iOS (26.5.2).**

**c. Apple documentation.** "Keeping a widget up to date" describes
entry-to-entry advancement as pre-rendered system behavior, but no
CarPlay-specific advancement is documented or promised. WWDC25 session 278
("What's new in widgets") and 216 ("Turbocharge your app for CarPlay") specify
CarPlay widgets = `systemSmall` in a StandBy style, configured in Settings >
CarPlay, with "the general update mechanisms" applying — and both push the
Live Activity (`supplementalActivityFamilies([.small])`) as the CarPlay
surface. Nothing anywhere promises animated widget tiles on CarPlay.

**d. The competitors.** All of them ride the Live Activity (with frequent
updates; some with server push) + background audio. None attempts anything
else. The fluid "CarPlay widgets" the user saw in Dynamic Lyrics = the Live
Activity tile in the CarPlay dashboard.

## 3. Conclusions

1. **Per-line animated lyrics on CarPlay widget tiles is not achievable.** Not
   by us, not by anyone — the surface re-renders on reloads and screen events
   only. This is the platform, not our bug. (Verified on PlayPort; the in-car
   head unit may differ, and build 71/72 has never been driven — see §5.)
2. **Our Live Activity is already the correct primary surface and already at
   config parity** with every competitor: `NSSupportsLiveActivities`,
   `NSSupportsLiveActivitiesFrequentUpdates`,
   `.supplementalActivityFamilies([.small])` with a `carPlaySmall`-tailored
   layout (LyricsLiveActivity.swift:39–80), background audio via
   RideAudioKeeper. Checked line-by-line tonight.
3. **The widget tiles' job is now "correct snapshot at every event"** — song
   change, play-state change, screen entry, heartbeat — which the bake
   machinery already delivers.
4. New prime suspect for the classic in-car pattern ("works a few minutes,
   then hard-freezes"): the 15 s heartbeat's line-divergence reloads. On CarPlay
   the baked timeline never advances, so divergence fires every beat → a reload
   storm → chronod throttles the widget into the penalty box for the rest of
   the drive. PlayPort's recordings can't show this (the app was suspended
   there); only a real drive with logs can. **Not coded tonight — needs a
   product decision** (cadence, or gating, or accepting the freeze).

## 4. Shipped tonight: build 72 (a5a4263) — Apple Music chained bakes

The one real parity gap the teardown exposed was ours: `startChainFetch` was
Spotify-only. Apple Music now reads its Up Next queue locally
(`AppleMusicSource.nextInQueueWithArtwork()`, `MPMusicPlayerController.queue`)
and feeds the same chained-bake path — the widget timeline now crosses AM song
boundaries with zero network cost. Local gate: 295 passed / 0 failed, parse
sweep clean. CI run 40242123463.

## 5. What only the user can do next (the morning list)

1. **Install 72 when TestFlight offers it, then drive.** The car test is the
   only validator PlayPort can't provide. Watch: (a) the Live Activity tile in
   the dashboard — the primary lyric surface; (b) the widget tiles — how long
   into the drive do they keep refreshing before the suspected budget freeze.
2. If the tiles freeze mid-drive again: collect logs right after the drive
   (`sudo /usr/bin/log collect --device --last 2h`) and the `widgetreload`
   lines will show whether the reload storm theory holds.
3. Decision needed: heartbeat divergence cadence on CarPlay (accept 15 s
   refresh + freeze later, vs. throttle to ~60 s, vs. stop divergence reloads
   while playing).
4. Before any public release: flip `debugStamp` defaults to `false` in
   `SharedWidgetSettings` (both the initializer and the decoder).
