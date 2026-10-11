---
name: caraoke-phone-tester
description: Automated CarPlay audit for Caraoke via PlayPort — drives the Live Activity tile and all widget-stack states over WebSocket, verifies every control action, captures still + 60fps video evidence per surface, measures sync/latency, grades user-supplied iPhone evidence, and writes build<N>-live-audit.md.
---

# Caraoke Phone Tester — CarPlay Audit (iPhone evidence is user-supplied)

**Contract:** when invoked, run this protocol to the end. Drive every CarPlay state, verify every control action produced an observed change, `Read` every artifact, measure latency, grade whatever iPhone evidence the user supplied, then write `build<N>-live-audit.md`. Never exit early, never deliver a chat-only summary, never mark a surface silently skipped — unreachable = `NOT REACHED` with the reason.

**Scope decision (2026-10-11, user):** iPhone-side capture automation is REMOVED (iOS 26 blocks gestures/video; QuickTime pipe too fragile — not worth the time). The user captures the phone themselves and sends screenshots/recordings (chat attachments or files under `App Screenshots/build<N>-audit/user/`). Grade them with the same rubric, labeled `USER-SUPPLIED`. Everything CarPlay is automated.

**This skill is Markdown + native commands only.** Never create/edit `.py`/`.sh` files. All commands verified on this Mac 2026-10-11. If a command fails, re-run it raw and read stderr — do not build scaffolding.

## CarPlay topology & navigation map (exact — user-configured layout)

| Screen | Content | Drive there with |
|:--|:--|:--|
| **Home** (first screen) | **Live Activity tile** `.carPlaySmall` — the CarPlay presentation of the Live Activity (cover, title/artist, lyric rows, progress) | `knob home` |
| **Widget screen** (left slide) | **Two widgets concurrently**: **W1** (left slot) = Cover/Player `CaraokePlayerWidget`; **W2-1** (right slot, default) = **Lyrics-only** `CaraokeLyricsWidget` | `knob left` (swipe left / left arrow) |
| **W2-2 hybrid state** | `CaraokeHybridWidget` in the right slot: lyrics + **progress bar** + transport controls | `knob down` **while on W2-1** (slide down on the lyrics widget) |
| W2-1 again | lyrics-only restored | `knob up` |
| Back to Home | Live Activity tile | `knob home` |
| Now Playing / dock | system now-playing surface (best-effort) | `knob select` on the focused tile |

The three widgets to audit are **W1 (cover/player)**, **W2-1 (lyrics-only)**, **W2-2 (hybrid)**. The Live Activity is the Home tile. Nothing else is in scope for automation.

## Verified capture truths (2026-10-11, this Mac)

- **Stills:** `screencapture -x -o -l<WID>` on the PlayPort Chrome window — occlusion-proof, Space-proof; black frame ⇒ window minimized (recipes deminiaturize first).
- **Video:** `screencapture -v` **ignores `-l`** here — activate Chrome to front first, then region-capture the window's `CGWindowList` bounds (toolbar cropped). Chrome stays frontmost for the whole session (user hard rule — the laptop display belongs to the PlayPort window).
- **Chrome AppleScript is booby-trapped:** never hold `repeat with t in tabs of w` refs across mutations (-1719/-1728/-10006). Bulk-fetch `title of every tab of w` into a list, set `active tab index` by integer. Deminiaturize Chrome via System Events (Chrome rejects `miniaturized` in its own dictionary).
- PlayPort Web UI `http://localhost:8080/?token=caraoke` · control WS `ws://localhost:8080/ws?token=caraoke` · AirPlay `192.168.0.205:7000`.

## Step 0 — Build number & output locations

```bash
grep CURRENT_PROJECT_VERSION CaraokePOC/project.yml   # → N (e.g. "65")
mkdir -p "App Screenshots/build<N>-audit/user"
```

- Artifacts: `App Screenshots/build<N>-audit/` (user drops iPhone evidence in `user/`).
- Deliverable: `build<N>-live-audit.md` at repo root.

## Step 1 — Pre-flight (gates are mandatory)

```bash
# 1. PlayPort receiver: ALWAYS cold-restart. bridge.py start returns early if
#    ANYTHING holds :8080 — a stale daemon silently traps PlayPort in STANDBY
#    ("0 fps / 0.0 Mbps") and never pairs the phone.
python3 .zcode/skills/carplay-bridge/bridge.py stop
python3 .zcode/skills/carplay-bridge/bridge.py start
python3 .zcode/skills/carplay-bridge/bridge.py status
# GATE: proceed ONLY when status prints "iPhone Stream: CONNECTED".
# If "WAITING": ask the user to open Settings > General > CarPlay > select
# "PlayPort" on the iPhone, then re-run status. NEVER capture a standby screen.

# 2. Music must be playing (lyric/sync evidence is meaningless otherwise).
#    Use WS "media play" (Step 3) and confirm the Home tile shows a live track.
```

## Step 2 — Capture recipes

Shell state does not persist — every block is self-contained.

