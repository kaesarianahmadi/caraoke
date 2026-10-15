# CarPlay lyric sync: evidence report

Date: 2026-10-15. Investigator: ZCode session.
Question: why do competitor lyric apps stay fluid on CarPlay while Caraoke
freezes roughly once per second and its lyrics never slide?

## 1. The answer, up front

The freeze is not a sync-accuracy problem. Caraoke's lyrics are correctly
timed. The problem is that **the CarPlay surface cannot redraw fast enough**,
because Caraoke pushes *rendered text* to it on a throttled schedule instead
of giving it *timing data* and letting the device draw continuously.

Three facts, each verified in code:

1. **CarPlay mirrors the Live Activity, not the widget.**
   `iOS/LyricsLiveActivity.swift:6-8` — `.supplementalActivityFamilies([.small])`
   "is what makes the same view render as the CarPlay small-family tile
   (iOS 17.2+ mirrors Lock Screen Live Activities onto CarPlay)."
   `iOS/LyricsActivityController.swift:13-14` repeats it for iOS 26.

2. **The Live Activity is throttled to one push per 1.5 seconds.**
   `iOS/LyricsActivityController.swift:20`:
   `static let minLineUpdateInterval: TimeInterval = 1.5`.
   Every line change funnels through `activity.update()` behind that throttle
   (`:86-96`). On top of it sits ActivityKit's own delivery budget.
   A surface that only receives a new string every 1.5 s can only change every
   1.5 s. That is the "freezes every second".

3. **The payload carries no timing, so the view cannot advance itself.**
   `iOS/LyricsActivityAttributes.swift:10-31` — `ContentState` holds
   `currentLine: String`, `previousLines: [String]?`, `nextLine: String?`,
   `upcomingLines: [String]?`, `positionMs: Int?`.
   `iOS/LyricsLiveActivity.swift:59-75` passes those as plain strings into
   `LyricTileView`. A view that is told "the current line is X" has no way to
   know when X stops being current. It must wait for the next push.

## 2. The contradiction inside Caraoke

Caraoke already implements the correct pattern — for the Home Screen widget.

`iOS/CaraokeWidget.swift:103-140` builds a *pre-baked timeline* via
`WidgetTimelineBuilder.entries(for:now:includeOutro:)` and hands WidgetKit many
dated entries at once. `iOS/RidePlaybackController.swift:561-564` states the
rule:

> "the reload is skipped unless something the baked timeline cannot know by
> itself changed: the track, the play state, the lyric status or the artwork.
> Line advance is not one of those — the widget walks the..."

So the Home Screen tile advances lines **with no push at all**. The Live
Activity — and therefore CarPlay — does the opposite: it pushes every line.

## 3. What the competitor evidence shows

Static analysis of a shipped synced-lyrics app (AirLyrics 1.2.6, F-Droid,
SHA256 `6246f00b…`), decompiled with jadx 1.5.6. Not obfuscation-free, but the
architecture is legible:

- `floating/FloatingLyricsService.java:50,140,230` — three `Runnable`s, each
  scheduled with `handler.postDelayed(...)` and cancelled with
  `removeCallbacks(...)` at `:385`. **The lyric advance is self-scheduled per
  line**, not pushed at a fixed rate.
- `defpackage/ag0.java:442` — `handler.postDelayed(biVar, 1000L)`: a 1-second
  poll of the media session, i.e. the app re-reads playback position on a
  clock rather than receiving position pushes.
- `com/andsi/airlyrics/lyrics/providers/` — `LrclibLyricsNative`,
  `MusixmatchLyricsNative`, `NeteaseLyricsNative`. Same lyric-source model
  Caraoke uses (LRCLIB first).

**The transferable principle:** the competitor never pushes rendered text.
The app holds the timed lines and the playback position; the *rendering
surface* draws from time. Their surface is an Android overlay they own, so
they can draw at display rate — which is exactly the freedom CarPlay does not
give you.

## 4. What that means for CarPlay specifically

On Android, an app can own its drawing surface and refresh at frame rate.
On CarPlay, you cannot: the surface belongs to the system and updates are
budgeted. So the competitor's Android technique does not port. What ports is
the *data model*: send timing, not text.

Apple provides the mechanisms that survive the budget:

- **Pre-baked timeline of dated entries** — already used by Caraoke's widget.
- **Native self-updating text** — `Text(timerInterval:)`, `.timer` timeline
  entries. These keep redrawing in the widget's own process with no pushes.
- **Client-side derivation** — ship a bounded window of timed lines plus a
  playback anchor; the view computes the active line from the clock.

Caraoke's CarPlay surface uses none of these three. That is the entire
difference, and it is fixable without any competitor's code.

