# Caraoke vs Dynamic Lyrics — CarPlay sync comparison (read-only)

Date: 2026-11-01. Inputs: our `CaraokePOC/` sources and the decrypted competitor binaries
(`rea/dynamic-lyrics/INVENTORY.md` for the Mac 2.0.3 build, `INVENTORY-IOS.md` for the iOS 2.0.7
build). **No code was changed.** This document ranks the candidate causes of our CarPlay widget
sync problem and names the evidence for each.

## 0. The surfaces, side by side

| Question | Ours | Theirs |
|:--|:--|:--|
| Live Activity / Lock Screen tile | `LyricsLiveActivity` in `CaraokeWidgets` | `lyricsWidgetExtension` + `LiveActivityHelper` (iOS only) |
| **CarPlay rendering** | (a) `.supplementalActivityFamilies([.small])` mirror on the activity, (b) three `systemSmall` widgets in the CarPlay stack | (a) `ActivityKit` mirror, (b) `CarPlay.framework` linked but **no CP\* API used**, (c) CarPlay widget host |
| Live Activity updates from background | app-local + **relay APNs** (`relay/worker.js`, `push-type: liveactivity`) | `Helper/LiveActivityRefresher` + apns, `pushToStartTokenUpdates` imported |
| Widget tile motion | baked timeline entries, `.atEnd` for `systemSmall` | `LyricScrollSegment.nextRefreshInterval` → per-line `ClockAnimationModifier` |
| Keep-alive | `RideAudioKeeper` (silent wav, `UIBackgroundModes=[audio]`) | `RefreshKeeper`/`RefreshPlayer` — same idea, plus `CXCallObserverDelegate` |
| App↔extension state | shared **Keychain** (no App Group in our profiles) | App Group `group.com.bing.lyrics` |
| Widget extension embedding | **everything** (Live Activity + 4 widgets in one bundle) | **everything** (Live Activity + widgets in one bundle) |

Both architectures match. Four concrete divergences follow.

## 1. Candidate A — the tiles bake one entry and the timeline is spent on arrival

**Corrected on second reading.** The per-line force-reload is *already* gated to the foreground:

```swift
// RidePlaybackController.swift:691
let isLineReloadCandidate = snapshot.currentLine != lastWidgetLine
    && appActive && snapshot.isPlaying        // ← foreground only
```

So the "metered loop competing with the policy path" framing in my first pass was wrong: while
backgrounded (the driving case) no force-reload is sent at all. The actual defect is the **policy**
on the car tiles:

```swift
// CaraokeWidget.swift:212-227 (before this fix)
let looping = context.family == .systemSmall && payload.isPlaying && payload.chainedSpanMs > 0
let built = WidgetTimelineBuilder.entries(for: payload, now: now, limit: looping ? 1 : maxEntries, …)
…
} else if context.family == .systemSmall {
    policy = .atEnd      // ← spent instantly, no wake date
}
```

A one-entry build plus `.atEnd` means chronod reads a timeline that is already spent and carries no
date. Nothing schedules the next wake — which is exactly the 60–90 s starvation in §12, and why the
tile freezes on whatever line that single entry held. The tile's only remaining refresh paths were
the app's force-reload (gone when backgrounded) and the 15 s heartbeat (only while the app is alive).

**Fix applied:** the tile now asks for a wake just before the line on screen stops being the line
that should be on screen (`WidgetTimelineBuilder.nextLineBoundary` → `.after(date)`), keeping
`.atEnd` only when there is no line ahead. One request per lyric line — the cadence the competitor's
tiles demonstrably ride — against the 1 Hz loop's one per second.

Caveat retained from §13: short `.after` dates measured a ~86 s deferral while the force-reload loop
was *also* running (build 75). The loop is gone from the `systemSmall` path now, so the hypothesis is
that the date is honoured — but that is a device-verifiable claim, not a proven one.

## 2. Candidate B — the relay's parity arm: verified working, routing fixed, dark-state made visible

Ours has **two** background mechanisms and they are not the same path:

| Arm | What it does | When it works |
|:--|:--|:--|
| Local (`CaraokeActivityController`) | updates the activity from app-side timers; needs the process alive (`RideAudioKeeper`) | foreground / short backgrounding |
| Relay (`LyricsRelayClient` + `worker.js`) | app POSTs the full lyric schedule + push token **once per ride**; worker holds a Durable Object, fires an **APNs `liveactivity` push per line** | phone locked in the car |