**Recipe C — still (window-ID targeted):**
```bash
osascript -e 'tell application "System Events" to tell process "Google Chrome" to set miniaturized of windows to false
tell application "Google Chrome"
  repeat with w in windows
    set titles to title of every tab of w
    repeat with i from 1 to (count of titles)
      if (item i of titles) contains "PlayPort" then
        set active tab index of w to i
        exit repeat
      end if
    end repeat
  end repeat
end tell'
WID=$(printf '%s' 'import Cocoa
import CoreGraphics
guard let wl = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in wl {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let name = w[kCGWindowName as String] as? String ?? ""
  if owner == "Google Chrome" && name.contains("PlayPort") {
    print(w[kCGWindowNumber as String] as? Int ?? -1); exit(0)
  }
}' | swift -) && echo "CarPlay WID=$WID"
screencapture -x -o -l"$WID" "App Screenshots/build<N>-audit/NAME.png"
```

**Recipe D — 60fps video (activate + region, toolbar cropped).** Run Recipe C's osascript + rect lookup, then record **while sending the WS action** so the transition itself is on tape:

```bash
read -r X Y W H < <(printf '%s' 'import Cocoa
import CoreGraphics
guard let wl = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in wl {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let name = w[kCGWindowName as String] as? String ?? ""
  if owner == "Google Chrome" && name.contains("PlayPort") {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("\(b["X"] as? Int ?? -1) \(b["Y"] as? Int ?? -1) \(b["Width"] as? Int ?? -1) \(b["Height"] as? Int ?? -1)")
    exit(0)
  }
}' | swift -)
osascript -e 'tell application "Google Chrome" to activate'
# arm the WS action at +2s so the transition lands mid-recording:
(sleep 2 && node -e 'const w=new WebSocket("ws://localhost:8080/ws?token=caraoke");w.onopen=()=>{w.send(process.argv[1]);setTimeout(()=>process.exit(0),400)}' 'WS_JSON') &
screencapture -v -V 5 -x -R "$X,$((Y+118)),$W,$((H-118))" "App Screenshots/build<N>-audit/NAME.mov"
```

## Step 3 — Stations (each action doubles as the control verification)

Capture protocol per station: **still of the state → `Read` it → 5s video that includes the WS transition into the next state → `Read` it**. A station's control check PASSES only if the before/after content visibly differs in the expected way.

| # | Artifact | State | WS action during/into it | Checks (be precise) |
|:--|:--|:--|:--|:--|
| 01 | `01_home_live_activity.{png,mov}` | Home — Live Activity tile `.carPlaySmall` | record 5s at steady playback (line advance is the motion); then `media next` triggers come from Step 4 | Lyric row budget **2–3 rows max** (C3); active-line contrast vs neighbor lines; **crossfade collision** outgoing×incoming glyphs (C1, video frames); **skeleton/placeholder bars** (C2, must be absent); title/artist wrap/ellipsis (C4); progress bar present, not frozen |
| 02 | `02_widget_screen_w1_w2-1.{png,mov}` | Widget screen: **W1 + W2-1 concurrently** | send `knob left` 2s into the recording (transition Home → widget screen must appear in the .mov) | **W1:** cover art resolution/aspect, title/artist truncation (C4), transport affordances & glyph states (play vs pause matches playback); **W2-1:** lyric row budget, word wrap quality, active-line contrast, edge clipping (C3); both tiles: no dead zones / no overflow past tile bounds |
| 03 | `03_widget_w2-2_hybrid.{png,mov}` | W2-2 `CaraokeHybridWidget` | send `knob down` 2s into the recording (slide-down W2-1 → W2-2 must appear) | Lyrics region + **progress bar** + transport row coexist without overlap/occlusion; progress advances smoothly in video frames (stepping/jumping = defect); transport glyph state matches playback; lyric highlight cadence vs progress bar (internal sync — feed into Step 4) |
| 04 | `04_widget_w2-1_restore.png` | W2-1 restored | `knob up` | **Control check:** must visibly return to lyrics-only (compare to 02). Same layout checks as W2-1 |
| 05 | `05_now_playing.{png,mov}` (best-effort) | Now Playing / dock | `knob select` on focused tile | Track status, layout. Unreachable → `NOT REACHED` |
| 06 | `06_home_return.png` | Home again | `knob home` | **Control check:** must match 01's layout (live track visible) |

**Control verification scorecard (fill every row):** `knob left` (Home→widget screen) · `knob down` (W2-1→W2-2) · `knob up` (→W2-1) · `knob home` (→Home) · `media playpause` (tile glyph flips — test between stations) · `media next` (track/lyrics change — Step 4). Any action with no observed visual delta = **FAIL** row in the report. Never claim controls work from static frames alone.

## Evidence gate (mandatory after every capture)

`Read` the artifact before continuing; recapture until it shows the expected state.

