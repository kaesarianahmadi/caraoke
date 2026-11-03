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
## 9. Build 81 failure and system intent continuation (2026-11-03)

Earlier explanations above are hypotheses, not platform guarantees. In particular:
`immediate-free-1` also appears for foreground and user-triggered refreshes; it does not
uniquely identify an intent exemption. Undiscoverable intents can still be button-triggered.
Neither a protocol declaration nor a direct Swift `perform()` call proves system dispatch.

### Build 81 device evidence

`/tmp/caraoke81-fresh.txt`, 14:39:22–14:47:24, explicitly identifies extension/container version 81.
The app kept sending line reloads. chronod logged `Throttling additional refresh request while
foreground.` The lyrics timeline last succeeded at 14:45:08.256, followed by 24 app line-reload
requests without another successful lyrics timeline reload through 14:47:24.189 (136 seconds).
No `WidgetRefreshIntent` system-execution record or Caraoke `intent recently ran` grant appeared.
The empty intent body called directly from `requestReload` did not implement system invocation.

### Recovered invocation, not a new scheduling guess

The decrypted iOS widget executable imports `IntentResult.result(value:opensIntent:)`.
Its `WidgetRefreshAppIntent` continuation at `0x10001bb40` calls the stub `0x100600454`, which
resolves through chained fixups to that exact AppIntents function. The preceding code awaits
`Task.sleep(nanoseconds:)`, checks its current session/random identity, then returns the next
intent. Separately, `/tmp/live_carplay_targets.log:591-596` shows `BackgroundShortcutRunner`
dispatching `RefreshAppIntent` into the app process. These observations establish intent chaining;
they do not promise a particular refresh budget or prove every intent uses the same delay.