## 5. Fix outline

> **CORRECTION (same day, after research).** The original outline below rested on
> `TimelineView` redrawing inside a Live Activity. That assumption is wrong and
> this section is superseded by §8. Kept for the record.

Nothing new is needed in the data layer: `Sources/CaraokeCore/LyricLine.swift:6`
already defines `startMs` ("the time the line becomes the current line"), and
`Sources/CaraokeCore/LyricTrack.swift:24-30` already binary-searches a position
to a line index. `WidgetTimelineBuilder` already converts this into dated
entries for the widget.

1. **Widen `ContentState`** to carry a bounded timed window (upcoming lines
   with `startMs`) plus a playback anchor (`positionMs` + capture wall-clock).
   Note the size objection in `LyricsActivityAttributes.swift:4-8` — the window
   must be measured, not assumed free.
2. **Compile `LyricTrack.swift` + `LyricLine.swift` into the widget target.**
   They are not in the extension's source list today; the extension already
   compiles `WidgetShared.swift`, which contains `WidgetTimelineBuilder`.
3. **Derive the active line inside the view** from (anchor, now, `startMs`),
   refreshed on a `TimelineView` schedule.
4. **Reserve pushes for what only the app knows**: track change, play/pause,
   lyric status, seek. Line advance stops being a push trigger.
5. **Verify on a real CarPlay device** — see caveats.

## 6. Caveats — what this report does not establish

- **The load-bearing assumption is untested.** Whether
  `TimelineView(.animation)` inside a Live Activity actually redraws at the
  expected rate on Caraoke's iOS 26 target is *not* verified here. It needs a
  device test. If it does not, the fallback is `Text(timerInterval:)`-style
  native updates plus a wider push interval.
- **No App Store IPA was obtained.** App Store binaries are FairPlay-encrypted;
  they cannot be read statically, so "Dynamic Lyrics" itself was never
  decompiled. The competitor claim rests on the Android sibling's architecture
  plus Apple's documented update budgets — not on reading their iOS binary.
- **REA's Android path is not working on this machine.** REA compiles a Swift
  process-ownership helper via `swiftc` under a 60-second cap
  (`dist/native/NativeUiHelperRuntime.js:24-33`). This machine is currently
  swapping ~7.3 GB of 8 GB; the swiftc compile was killed after ~20 minutes of
  wall time (2:48 CPU). The decompilation above was done with jadx 1.5.6
  directly instead. Fix when memory is free: pre-warm `xcrun swiftc`, then
  `rea inspect-android-package` will work.
- **AirLyrics is a free FOSS app, not a commercial competitor.** It was the
  closest reachable analogue to the problem. Commercial APK mirrors
  (APKPure, APKMirror) return 403 to non-browser clients.
- **Decompiled output is obfuscated.** Method bodies in `defpackage/` are
  partly reconstructed; the scheduling calls above are literal, but the delay
  arithmetic feeding them could not be fully recovered.

## 7. Artifacts left on disk