- **Black frame** → PlayPort window minimized: recipes deminiaturize; confirm they ran.
- **"Your next drive starts here" / `0 fps / 0.0 Mbps`** → standby = no stream: STOP, redo Step 1, re-gate on `CONNECTED`.
- **Wrong window/app in frame** → capture wasn't window-targeted; never accept it.
- **After all stations:** `md5 App Screenshots/build<N>-audit/*` — two identical hashes = one capture counted twice; recapture. (This falsified an entire audit once.)
- WS action with no visual delta → re-send once; still nothing → CONTROL FAIL, do not fake it.

## Step 4 — Sync & latency protocol (improvement-oriented)

Run all three layers; the app's sync needs improving, so measurements must be precise enough to attribute blame.

1. **Transport reaction latency (end-to-end), 3 trials.** Each trial: Recipe D, 8s recording of Home tile; fire `{"type":"media","media":4}` (next) at exactly t=3.000s via the delayed background trigger. Read the .mov frame-by-frame: latency = first frame showing the tile change (cover/lyrics/title) − 3.000s. Resolution ±1 frame ≈ **±17 ms at 60fps**. Report per-trial table + median + max. Alternate `media 5` (prev) on the middle trial to avoid novelty bias.
2. **In-app progression smoothness.** Frame-step `02`/`03` videos: (a) lyric highlight advance cadence — smooth vs hard-stepping (record step interval in ms); (b) row-jump count (layout height changes); (c) on W2-2, divergence between progress-bar position and lyric highlight — both are app-side, so divergence = **sync engine** defect, not wireless.
3. **Attribution & improvement checklist.** `Total reaction = wireless AirPlay link (≈150–300 ms baseline) + app sync engine lag`. Subtract the wireless baseline from the median to estimate app-side lag. Then read the current sync code (`CaraokePOC/iOS/SpotifySource.swift`, `SyncEngine.swift`, `LyricsActivityController.swift`) and report: lead-offset present or absent (build65: absent), metadata relay path, timeline refresh cadence. Output concrete sync-improvement items (with `file:line`) as first-class checklist entries — synchronization is a product priority, not a footnote.

## Step 5 — User-supplied iPhone evidence intake

Collect everything the user sent (chat attachments) or placed in `App Screenshots/build<N>-audit/user/`. Grade with the rubric below (codes L1–L4, W1–W2, I1 apply), each row labeled `USER-SUPPLIED`. If none arrived yet, list the expected rows as `PENDING USER EVIDENCE` — never silently omit. Note each artifact's capture time if visible (clock in frame) for cross-reference with the CarPlay timeline.

## Step 6 — Evaluate & write `build<N>-live-audit.md`

| Code | Defect | Rule |
|:--|:--|:--|
| C1 | Mid-flight text collision (outgoing + incoming glyphs overlap) | clean crossfade, no coordinate overlap |
| C2 | Skeleton/loading placeholder bars on CarPlay | no attention-grabbing animation in driving UI |
| C3 | Row cramming (>2–3 lines) / edge clipping of glyphs | 2-line glance rule, safe insets |
| C4 | Title/artist ellipsis truncation | wrap before truncating |
| L1 | Live Activity extension crash alert (user evidence) | zero crashes, <30 MB WidgetKit budget |
| L2 | Top ascender clip on `.lockBanner` (user evidence) | gradient edge mask |
| L3 | Bottom line collision with card radius (user evidence) | bottom clearance |
| L4 | Row jumping 1↔4 lines (user evidence + CarPlay videos) | stable 2–3 row optical balance |
| W1 | 4x4 column cramp / fragmentation (user evidence) | use full widget width |
| W2 | 2x4 vinyl dead space (user evidence) | vertical centering |
| I1 | Miniplayer occlusion (user evidence) | safe-area clearance |
| X1 | **Control FAIL** — WS action with no observed delta | every advertised control must work |
| S1 | Sync defect: highlight/progress divergence, hard stepping, row jumps | karaoke-grade temporal alignment |

Report structure (all sections, every run):

1. **Executive Summary & Scorecard** — Surface · Defect · Rule · PASS/FAIL/NOT REACHED/PENDING · Severity · Evidence file. Include the control-verification rows (X1) and `USER-SUPPLIED` markers.
2. **CarPlay Defect Analysis (C1–C4, X1, S1)** — Evidence · Observed · Rule · Root cause `file:line` (verify in Swift source) · ACTUAL vs EXPECTED ASCII mockup · Code fix.
3. **Sync & Latency Evaluation** — trial table, smoothness findings, attribution math, sync-improvement checklist.
4. **User-Supplied iPhone Evidence (L1–L4, W1–W2, I1)** — same defect format; `PENDING` rows if no evidence.
5. **Actionable Implementation Checklist** — prioritized `file:line` targets in `CaraokePOC/iOS/`, sync items ranked as product priorities.

Honesty rules: a state seen in a still is "observed rendering", not "interaction-verified". A previous defect not re-observed is `UNVERIFIED`, never "fixed". Nothing cited without a `Read`. No two cited artifacts may share an md5. Control claims require before/after evidence.