That is *precisely* the competitor pattern (`findings-carplay-lyric-sync.md` §10/§12: "only
server-push LA goes lower"). Verified in this pass with a stubbed Durable Object driving the real
handler:

| Check | Result |
|:--|:--|
| `register` → APNs push | 1 push, `apns-push-type: liveactivity` |
| alarm armed at the first line boundary | **10 000 ms** exactly (10 s line), not the 15 s fallback |
| paused register | frozen push once, **no alarm armed** |
| `end` | session dropped, alarm cleared, later alarm is a no-op |
| `lineAt` / `nextBoundaryAt` | consistent — reads the `t` key the client encodes |

**Two defects found and fixed:**

1. **Cross-device collision.** Every phone resolved the same Durable Object
   (`idFromName("caraoke-ride")`), so a second driver starting a ride overwrote the first one's
   session; the first phone then received pushes computed from another phone's lyrics. Sessions are
   now keyed per device by the activity push token, with a shared fallback for bodies that carry no
   token (and for the `/crashes` operator diagnostics, which stay deployment-wide). `end()` now
   re-sends the token so the teardown routes to the right session. Verified: two tokens → two
   objects, `end` hits its own.
2. **Silent darkness.** `trySend()` returned early whenever the schedule or the push token was
   missing, so a relay that was configured but never armed was indistinguishable from a working one
   — the app just fell back to the local arm and the car showed local behaviour. It now reports
   through `onStatus`, which already surfaces on the HomeView diagnostic line.

Remaining unknown: whether the deployed worker has its APNs secrets and env wired (`APNS_KEY_P8`,
`APNS_KEY_ID`, `APNS_TEAM_ID`). The code path is proven; the deployment is not. **Confirm with
`wrangler tail` during a drive + the `onStatus` line.**

## 3. Candidate C — CarPlay is served by a widget tile, not by the Live Activity

| Their copy (their own UI strings) | Implication |
|:--|:--|
| *"Enable Live Activities to show lyrics on CarPlay"* | the LA is the load-bearing CarPlay surface |
| *"Show lyrics on the Dynamic Island, Lock Screen, CarPlay, and Apple Watch"* | CarPlay is a mirror of the LA, not a separate feature |
| *"You can add widgets to desktop, CarPlay, StandBy, etc."* | a widget host exists, but secondary |

Our build offers **both**, and the profile of the complaint (§11: tile freezes while the LA tile "already
works in the user's car") says the tile path is the one being judged. Ranking: this is not a defect by
itself, but it means every fix aimed at the *widget tile* is fighting a surface the competitor does not
lead with. If the acceptance criterion is "car shows fluid lyrics", Candidate A's fix is not required —
switching the car-facing expectation to the LA (which we already mirror via `.small`) may close it.

Divergences that support this: `.supplementalActivityFamilies([.small])` present on ours (verified
`LyricsLiveActivity.swift:39`); their Mac build has **no** ActivityKit at all and their iOS build has
the LA plus `CarPlay.framework` with no CP\* API — i.e. they never drive CarPlay from a CarPlay app
scene either.

## 4. Candidate D — `staleDate: nil` hid stalls from the system (fixed)

Ours (before this change), in all five paths that create or update the activity:

```swift
await activity.update(ActivityContent(state: content, staleDate: nil))
```

`staleDate: nil` declares "permanently valid", so the system has no reason to fade or refresh the
presented content and no signal that our data stopped flowing. A frozen activity looked live to the
system *and* to the user.

Now every path computes a bounded date: while playing, a generous ceiling (90 s) capped by the track's
remaining time — a content state that outlives its own track is certainly wrong; while paused, 600 s,
so a red-light pause is never faded but a dead app cannot claim freshness forever. The coalesced-update
path derives the same budget from the content state, since it no longer holds the snapshot.

## 5. Candidate E — tile layout can clip the active line

Not a sync cause, but it changes what "frozen" looks like. Ours pins the CarPlay small tile to a
fixed box:

```swift
// LyricTileView.swift:175-177
boxHeight: customBoxHeight ?? LyricSurface.carPlaySmall.blockHeight,
maxBoxHeight: ...,   // "Strict fixed height: never shrinks … never expands"
```

Their CarPlay tile uses a per-line **scroll segment** with `startProgress/endProgress/curve` and a
clock-animation modifier (`ClockAnimationModifier`, bundled `ClockEffect.framework`), i.e. motion
*inside* one rendered entry instead of a fixed multi-row block. A competitor measurement in
`findings-carplay-lyric-sync.md` §13 (4–10 s clean pixel steps) is compatible with either, so this
stays a layout difference, not a proven cause.

## 6. Device-configuration divergences worth noting

| Item | Ours | Theirs |
|:--|:--|:--|
| App Group | **not entitled** — keychain used instead (`SharedWidgetStore` header documents this) | `group.com.bing.lyrics` on both targets |
| Live Activity target | `CaraokeWidgets` extension (correct) | same |
| `UIBackgroundModes` | `[audio]` | `[audio]` |
| `NSSupportsLiveActivities(FrequentUpdates)` | true / true on app **and** extension plists | true / true on app |
| `aps-environment` | `production` on app; **extension carries no aps entitlement** | app only as well |

The app-group absence is a documented, deliberate consequence of our distribution profiles; it is not a
sync cause by itself, but it is the reason the extension reads via keychain (slower, no notification of
change) instead of a shared defaults domain.

## 7. Ranking and status

| # | Candidate | Status | Change made |
|:--|:--|:--|:--|
| A | Car tiles bake one entry with `.atEnd` — spent on arrival, no wake date | **fixed** | `WidgetTimelineBuilder.nextLineBoundary(payload:now:)` → `.systemSmall` policy becomes `.after(wake before the next line rollover)`, `.atEnd` only when no line is ahead. +6 tests |
| B | Relay arm dark / mis-routed | **verified + 2 defects fixed** | per-device Durable Object keyed by activity push token; `end()` routes with the token; `trySend()` no longer fails silently. Verified with a stubbed DO: boundary-exact alarm, paused hold, end teardown |
| D | `staleDate: nil` hid stalls | **fixed** | bounded stale dates on all five activity paths (playing: ≤90 s and never past the track; paused: 600 s) |
| C | Car-facing expectation sits on a widget tile while the LA is the competitor's load-bearing CarPlay surface | **open — design decision, not code** | none; changing which surface the car is graded on is yours to call |
| E | Fixed-height tile vs per-segment scroll motion | **open — layout only** | none; not a sync cause |

Note on A: the fix targets one request per lyric line. If the device shows the `.after` date being
deferred the way build 75 measured (~86 s), A is not sufficient and the fallback is to consider C.
That is the single thing worth measuring next.

No build number was bumped and nothing was pushed — `CaraokePOC/project.yml` still reads
`CURRENT_PROJECT_VERSION: "78"`, which is already the value in the last `main` commit, so a push
without a bump would be rejected by Apple.

## 8. What this comparison does NOT establish

- No function bodies on their side: we have their type/method/property names, provider classes,
  framework layout and defaults keys, not implementations. Claims about *their* internals are
  structure-level only.
- Widget family sets are not recoverable from either binary (WidgetKit builds them at runtime), so we
  cannot prove their CarPlay tile is `systemSmall` from the artefact alone.
- Relay deployment state was not confirmed (root route 404s).
## 9. The answer — found 2026-11-03, and the reason candidates A–E never mattered

Read from two sources, both conclusive: the competitor's **unencrypted intent metadata**
(`rea/dynamic-lyrics/raw/ios/Payload/Dynamic Lyrics.app/{,PlugIns/lyricsWidgetExtension.appex/}Metadata.appintents/extract.actionsdata`,
a plist), and a **30-minute `log collect`** from the user's phone while plugged into CarPlay
(`/tmp/chrono.txt`, 115 231 lines, 13:31:49–14:01:36 + a second capture taking it to 14:01:29).

### What was wrong with everything above

A–E all assumed the reload *request* was the lever — policy dates, entry counts, which surface is
graded, layout. None of them is. The lever is **whether the extension has a recent `SystemIntent`
run on record**, which decides the *tier* chronod admits the request at.

### The proof, side by side, same 30 minutes, same device

| | Theirs | Ours |
|:--|:--|:--|
| `Allowing reload because an intent recently ran for the extension: <ext>` | **1 313 lines** | **0** |
| Reload class | `externalRequest(…)-immediate-free-1` (free tier) | `externalRequestThrottledRetry(...)` |
| Follow-on scheduled by chronod | `Scheduled DAS standard refresh` | `timelineExhausted-…-budgeted-1` |
| Measured wake gaps | **300 gaps × exactly 5 s** | 13:36 → 13:41 → 13:47 → 13:52 (minutes) |
| Grant bursts | every 5 s for the whole window | none |

Our own `ResyncWidgetIntent` **did run** (twice, `13:59:16` and `14:01:06`, `Successfully ran
action`) and the only reload it got was `systemRequest(userTappedFailedWidget)` — never the grant
line. The reason is on the same log line:

```
identifier: ResyncWidgetIntent, mangledTypeName: 14CaraokeWidgets18ResyncWidgetIntentV,
openAppWhenRun: NO, outputFlags: 0, outputType: (null), systemProtocols:
```

**Empty `systemProtocols`.** An intent with no system protocol is a button, nothing more.

### Their protocol declarations (the whole trick, both targets)

```
WidgetRefreshAppIntent → com.apple.link.systemProtocol.AudioStarting    discoverable=false
RefreshAppIntent       → com.apple.link.systemProtocol.SessionStarting  discoverable=false
```

`discoverable=false` on all of them: they are internal, invoked by their own code, not user taps.
Swift mapping (verified against Apple docs this session):

| Their `systemProtocol` | Swift protocol, iOS 26 | Note |
|:--|:--|:--|
| `AudioStarting` | `AudioPlaybackIntent` | `AudioStartingIntent` is the iOS 16 spelling; **deprecated on 26** |
| `SessionStarting` | `LiveActivityIntent` | `LiveActivityStartingIntent` also deprecated |
| `LiveActivityStartingIntent` | `LiveActivityIntent` | (the string the older `bg_36` log showed on their app target) |

### Also corrected here

- **§12/§13's "the tile can't be fluid, only the Live Activity can" was wrong.** Their *widget*
  tiles get granted 40+ times per window, sustained at 5 s, with the extension backgrounded
  throughout. The LA is a separate, already-working surface of ours (41 `immediate-free-2
  payloadChanged` + 69 `containerApp` exempt in the same window).
- **Killing the app stops everything** — after the user swiped Caraoke away, our extension produced
  **0 chronod events for 20 minutes** while their backgrounded extension kept its 5 s cadence.
- The earlier reading of `-1` and `-2` as "free tier" and "the bypass" was inverted in the first
  pass: `-1` is what the intent-granted widget reload rides; `-2` is the `containerApp` activity tier.

### Fix (build 81)

`iOS/WidgetRefreshIntent.swift` — `AudioPlaybackIntent`, `@Parameter nonce: Int` (so successive runs
aren't collapsed into one system cache entry, as all of theirs carry `random: Int`), registered in
**both** targets because the protocol attaches to the extension's AppIntents metadata.
`SharedWidgetStore.requestReload` now runs it immediately before every reload, and
`RidePlaybackController`'s `appActive` gate on per-line reloads is removed — that gate existed only
to keep the *ungranted* path out of the background, which is the driving case this is for.

Not yet verified on device. The check is the same grep: after the next drive, chronod must print
`Allowing reload because an intent recently ran for the extension: app.caraoke.ios.widgets`, and our
follow-on must read `Scheduled DAS standard refresh` rather than `…-budgeted-1`.

### What this comparison still does NOT establish

- No function bodies on their side, ever — the metadata above is declaration-level, and it is enough.
- **Whether their 5 s re-arm is `RefreshAppIntent` re-invoking itself** (a `while` loop inside a
  `SessionStarting` intent, which is what keeps their app process alive) or a chronod-scheduled
  repeat is **not** established. `bg_36`'s intent-cluster times do not line up with the grant times;
  only their activity's ~1/s `Tick second` is explained. Our design runs the intent from
  `requestReload` instead, which is engine-agnostic and needs no long-lived loop.

Build number: `CURRENT_PROJECT_VERSION: "81"`. This is the first push since 80.