Apple documents the contract: [OpensIntent](https://developer.apple.com/documentation/appintents/opensintent).
After an intent returns another intent, the system runs it. This is not equivalent to calling
`perform()` on a Swift value.

### Build 82 and drive re-audit

Build 82 used a five-second sleep and threw `CancellationError` when its shared session
was replaced or stopped. The real-car recording confirms successful background system dispatch,
not just compilation. The sysdiagnose contains two `chronod` crashes: capture times
16:17:11.4585 (PID 115) and 16:19:14.8158 (PID 1189). Both trap in `dispatch_group_leave`
from `LNActionExecutorPassthroughDelegate` with `Unbalanced call to dispatch_group_leave()`.

The first follows a CarPlay resync at 16:17:10 and a `ClientCancelled` error at 16:17:11.339.
The second follows two overlapping resyncs at 16:19:10, a new cycle 0 at 16:19:11.644 while
the old chain was awaiting, and another `ClientCancelled` at 16:19:14.698. This implicates
cancellation/replacement in the executor crash; it does NOT prove all extension `opensIntent`
results are unsupported. There are 149 cycle-start records in the extracted 16:10–16:25 window,
with gaps/restarts, not 145 uninterrupted cycles across the crashes.

Before the first crash, chronod also ignored granted widget requests while a timelineExhausted
task was current and another request queued. Budget exemption was not proof of timely rendering.
The fixed five-second sleep adds up to a polling interval of lyric delay plus dispatch/render time.

### Local correction after the drive

- Invalidated sessions and cancelled sleeps return a successful empty result, without another
  continuation. No `CancellationError` is thrown deliberately into LinkServices.
- Resync remains an extension-side data repair, but no longer rotates the session token or
  launches a second chain. Start Ride / the Live Lyrics control own chain creation; Stop clears it.
- Refresh sleeps until the next lyric boundary, bounded to 0.05–3 seconds; missing/paused payloads
  check again in three seconds. No pre-boundary lead is used for the intent, which would bake
  the previous lyric. Active small-widget sessions request a later 30-second recovery wake,
  not a competing per-line policy wake.
- Spotify already preserved credentials on ordinary network failures. The previous explanation
  claiming `catch { store.clear() }` was false. This correction retains the grant on API 401s and
  generic token-endpoint errors too; only explicit OAuth `invalid_grant` invalidates it.
  The drive does not establish a token wipe as the cause of recovery/re-login.
- Widget resync now timestamps Spotify progress at the request midpoint, after token acquisition,
  instead of stamping the whole operation's start; lyric-fetch time is extrapolated for new tracks.
  Same-title tracks also require an artist match before existing lyrics are reused.
- Shared Keychain read failures now record OSStatus (never token contents). `AfterFirstUnlock`
  items are intended to remain accessible after a normal screen lock; no lock failure was proven.

Local regression checks cover session replacement/stop, boundary timing, and OAuth response
classification. Local macOS execution cannot prove the Apple daemon no longer crashes or that
CarPlay meets the competitor's latency. Those require a new device run with repeated resync,
stop/start, locked-phone playback and multiple track changes. No zero-latency guarantee is made.


## 10. Build 83 regression audit and local three-surface repair

Source: Taildrop `sysdiagnose_2026.11.03_19-46-09+0700_iPhone-OS_iPhone_23F84.tar.gz`.
The extension updates to version 83 at 18:20:59.436. No `refresh intent cycle=` or
`WidgetRefreshIntent.perform()` execution appears after that installation. At 18:41:11.691,
the in-app Toggle emits a SwiftUI `Environment<Optional<AppIntentExecutor>>` access fault;
its start body creates an activity and prepares the next intent, but cycle 0 never follows.
Resync taps now return a plain result, so they cannot repair bootstrap. Older `chronod`
crashes in this archive precede installation; they are not evidence of a new build 83 crash.

The leading source-level regression is the mixed empty/continuation opaque result. iOS 18.2+
has an erased result overload; build 82's unconditional continuation had no empty branch.
This is a diagnosis, not a proven trace of the framework's internal overload selection.
The local repair uses explicit `IntentResultContainer<String, WidgetRefreshIntent, Never, Never>`
for start, refresh and resync. Stop removes the optional follow-on from the SAME result type,
never throws cancellation and never calls `perform()` from a timer. A native macOS AppIntents
executable proved both the continuing and normal-stop result paths. iOS metadata extraction
is unavailable locally, so CI and a device run must validate iOS dispatch.

The in-app control is now an intent Button retaining switch appearance/accessibility, not the
faulting intent Toggle. Resync uses `LiveActivityIntent` for app-process execution and returns
a fresh typed chain. Token presence no longer claims liveness: a matching cycle heartbeat must
be less than ten seconds old. Entry logs precede all session guards. Each app-side cycle ticks
the real playback engine before requesting a widget reload. Boundary checks are capped at one
second; Live Activity line-update coalescing is reduced from 1.5 s to 0.25 s. These remove known
client-side delay, not iOS dispatch, Spotify polling or archive-rendering latency guarantees.
The asynchronous activity-controller initializer that could end a newly created activity was removed.

### Three surfaces only

Binary associated types prove separate Dynamic Lyrics lyric-only and hybrid trees: the hybrid
is a VStack of the lyric viewport followed by artwork/title/artist/playback controls. The Live
Activity uses a masked, offset-based vertical lyric view. Measured horizontal text scrolling also
exists, but neither exact font/inset values nor the current per-surface branch settings are known.
The identified competitor screenshots show centered wrapped lyrics, faded context and a bottom
player strip. They do not establish a universal no-truncation guarantee or original source code.

`CompactLyricsView` is scoped to the Live Activity banner/small mirror, CarPlay Hybrid and lyrics-only
tiles. It measures full wrapped strings at the available width/height, preserves the entire active
line, sheds context before reducing a common font, and never applies a lyric lineLimit. The hybrid
footer uses the remaining measured height rather than a fixed 65% lyric box; metadata wraps.
Other Home Screen/in-app lyric layouts, Dynamic Island regions and Player-tile design remain unchanged.
Visible diagnostic stamp overlays are removed for all widgets; system diagnostic logs remain.

Native macOS SwiftUI snapshots exercised the actual new lyric view at 162x100, 162x162 and 342x138,
including the long Oasis line that truncated in the user's screenshot. A composite checks the
hybrid footer composition too. This is not an iOS simulator or CarPlay visual proof. Exact 100%
competitor binary parity (including private ClockEffect animation) is NOT claimed. Local changes
stay unpushed with project build number 83 until the user explicitly authorizes a release.

The iOS 26.5 AppIntents swiftinterface was also read from the public SDK mirror at
https://github.com/xybp888/iOS-SDKs/tree/master/iPhoneOS26.5.sdk/System/Library/Frameworks/AppIntents.framework .
It confirms both overloads exist and the typed factory is disfavored by inference; `opensIntent`
is deprecated, not unavailable. The explicit result compiles against the local native AppIntents
framework. This does not prove the modern erased overload is itself broken or that the competitor
uses the typed container: its binary reflection reports `IntentResultContainer<String, Never, Never, Never>`.
The actual observed build 83 failure is missing cycle dispatch plus the in-app executor fault.



Verification for the local repair: standalone core suite 316 passed / 0 failed, all 38 iOS files
parsed, app/extension conditional intent branches parsed, native AppIntents smoke exercised
parameter defaults, typed continuation, cycle increment and nil-follow-on stop. Native SwiftUI
snapshots exercised the actual final compact lyric view at all three recorded sizes. The old
debug-default assertion was removed rather than re-pinned; it tested an incidental default,
not user-visible correctness. No Xcode, iOS SDK typecheck, iOS metadata extraction, CI run,
CarPlay render or locked-phone endurance run was performed for these local changes.