| Path | Contents |
|:---|:---|
| `rea/targets/` | 3 verified APKs (AirLyrics, FastLyrics, LyricsGrabbr) |
| `rea/jadx-out/airlyrics/` | 1,361 decompiled Java files |
| `~/Tools/jadx/` | jadx-headless-mcp 0.7.1 (REA's Android jar, SHA256 verified) |
| `~/Tools/jadx-cli/` | jadx 1.5.6 CLI (used above) |
| `~/Tools/apktool/` | apktool 3.0.3 jar |
| `~/Tools/ghidra_12.1.4_PUBLIC/` | Ghidra, with macOS x86_64 natives built locally |

The toolchain deliberately lives in `~/Tools/`, outside this repo: it is
machine-level rather than part of the app, and Ghidra alone is ~900 MB. The env
vars (`GHIDRA_INSTALL_DIR`, `REA_JADX_MCP_JAR`, `REA_APKTOOL_COMMAND`) point
there from `~/.zshrc` and the MCP server config. Nothing under `~/Tools/` is
committed to any repository.

---

## 8. Correction and revised approach (post-research)

The §5 outline assumed a Live Activity view can redraw itself from its own
clock. Research contradicts that, and hands back a better mechanism.

### What the sources establish

**A Live Activity is a snapshot, not a live view.** Apple, ActivityKit overview:
"Live Activities use a different mechanism to receive updates compared to
widgets. **Instead of using a timeline mechanism**, Live Activities receive
updated data from your app with ActivityKit and from your server with
ActivityKit push notifications." The view redraws when `Activity.update()`
fires, a push arrives, an App Intent runs, or `staleDate` passes. Between
those, nothing ticks.

**`TimelineView` in a Live Activity is unreliable.** No Apple doc page states
this outright, but the forum repro (Apple Developer Forums 766932, "TimelineView
in LiveActivity Widget", bug FB15590204) shows the closure firing about twice
and then stopping across `.animation`, `.periodic` and `.explicit`. Developer
reports attribute it to the widget extension being suspended ~10 s after start.
Treat as strong anecdote, not gospel — but strong enough to design around.

**Only two primitives are interpolated by the system.** `Text(timerInterval:)`
and `ProgressView(timerInterval:)` are rendered out of process: the OS ticks
them, not your app, and they keep running after the process dies. A WWDC22
WidgetKit Lounge answer from Apple's Graham P confirms secondly updates from a
single timeline entry via `.timer` / `.relative`.

**Animations on content changes are supported, capped at 2 seconds.** Apple,
"Animating data updates in widgets and Live Activities": "Animations in widgets
and Live Activities have a maximum duration of two seconds." Supported
transitions include `opacity`, `move(edge:)`, `slide`, `push(from:)`,
`transition(_:)`, `contentTransition(_:)`, and `numericText(countsDown:)` for
timers. `Transaction` is unavailable. Animations are suppressed under
Always-On / reduced luminance — check `isLuminanceReduced`.

**The push budget is real but unpublishable.** Apple documents that a budget
exists and that exceeding it causes throttling, and that `apns-priority: 5`
updates do not count against it, raising the budget via
`NSSupportsLiveActivitiesFrequentUpdates` (user-toggleable, detect with
`ActivityAuthorizationInfo().frequentPushesEnabled`). Apple never states a
number. Developer reports describe silent drops at ~1/sec. Local
`Activity.update()` has no documented rate limit — only a 4 KB state limit.

**CarPlay adds no redraw cap of its own.** It renders the same snapshot from
the same extension, inheriting `Text(timerInterval:)` interpolation. CarPlay
constraints are UI-level: non-interactive, small family, "only communicate the
most significant states" (WWDC25 session 216).

### What this means for the fix

My §5 plan is dead: giving the tile timing data is useless if the tile cannot
redraw between snapshots. The revised approach, ordered by confidence:

1. **Animate the line change, don't scroll it.** Attach a transition
   (`.push(from: .bottom)` or `.move(edge:)`) to the lyric line and drive it
   with `.animation(_:value:)` keyed on `lineIndex`. Each real push then
   produces a visible slide. This is the only mechanism Apple documents for
   motion in a Live Activity, and `lineIndex` is already in the payload.
2. **Keep push intervals modest.** The budget is undocumented; existing
   behaviour at ~1/1.5 s is plausibly already being throttled, which would
   compound the stutter. Test with and without
   `NSSupportsLiveActivitiesFrequentUpdates`.
3. **Make time-driven content free.** Replace the hand-computed progress bar
   with `ProgressView(timerInterval:)` seeded from the anchor, so the bar keeps
   ticking with zero pushes. Same for any elapsed/remaining readout via
   `Text(timerInterval:)`. This buys back budget for lyric updates.
4. **Do not rely on `TimelineView`.** If a client-side derivation is still
   wanted, it must be re-verified on device first — the evidence says it will
   not work.

### Honest confidence after this research

- Diagnosis (CarPlay renders an update-budgeted snapshot; therefore it can
  never redraw faster than updates arrive): **~90%**, now backed by Apple's own
  wording rather than inference.
- That the fix in this section improves the experience: **~60%**.
- That the original §5 `TimelineView` plan works: **~5%**. Retired.

The remaining uncertainty is what the real budget does at 1 Hz in CarPlay
specifically, which no public source pins down. That is measurable only on the
device.

---

## 9. Instrumentation shipped (build pending)

Implemented 2026-10-15. Seven files, flag-gated, bake untouched.

### The stamp

`CaraokeWidgetEntry.debugStamp` carries a `WidgetDebugStamp` rendered into the
bottom-left corner of every tile — the three CarPlay tiles via
`CaraokeCarPlayChrome` (`CarPlayWidgets.swift:214`) and the Home Screen widget
via `CaraokeWidgetEntryView`.

**Every field is captured at bake time, never inside a view body.** A view body
runs when the system archives the entry, not when it is displayed, so a live
clock there would read as permanently fresh and prove nothing.

Format on the tile: `N/M eHH:mm:ss bHH:mm:ss -<age>s`

| Field | Meaning |
|:--|:--|
| `N/M` | this entry's position in the bake: index+1 of total entries |
| `e` | the entry's own schedule date (what WidgetKit compares to the clock) |
| `b` | when this timeline was built |
| `-Ns` | how stale the playback anchor already was at bake time |

Wall-clock times, not epoch: this line is read by a human off a photograph of
the car screen. The anchor value itself, and sub-second precision, live in the
log line instead — see below.

**The flag travels in the shared keychain settings, not UserDefaults.** The
app and the widget extension cannot share `.standard` without an App Group, and
this project deliberately has none — an earlier build proved it, and
`LyricsActivityAttributes.swift:27-29` records the lesson. So
`SharedWidgetSettings.debugStamp` is the only route, read by the provider
through `SharedWidgetStore.readSettings()`, which it already called.

It is **on by default for test builds** (`debugStamp` defaults to `true`, and
the decoder defaults a missing key to `true`). Before a release build, set both
defaults in `SharedWidgetSettings` back to `false`.

### Reading a frozen tile

| Observation | Conclusion |
|:--|:--|
| `M` is tiny (1–3) | the bake itself is short — payload or anchor problem, not CarPlay |
| `M` large, `N` stuck, `b` unchanged | CarPlay is not swapping entries it already holds |
| `b` changing on each look | reload churn is replacing a good timeline |
| `-Ns` large or climbing | the app handed over a stale anchor — reload landed on an unrefreshed payload |

### The reload and bake logs

All eight `reloadAllTimelines()` call sites now route through
`SharedWidgetStore.requestReload(reason:)`, which logs
`reloadAllTimelines reason=<cause>` to subsystem `com.caraoke.poc`, category
`widgetreload`. Only one place in the codebase calls it, so every reload is
attributable.

Reasons emitted: `ride-mode-stop`, `settings-changed`, `tap-prev`,
`tap-playpause`, `tap-next`, `resync-no-payload`, `resync-pulse`,
`resync-settle`, and the coalesced path's `heartbeat` / `title` / `playstate` /
`status` / `artwork` (joined with `+` when several fire together).

Each bake additionally logs one line to category `widget` with millisecond
precision, which is what lines a bake up against those reload requests:

```
timeline baked entries=<n> covered=<bool> N/M entryMs=… builtMs=… anchorMs=… anchorAgeSec=…
```

Pair both with the provider's existing `getTimeline direct` / `getTimeline
self-fetch` lines and the app's category `ride` (`widget reload scheduled` /
`widget reload executed`).

**All of these log at `notice`, not `info`** (from build 70). Two reasons, both
of which would otherwise empty the log right when it matters: `log show` prints
only default-level events unless `--info` is passed, and info events are
frequently not persisted into a logarchive at all — `log collect` has no flag
to force them in. A collection taken from the phone after a drive could
otherwise contain none of the lines this build exists to produce.

### Collecting the log

`log collect` has **no `--predicate`** — filtering belongs on `log show`. The
`log` name is also a zsh builtin (natural logarithm), so use the absolute path
or the builtin wins:

```bash
sudo /usr/bin/log collect --device --last 10m --output caraoke.logarchive
/usr/bin/log show --predicate 'subsystem == "com.caraoke.poc"' caraoke.logarchive
```

`--device` requires the iPhone plugged into this Mac with Developer Mode on.
In the car the phone is attached to the head unit, not the Mac, so collect
afterwards — and note that only what the system persisted will be there.

**In the car, the photographed stamp is the primary evidence and the log is a
bonus.** The stamp is rendered into the tile and needs no collection at all.
The CarPlay Simulator is where logs can be watched live.

The distinction the logs settle: **"the app stopped asking" and "the reload was
throttled" are identical on the car screen** — a reload line with no matching
bake line means the request left the app and never landed.

Note also that the app already self-heals: `RidePlaybackController.swift:780+`
runs a 15 s heartbeat that forces a reload on bake exhaustion, a static-while-
playing bake, or line divergence. If `heartbeat` reloads keep executing while
the tile stays frozen, the requests are leaving the app and not landing — which
points at CarPlay or the budget rather than at the bake.

### Verification state

`swiftc -parse` clean on all 36 `iOS/*.swift`; core suite **289 passed, 0
failed** (5 new checks). **Type-level correctness is NOT verified** — parse
catches syntax only, per the project's own hard-won note. `ios-app-compile` in
CI is what proves it.

Two type risks found by hand, because parse cannot see either:

1. Adding a field to `CaraokeWidgetEntry` requires every construction site to
   supply it. Both (`CaraokeWidget.swift:74` placeholder, and the from-bake
   call) were updated.
2. Adding a field to the Codable `SharedWidgetSettings` breaks decoding of any
   blob written before that field existed, and `readSettings()` maps a decode
   throw to *defaults* — silently resetting theme and cover style. Fixed with a
   hand-written `init(from:)` using `decodeIfPresent`, now covered by the five
   new suite checks (`settingsKeepsThemeAcrossAddedField` and friends).

