# Build 65 — Live Dual-Screen Audit: CarPlay Bridge + Phone Tester

**Date:** 2026-10-10, 22:01–22:25 WIB
**Build under test:** 65 (`CURRENT_PROJECT_VERSION: "65"`, commit `7e81649` "Build 64 → 65: live activity, full lyrics page & widget surface overhaul")
**Note:** the last written audit (`build64 phone test.md`, `build-64-phone-test-analysis.md`) predates build 65 — those two documents describe build 64. Build 65's changes (11 files, +279/−89) were committed but **never live-tested until this session.**

**Harness:** CarPlay Bridge (PlayPort wireless AirPlay receiver, Mac :7000 RTSP + :8080 WebCodecs viewer in Chrome) + Caraoke Phone Tester (pymobiledevice3 USB CoreDevice). Real iPhone "Kaesarian", iOS 26.5.2, wireless CarPlay (no cable). Test content: Spotify playback — *Vince Van Gogh* → *Shot My Baby*, both Daniel Caesar.

**Evidence (preserved, not in `/tmp`):**
- New captures: `App Screenshots/build65-audit/dual/` (phone + CarPlay pairs) and `App Screenshots/build65-audit/syncprobe/` (22 timed dual-capture pairs + `timestamps.csv`, epoch-ms wall clock)
- Legacy screenshots kept: `App Screenshots/` (build 60/61 era, 23 files). **The 48 build-64 screenshots referenced by the old reports (`/tmp/build64_screenhots_caraoke/`) are gone** — `/tmp` was cleared. Future audits should write here, as this one did.

---

## 1. Executive Summary — Scorecard

| # | Surface | Defect | Severity | Evidence | Status vs Build 64 |
|:--|:---|:---|:---:|:---|:---|
| D1 | App logic (all surfaces) | Mid-song lyrics wiped → "No lyrics for this track", recovers later | **CRITICAL** | `phone_1006.png` vs `ph_006.png` | NEW (or first observed) |
| D2 | Sync engine | `capturedAt` stamped on network **response arrival** → 400–800 ms phantom lag | **HIGH** | `SpotifySource.swift:116` | PERSISTS (build-64 root cause #1) |
| D3 | Sync engine | `jitterThresholdMs = 500` suppresses corrections the engine needs | **HIGH** | `SyncEngine.swift:50,86` | PERSISTS (build-64 root cause #2) |
| D4 | Sync engine | No 200–300 ms karaoke lead (singers read ahead) | **MEDIUM** | no anticipation code found | PERSISTS |
| D5 | CarPlay tile | Previous line truncated with `…` ("fault? If I lay you d…") | **HIGH** | `cp_006.png` | PERSISTS (spec: wrap, never truncate) |
| D6 | CarPlay tile | Prev line top-clipped, next line bottom-clipped at tile edges | **HIGH** | `cp_006.png`, `cp_013.png` | PERSISTS |
| D7 | In-app Live Lyrics card | Neighbor lines clipped top/bottom inside card | **MEDIUM** | `ph_020.png` | PERSISTS |
| D8 | Home widget (2x4 vinyl) | Hero line truncated `…` after 2 rows ("…(you lost me, oh,…") | **MEDIUM** | `ph_006.png` | PERSISTS |
| D9 | In-app card + widget | Duplicate intro identity: title shown as both header and hero on track change | **MEDIUM** | `ph_013.png` | NEW / regression of build-63 fix |
| D10 | Home widgets (2x4 + 4x4) | Both stuck "Out of date / Tap the cover to resync", lyric area empty, for minutes while music plays | **HIGH** | `phone_lacheck_1/3.png` | NEW surface state |
| D11 | In-app Home | Floating miniplayer occludes "Apple Music" source tile | **HIGH** | `ph_006.png` (and all home shots) | PERSISTS (build-64 I1) |
| D12 | CarPlay tile | Hero wraps to 3 rows filling the whole tile; neighbor rows crushed | **MEDIUM** | `cp_006.png`, `cp_013.png` | PERSISTS |
| D13 | Cross-surface state | Phone UI ("No lyrics") diverged from CarPlay tile (live lines) in the same minute | **MEDIUM** | `phone_1006.png` vs `cp_006.png` | NEW observation |
| D14 | Wireless link | Stream stall captured: `0 fps · 0.0 Mbps`; PlayPort clock drifts erratically | **INFO** | `cp_013.png` | NEW observation |
| D15 | CarPlay tile | "Singin' yes" shown as both previous AND next line | **LOW** | `cp_020.png` | NEW, needs LRC cross-check |

**Verdict:** the app's core flow *is* fully set up and functioning end to end (detection → lyrics → sync → Live Activity → CarPlay → widgets), but build 65 ships **one critical logic bug (D1: mid-song lyric loss)**, **two unfixed sync root causes (D2/D3) that keep lyrics ~1.5 s behind the vocal**, and a persistent layout family (D5–D8, D12) where the renderer violates its own spec ("wrap, never truncate/clip"). The wireless CarPlay link itself is healthy (decode 4–7 ms) and is **not** the reason lyrics look late — see the delay math in §3 before blaming sync.

---

## 2. App Logic & Flow — Is It Set Up?

**Yes.** `APP_SPECIFICATION.md` documents the complete architecture and the implemented code matches it:

```
SpotifySource (poll 2s) ──► NowPlayingCoordinator ──► RidePlaybackController
                                                        │
                              ┌─────────────────────────┼──────────────────────────┐
                              ▼                         ▼                          ▼
                     SyncEngine (250ms tick,      FallbackLyricsProvider    CaraokeActivityController
                     jitter 500 / slew / snap)    (LRCLIB ⇄ YouTube race)   (LA throttle ≥1.5s)
                              │                         │                          │
                              ▼                         ▼                          ▼
                     RideModeViewModel UI         LyricsDiskCache          LyricsLiveActivity
                     (Home card, LyricsPage)      SharedWidgetStore(Keychain)  ├─ .lockBanner
                                                        │                      ├─ .carPlaySmall ◄── CarPlay dashboard
                                                        ▼                      └─ Dynamic Island
                                                  CaraokeWidget timeline
                                                  (2x2 / 2x4 / 4x4)
```

Verified present and wired: `RidePlaybackController` state machine (`iOS/RidePlaybackController.swift`), `SyncEngine` extrapolation (`Sources/CaraokeCore/SyncEngine.swift`), LRCLIB+YouTube race provider, Keychain `SharedWidgetStore`, relay APNs schedule (`LyricsRelayClient`), `RideAudioKeeper` background loop, `TransportControl` + AppIntents, CarPlay widget stack (`CarPlayWidgets.swift`), Live Activity supplemental family. The CarPlay dashboard tile rendered live lyrics through the whole session, the phone UI tracked playback, and Spotify source badges behaved — the pipeline works.

**Functions that do NOT follow the documented logic:**

| Spec says | Code does | Where |
|:---|:---|:---|
| LRCLIB: "fallback to stale cache on network failure" | `try? await provider.lyrics(...)` collapses **network errors** into `.noLyrics`; no stale-cache fallback on this path | `iOS/RidePlaybackController.swift:310-317` |
| SyncEngine: "millisecond-level position extrapolation" | `capturedAt: Date()` stamped when the HTTP **response arrives**, so `progress_ms` is already 400–800 ms old on mobile networks | `Sources/CaraokeCore/SpotifySource.swift:116` |
| "No `minimumScaleFactor` and no `.truncationMode` anywhere — a line that does not fit carries onto the next row" | Neighbor/hero lines truncate with `…` and clip at surface edges | `LyricTileView.swift` rendering on `.carPlaySmall`, `.widgetMedium`, `.home` |
| carPlaySmall intro rule: title row until first line, then removed; hero vertically centered | Hero line occupies 3 rows and pushes prev/next into clipped edges | `cp_006`, `cp_013` |
| Widget resync: "an overlay refresh icon appears" on the cover | Whole lyric area replaced by "Out of date / Tap the cover to resync" slate | `phone_lacheck_1.png` |
| Build 63: "eliminate duplicate intro headers" | Title rendered as both header and hero on track change | `ph_013.png` |

---

## 3. Synchronization Math — Including the Wireless CarPlay Delay

This is the section to use whenever judging "is the lyric late?" — **do not compare CarPlay pixels to audio directly.**

### 3.1 Measured / sourced delay components

| Component | Value | Source |
|:---|:---:|:---|
| PlayPort WebCodecs decode | **4–7 ms** | viewer footer readout, sampled across `cp_006/013/020` |
| CarPlay frame quantization | **45–55 ms** | stream ran 18–22 fps (`cp_*` footers) |
| Wireless link (encode + Wi-Fi + receive buffer) | **~100–300 ms** (estimate) | Not instrumented: PlayPort client JS (`index-fJ5j8hYQ.js`) exposes only fps/Mbps/dropped/queue/decode — no RTT or end-to-end metric. Typical wireless CarPlay range; one captured stall (`0 fps · 0.0 Mbps` at `cp_013`) confirms the link is variable. |
| **Wireless CarPlay display chain subtotal** | **≈ 150–400 ms** | sum of the three rows above |
| ActivityKit LA update throttle | **≤ 1.5 s** between line pushes | `ActivityUpdatePolicy` — by design (instant for skip/pause) |
| Spotify poll cadence | 2 s active | `SpotifySource.swift` |
| `capturedAt` response-stamp error | +400–800 ms phantom position lag | `SpotifySource.swift:116` (D2) |
| SyncEngine jitter suppression | ≤ 500 ms drift left uncorrected | `SyncEngine.swift:86` (D3) |
| App-side visual lag vs audio (device) | **~1.45 s** | build-64 calibration (RMS vocal onset vs frame transition, minus 150 ms QuickTime mirror); code paths unchanged in 65, still representative |
| Karaoke lead (anticipation) | 0 ms (should be 200–300 ms lead) | not implemented (D4) |

### 3.2 The delay budget — what the driver actually sees

```
Perceived CarPlay lag vs vocal audio
  = app-side lag (~1.45 s: D2 + D3 + poll)
  + LA throttle worst case (≤1.5 s at a line boundary; ~0 s when update lands)
  + wireless display chain (≈0.15–0.4 s)
  + frame quantization (≈0.05 s)
  − karaoke lead (0 s — none)
  ≈ 1.9–2.3 s typical,  ~3.3 s worst case
```

**Compensation rule for future sync audits:**
1. When a CarPlay line transition looks late, first subtract **≈0.2–0.45 s** (wireless display chain) — that is physics, not the app.
2. Then subtract up to **1.5 s** if the transition fell on an LA throttle window.
3. Only an error **> ~1.6 s after both subtractions** (i.e. visible on the phone UI too) is an app sync-engine bug.
4. Phone-side measurements need **no** wireless compensation — only the D2/D3 terms (~1.45 s).
5. Any fix for D2/D3 removes ~1.2–1.5 s from **both** budgets at once — highest-value sync work.

### 3.3 Cross-screen consistency check (probe, 22:09:46–22:12:56)

Same-window pairs (`timestamps.csv`, 22 timed captures) show both screens tracking the same track within the capture skew (phone USB capture is slow, ~6–7 s per shot, so pairs are 7–8 s apart — fine for content, too coarse for ms timing):
- `cp_020` @22:12:26 hero "I shot my baby down that day" → `ph_020` @22:12:33 hero "(Shot down, shot down, my baby, I shot down)" — sequential lines, consistent with near-realtime on both.
- No evidence of multi-second CarPlay-side divergence; the wireless link is not the problem (see §3.1).

---

## 4. Surface-by-Surface Defect Detail

### 4.1 CarPlay Dashboard — Live Activity tile (`.carPlaySmall`)

**D5 — Previous line truncated with ellipsis.** `cp_006.png` (22:10:30): prev line renders "fault? If I lay you d…". Spec (`APP_SPECIFICATION.md` §2.3): "No `minimumScaleFactor` and no `.truncationMode` anywhere — a line that does not fit carries onto the next row at the same size." Fix: remove the row cap on the neighbor line (`lineLimit`) and wrap to 2 rows at the same size, or center-crop the neighbor line without ellipsis.

**D6 — Edge clipping.** `cp_006.png`: next line "Started for better" cut by the tile's bottom edge; `cp_013.png` (22:11:28): previous line clipped at the top edge (visible half-descenders). Build-64 rules "smooth linear gradient edge mask" + "14pt bottom clearance" still violated. Fix: enforce `LyricTileLayout` vertical budget before render (hero 3-row worst case = 81 pt of the 119 pt block leaves ~19 pt/row for neighbors — either reserve fixed neighbor slots or drop neighbors when hero ≥ 3 rows).

**D12 — Hero 3-row dominance.** `cp_006`, `cp_013`: parenthetical-heavy lines ("How 'bout if I lay you down? (My fault, if I lay you down, just)") wrap to 3 rows and consume the tile, producing D5/D6. Consider stripping parenthetical asides on carPlay surfaces or allocating 2 rows hero / 1 row each neighbor.

**D14 — Wireless link stats (for the record):** 1280×720, 18–22 fps, 0.9–1.2 Mbps, decode 4–7 ms; one stall sample `0 fps · 0.0 Mbps` (`cp_013`). PlayPort's virtual head-unit clock lags erratically (displayed 10:06 at 22:10:30, 10:10 at 22:11:28, 10:12 at 22:12:26) — **never use it as a timing reference**; use capture timestamps.

**D15 —** `cp_020.png` (22:12:26): "Singin' yes" appears as both previous and next line around hero "I shot my baby down that day". If the LRC repeats the line, fine; if not, the snapshot builder duplicates lines. Cross-check `Shot My Baby` LRC before treating as bug.

### 4.2 Phone — In-app Home (Live Lyrics card + widget preview + miniplayer)

**D1 — CRITICAL: mid-song lyric loss + recovery.** Sequence on the same track (*Vince Van Gogh*):
- 22:02 (`phone_retry_1.png`): card shows hero "They won't Van Gogh me" — lyrics live.
- 22:07 (`phone_1006.png`): card shows **"No lyrics for this track / We couldn't find synced lyrics for this song" + "Try Again"**; the CarPlay tile 30 s earlier (`cp` capture 22:06:42) was still rendering live lines for the same song.
- 22:10:33 (`ph_006.png`): lyrics BACK ("Wanna see me broke and dumby…") — same track.

Root cause sites:
1. `iOS/RidePlaybackController.swift:310-317`: `guard let track = try? await self.provider.lyrics(for: signature) else { … self.lyricState = .noLyrics }` — `try?` turns **transient network/provider errors** into "no lyrics", with no `.stale` and no disk-cache fallback (spec §6 explicitly promises stale-cache fallback for LRCLIB).
2. Track-key flap: `isNewTrack` (title/artist/album/duration-bucket key) can flip on a noisy Spotify poll (2 s cadence) — that path wipes all lines (`engine.setLyrics([])`, `lyricState = .loading`) before refetching; a failed refetch then lands in case 1.

Fix: (a) make the fetch return a typed result — `nil` only for a genuine no-lyrics answer, errors go to `.stale` + cached track replay; (b) only treat a key change as a new track when the title/artist pair actually changes, or after the key persists across 2 polls.

**D13 — cross-surface divergence during D1:** phone UI = "No lyrics" while the CarPlay LA tile kept rendering lines (relay-fed schedule vs local UI state). After fixing D1, also route the LA from the single `lyricState` source so surfaces can't disagree.

**D9 — duplicate intro identity.** `ph_013.png` (22:11:34, track change → *Shot My Baby*): the card hero slot shows "Shot My Baby — Daniel Caesar" AND the widget preview shows the same string as both its header and its hero, while a real lyric line ("Starin' out my window") is already available as "next". Build 63 claimed "eliminate duplicate intro headers" — the `.home` surface still does it. Fix: in intro state render hero = title, next = first line (no header repeat); the vinyl widget header should hide during intro.

**D7 — neighbor clipping in the card.** `ph_020.png` (22:12:33): prev "That nigga too, he stole my place, my place" clipped at card top, next "Stepped inside the room, I still have dreams about it" half-cut at card bottom (renders through the card edge mask mid-word).

**D11 — miniplayer occlusion (build-64 I1, unfixed).** In every home capture the floating miniplayer covers the "Apple Music" source tile's title/status. Needs bottom safe-area padding on the scroll content ≥ miniplayer height + 44 pt touch margin.

**D8 — widget-preview hero truncation.** `ph_006.png` preview: "Wanna see me broke and dumby (you lost me, oh,…" — 2 rows then ellipsis. Violates the wrap-only typography contract for `.widgetMedium`.

### 4.3 Phone — Home Screen Widgets (2x2/2x4/4x4)

**D10 — widgets dead-stale while music plays.** `phone_lacheck_1.png` (22:21) and `phone_lacheck_3.png` (22:24): both the 4x4 and the 2x4 widgets show **"Out of date / Tap the cover to resync"** and an empty lyric area, minutes into active playback, while the app itself had live lyrics. Notes:
- This is the known WidgetKit boundary (widgets can't be pushed/polled; timeline precompute + `WidgetResyncIntent` is the designed mitigation) — but the *user-visible outcome* is a dead widget on the Home Screen, and the resync overlay only helps after a manual tap.
- Layout deviation: spec says "an overlay refresh icon appears" (on the cover); the implementation replaces the entire lyric area with a slate, and the 2x4 shows no lyrics at all in this state.
- Mitigation directions (pick in product order): (a) keep rendering the last-known lyrics under a small "stale" badge instead of the full slate; (b) precompute the timeline for the *chained* next track too (the `startChainFetch` path exists — verify it lands in `WidgetTimelineBuilder`); (c) accept and communicate the limitation (the in-app Widget settings guide already hints at it).

### 4.4 Surfaces not captured this session

- **Lock Screen Live Activity (`.lockBanner`) and Dynamic Island:** not captured — the tester's edge-drag (`universal-hid-service drag`) failed repeatedly ("Drag failed"), so Notification Center/lock screen could not be reached programmatically. Build-64 issues for this surface (ascender clipping, bottom border collision, row jumping) therefore **carry over unverified** into build 65. Recommend one manual pass or fixing the HID drag coordinates (service rejects y-origin 0–30).
- **Full-screen LyricsPageView:** not reached (time budget) — build-64 scrub-collision issues carry over unverified.

---

## 5. Build 64 → 65 Regression Matrix

| Build-64 defect | Build-65 status |
|:---|:---|
| C1 mid-flight text collision (CarPlay) | Not re-observed (no transition collision captured in 22 frames); code transition path unchanged — **treat as open** |
| C2 skeleton bars on dashboard | Not observed during this session (no `.loading` window captured) — unverified |
| C4 title ellipsis (full app) | Unverified (full app not opened) |
| LA extension crash | **Not reproduced** — LA rendered continuously ~20 min incl. track change |
| LA ascender clipping / bottom border / row jumping | Unverified (lock banner not reachable, §4.4) |
| Home 4x4 over-wrapping / 2x4 dead space | Superseded by D10 (widgets went stale before layout could be judged in motion) |
| I1 miniplayer occlusion | **PERSISTS** (D11) |
| Sync lag root causes (capturedAt + jitter) | **PERSISTS** (D2/D3 — code confirmed unchanged) |

Build 65's own changes (`7e81649`, 11 files: `LyricsLiveActivity`, `LyricsPageView`, `LyricTileView`, widget surfaces) were exercised live for the first time here; the `.carPlaySmall` tile and `.home` card are clearly working, with the layout defects catalogued above.

---

## 6. What Works (verified live)

1. End-to-end pipeline: Spotify poll → lyric race (LRCLIB/YouTube) → SyncEngine → Live Activity → **wireless CarPlay tile rendering real lines in real time** (~20 min continuous, incl. one track change).
2. Track change handling: *Vince Van Gogh* → *Shot My Baby* propagated to card, widget preview, miniplayer, and CarPlay tile within seconds.
3. PlayPause state shared correctly across miniplayer + widget transport (pause glyph on both at 22:12).
4. Spotify as active source (badge + check), Apple Music tile present.
5. Wireless AirPlay link quality is fundamentally healthy: decode 4–7 ms, 18–22 fps, ~1 Mbps, single-digit dropped frames.
6. Bridge + tester harness now reliable for future audits (see §7).

---

## 7. Harness Notes (for next sessions)

1. **`tester.py audit` CarPlay capture is unsafe:** `screencapture -R` grabs whatever is on screen in that region — it captured the ZCode window instead of Chrome. Fixed out-of-tree: `tools/carplay_shot.sh` (activates the PlayPort tab first, uses exact window bounds, crops the 118 px toolbar). Reuse it.
2. **`bridge.py start`'s browser open is unreliable** — the PlayPort URL did not land in Chrome (default-browser handler). Open `http://localhost:8080/?token=caraoke` explicitly and select the tab.
3. **Phone USB capture takes ~6–7 s**, not <1 s as advertised — paired captures are therefore 7–8 s apart. For ms-grade timing use content transitions + `timestamps.csv`, not pair deltas. `tools/sync_probe.sh` logs epoch-ms per frame.
4. **Edge drags fail** via `universal-hid-service` (Notification Center unreachable) — blocks lock-banner QA until fixed.
5. Screenshots from this and future sessions live under `App Screenshots/` (the build-64 `/tmp` set was lost to cleanup).

---

## 8. Prioritized Fix List

1. **D1** — stop losing lyrics mid-song: typed fetch result (error → `.stale` + cache), `nil` only for true no-lyrics; debounce track-key changes across 2 polls. *(CRITICAL — the product's one job)*
2. **D2 + D3 + D4** — one sync pass: stamp `capturedAt` at request dispatch (or extrapolate by RTT/2), lower `jitterThresholdMs` to ~150–200 ms with proportional slew, add a 200–300 ms presentation lead. Removes ~1.2–1.5 s of the ~1.9 s perceived CarPlay lag.
3. **D5/D6/D7/D12** — enforce the LyricTileLayout vertical budget on all surfaces: wrap (never ellipsis), reserve neighbor slots, gradient edge masks top+bottom. *(CarPlay HIG glanceability)*
4. **D10** — widgets: keep last-known lyrics under a small stale badge instead of the full-slate wipe; extend chained-track timeline precompute.
5. **D11** — scroll-content bottom inset ≥ miniplayer height.
6. **D9** — intro-state rendering: one identity line only (hide vinyl-widget header during intro).
7. **D15** — cross-check *Shot My Baby* LRC for the duplicated "Singin' yes" line.

*Delay-compensation numbers in §3.1–3.2 must accompany any future "lyrics are X ms off" measurement — wireless CarPlay display costs ≈ 150–400 ms before the sync engine gets any blame.*
