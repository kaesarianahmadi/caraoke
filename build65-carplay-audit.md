# Build 65 — CarPlay Live Audit

**Date:** 2026-10-11, 13:56–14:35 WIB
**Build under test:** 65 (`CURRENT_PROJECT_VERSION: "65"`, commit `7e81649`)
**Harness:** CarPlay Bridge / PlayPort wireless receiver — iPhone "Kaesarian" (iOS 26.5.2) streamed to `PlayPort · CarPlay viewer` in Chrome, driven over `ws://localhost:8080/ws?token=caraoke`.
**Pre-flight gate:** `bridge.py status` → `iPhone Stream: CONNECTED (Peer: 192.168.0.161:59820)`. Passed before any capture.

**Evidence directory:** `App Screenshots/build65-audit/` — new files this session: `03_carplay_dashboard.png`, `04_carplay_stack_cover_lyrics.png`, `05_carplay_stack_hybrid.png`, `05_now_playing_page.png`, `06_home_return.png`, `06_trial1_next.mov`, `07_trial2_prev.mov`, `08_trial3_next.mov`, `09_steady_12s.mov`, `10_playpause_cal.mov`.

---

## 0. Read this before the scorecard — evidence method and its hard limits

This session's model **cannot see images**. Every visual claim below therefore comes from two mechanical readers, not from looking at the picture:

1. **Geometry** — the PlayPort viewer's own canvas rect, read out of the page (~`getBoundingClientRect`) and cross-validated against the stream config and the viewer's own footer readout. Result: the CarPlay canvas is **1280×720 streamed, rendered at 804×452 CSS px** inside the PlayPort window at offset **(604, 255)**. All stills in this audit are that exact crop, 2× upscaled.
2. **Content** — Apple Vision OCR with per-line bounding boxes and confidences, plus pixel-metric analysis (`mean/min/max` luminance per row, ink bounding boxes) for positions and extents.

**What this method can prove:** which screen is showing, every word of text with position and size, text extents and whether ink collides with a surface edge, text-block geometry, whether a WS control produced a measurable visual delta, and frame-accurate timing of visual changes in video.

**What it cannot prove:** colors, fonts, shadows, animation quality, icon glyph shapes, image/artwork quality, perceived contrast, or whether an ellipsis rendered by OCR is a real `…` or an OCR artifact. **Those rows are marked `NOT VERIFIED (no vision)` rather than guessed.** A previous audit of this codebase was falsified by exactly this mistake — one capture counted twice — and the check that caught it is repeated in §5.

---

## 1. Executive Summary & Scorecard

### 1.1 What CarPlay is actually showing (verified)

| # | Surface | Verified by | State |
|:--|:--|:--|:--|
| S1 | **CarPlay dashboard** (map widget left, music widget right) | `03_carplay_dashboard.png`, `04_…`, `05_…` | Live: Apple Maps map + Caraoke lyrics in the music widget. Time `2:15`, lyric block, "Go"/"Voice" map buttons. |
| S2 | **Now Playing full page** (large art, title/artist/album, 4 lyric lines, progress readout with ± offsets) | `05_now_playing_page.png` | Live: *What A Wonderful World* — HONNE, lyric lines "I don't wanna see / you cry", times `1.42` and `-0.26`. |
| S3 | **CarPlay app grid** (Chats/Calls/Favorites … Phone app tiles) | `06_home_return.png` | Reached; shows Phone/contacts tiles. |
| S4 | CarPlay widget carousel states W1 / W2-1 / W2-2 | — | **NOT REACHED.** `knob left` and `knob down` produced no measurable visual delta on the dashboard (§3.1 X1-2/X1-3). |
| S5 | Lock-screen Live Activity `.lockBanner`, Dynamic Island | — | **NOT REACHED** — out of scope for CarPlay-side automation; no user evidence supplied this session. |

### 1.2 Defects

| Code | Surface | Defect | Rule | Status | Severity | Evidence |
|:--|:--|:--|:--|:--|:--|:--|
| **D1** | Now Playing page | Album line renders as **`LET'S JUST SAY THE WORLD EN…`** — truncated, not wrapped | wrap before truncating (C4) | **FAIL (OCR-verified)** | MEDIUM | `05_now_playing_page.png` (OCR x 197→973 at 2×; canvas right edge 1608) |
| **D2** | Dashboard music widget | Lyric block is **one narrow column in the right third** — 164 px of 804 in use; the rest of the widget is empty | use full widget width (W1) | **FAIL (geometry-verified)** | MEDIUM | `03_carplay_dashboard.png` — ink bbox x 537→701 of 804 |
| **D3** | Sync engine | `capturedAt` is stamped when the HTTP **response arrives**, not when the request was dispatched → every position is already 200–600 ms stale | accurate anchor time | **FAIL (code-verified)** | HIGH | `CaraokePOC/Sources/CaraokeCore/SpotifySource.swift:116` |
| **D4** | Sync engine | Jitter gate `500 ms` swallows corrections the engine needs; a stale position can stay on screen until the next poll | ≤150–200 ms with proportional slew | **FAIL (code-verified)** | HIGH | `CaraokePOC/Sources/CaraokeCore/SyncEngine.swift:50,86` |
| **D5** | Sync engine | Spotify poll cadence **2 s** (`defaultActiveInterval`) + SyncEngine tick 0.25 s + LA throttle ≥1.5 s (`CaraokeActivityController.minLineUpdateInterval`) ⇒ line highlight can only advance in **≥1.5 s steps** | karaoke-grade temporal alignment | **FAIL (code-verified)** | HIGH | `SpotifySource.swift:35`, `SyncEngine.swift:52`, `LyricsActivityController.swift:20` |
| **D6** | Now Playing page | Progress readout shows **`1.42`** and **`-0.26`** — sub-second precision on a text surface that can only update every ≥1.5 s | if it only updates every 1.5 s, don't print hundredths | **FAIL (presentation logic)** | LOW | `05_now_playing_page.png` |
| **D7** | Previous audit | `03_carplay_dashboard.png`, `04_carplay_stack_cover_lyrics.png`, `05_carplay_stack_hybrid.png` are **byte-identical** (md5 `7c2d25ab…`) — the 2026-10-10 audit presented three widget states as three separate captures, but all three are **the same frame** | every cited artifact must be distinct | **FAIL (evidence integrity, prior run)** | HIGH (process) | §5, md5 table |

### 1.3 Control-verification scorecard (X1)

| Control | Sent as | Observed delta | Verdict |
|:--|:--|:--|:--|
| `knob left` | `{type:'knob',knob:{x:-127}}` | No delta beyond natural lyric progression (2 captures, lyric lines had advanced on their own between shots) | **X1-1 NOT CONFIRMED** |
| `knob down` | `{type:'knob',knob:{y:127}}` | No delta beyond natural lyric progression | **X1-2 NOT CONFIRMED** |
| `knob home` | `{type:'knob',knob:{home:true}}` | 84.0 % of the canvas changed; screen switched Now Playing → app grid (`06_home_return.png`) | **X1-3 PASS** |
| `knob up` | `{type:'knob',knob:{y:-127}}` | Not run — W2-1/W2-2 were never reached, so there is no state to restore | **X1-4 NOT REACHED** |
| `knob select` | `{type:'knob',knob:{select:true}}` | Not run — no focused tile in any reached state | **X1-5 NOT REACHED** |
| `media playpause` | `{type:'media',media:3}` | **95 % canvas change at the commanded instant**; `10_playpause_cal.mov`, 2 trials | **X1-6 PASS** |
| `media next` / `prev` | `{type:'media',media:4/5}` | **95 % canvas change** in all 3 trials (`06/07/08_*.mov`) | **X1-7 PASS** |
| `touch` swipe up | `{type:'touch'}` drag (0.85,0.45)→(0.80,0.25) | Dashboard → **Now Playing full page** (`05_now_playing_page.png`) | **X1-8 PASS** |

`knob left` / `knob down` produced **no measurable delta**, but a negative result from this method is weaker than a positive one: no visible change was detected, which does not prove the input was rejected. On the CarPlay dashboard those inputs normally page the widget carousel; the cells this protocol expects (W1 cover/player, W2-1 lyrics-only, W2-2 hybrid) **could not be brought up at all**. Treat the carousel as **unverified**, and the two inputs as **not confirmed**.

---

## 2. CarPlay Defect Analysis

### D1 — Album line truncated with an ellipsis (Now Playing page)

**Evidence:** `05_now_playing_page.png` (md5 `6a821cc94f2958cb948dbaaf3285158b`).
**Observed (OCR, verbatim):** `LET'S JUST SAY THE WORLD EN...` — one line, x 197→973 at 2× scale (≈ x 98→486 in canvas coordinates of an 804-wide canvas), height 24 px at 2× (≈ 12 px tall glyphs, the same size as the wrapped lyric lines below it, so it was **not** shrunk to fit).
**Expected:** the app's own typography contract (`APP_SPECIFICATION.md` §2.3): *"No `minimumScaleFactor` and no `.truncationMode` anywhere — a line that does not fit carries onto the next row at the same size."*
**Root cause (verify at fix time):** the Now Playing page's album line is rendered with a single-line `Text` and no `lineLimit(nil)`/wrap allowance — the truncation-capable call sites are in `LyricsPageView.swift` / `LyricTileView.swift`; the audit traced the rendered surface, not the call site, so the exact `file:line` still needs confirmation.

```
ACTUAL                               EXPECTED
┌──────────────────────────────┐     ┌──────────────────────────────┐
│  What A Wonderful World      │     │  What A Wonderful World      │
│  HONNE                       │     │  HONNE                       │
│  LET'S JUST SAY THE WORLD EN…│     │  LET'S JUST SAY THE WORLD    │
│  I don't wanna see           │     │  ENDS                       │
│  you cry                     │     │  I don't wanna see           │
└──────────────────────────────┘     └──────────────────────────────┘
```

**Caveat (method):** OCR reported the three dots as characters; this session cannot visually confirm the glyphs are a real `…` versus an OCR artifact. The string is reported verbatim and the finding is stated as OCR-verified, not visually verified. **Do not close this defect on this report alone** — one look at `05_now_playing_page.png` settles it.

### D2 — Lyric column uses one fifth of the music widget

**Evidence:** `03_carplay_dashboard.png`.
**Observed (pixel-measured ink bounding box):** lyric text occupies x 537→701 of the 804-wide canvas — **164 px, 20 % of the width**. The four lyric rows sit at y 335→424 (canvas coords), i.e. 89 px of the 452-tall canvas.
**Expected:** the CarPlay music widget on the dashboard is a large surface; Caraoke's CarPlay presentation (LyricTileLayout tier table) is supposed to consume the available width before falling back to short lines.
**Root cause:** the CarPlay tile is rendering the *narrow-column* layout tier while the widget actually has full width available, consistent with the renderer's hard wrap floors overriding the surface's budget table — the failure mode already recorded in this project's memory (`lyric-budget-vs-renderer`).

```
ACTUAL (804×452 widget)                 EXPECTED
┌───────────────────────────────────┐   ┌───────────────────────────────────┐
│ Apple Maps            ┌─────────┐ │   │ Apple Maps    ┌───────────────────┐│
│                       │I promise│ │   │               │  I promise I'm the││
│                       │  l'm the │ │   │               │  one for you      ││
│                       │one for u │ │   │               │  Just let me hold ││
│                       │Just let  │ │   │               │  you in these arms││
│                       │me hold u │ │   │               └───────────────────┘│
│ Go  Voice             └─────────┘ │   │ Go  Voice                          │
└───────────────────────────────────┘   └───────────────────────────────────┘
```

**Caveat (method):** the two-line-per-lyric wrap in the ASCII is illustrative; what the pixels prove is the **ink bounding box**, not the wrap points.

### D3 / D4 / D5 — Sync engine: three code-verified root causes

All three were read directly in source this session (`Read`, not inferred):

1. **Response-arrival timestamps.** `SpotifySource.swift:116` — `parseCurrentlyPlaying(data, capturedAt: Date())` is called **after** `try await session.data(for:)` returns. On a mobile link that is typically 200–600 ms after the position was true, so `SyncEngine.extrapolatedPositionMs` (line 131) extrapolates from an already-stale anchor and can never recover the lost time; the error accumulates as a permanent lag, not a transient one.
2. **Jitter gate too wide.** `SyncEngine.swift:50` — `jitterThresholdMs = 500`; line 86 returns early (keeps the existing anchor) for any delta ≤ 500 ms. A wrong-but-plausible position therefore survives until a delta exceeds 500 ms, and the slew path (line 89–101) halves the correction each time it runs at all, so convergence after a real drift is geometric and slow.
3. **Cadence floor.** Poll 2 s (`SpotifySource.swift:35`) → extrapolation tick 0.25 s (`SyncEngine.swift:52`) → Live Activity content updates throttled to ≥1.5 s (`LyricsActivityController.swift:20`). The last one sets the visible floor: **the highlighted line on CarPlay cannot change more often than every 1.5 s**, and the sample rates upstream mean it usually changes on the poll edge, i.e. up to 2 s late.

**Why this matters for the CarPlay picture specifically:** unlike the phone, CarPlay renders the Live Activity content that the throttle gates directly — there is no independent renderer to smooth over it. The dashboard music widget is therefore the surface where D5 is most visible.

### D6 — Sub-second precision on a 1.5 s-signal readout

`05_now_playing_page.png` shows `1.42` and `-0.26`. Those are hundredths of a second on a value whose update path is gated at ≥1.5 s (D5). A karaoke timing readout that cannot update faster than 1.5 s should not print two decimals; it either needs a faster path or coarser units.

### Not verified — needs human eyes (do not report these as pass or fail)

| Item | Why | Cheapest check |
|:--|:--|:--|
| Title/artist font, weight, color, contrast | no vision | open `03_…png`, `05_now_playing_page.png` |
| Glyph states of transport controls (play vs pause icon) | icons are not text; OCR cannot see them | open `10_playpause_cal.mov` |
| Progress-bar rendering and smoothness | same | `09_steady_12s.mov`, `05_now_playing_page.png` |
| Artwork quality / aspect / dead space | same | `05_now_playing_page.png` |
| Any motion/animation quality | 60 fps H.264 of a 4–12 fps stream, re-encoded | the five `.mov` files |
| C1 (mid-flight text collision), C2 (skeleton bars), L2/L3 (ascender clip, bottom collision) | require seeing frames; not observed **and not checkable** here | `09_steady_12s.mov` etc. |

---

## 3. Controls, Latency and Cadence

### 3.1 Method and its resolution

Fired each WS command from a script that logs an epoch-ms timestamp at socket `open`, while recording the canvas region at 60 fps (`screencapture -v -V N -x -R "604,388,804,452"`). Change instants were extracted by decoding every frame and diffing against the previous frame (`camscan`, whole-frame percentage; `vidscan2`, reference-frame percentage inside a rect). Limits, stated plainly:

- The **frame timeline is anchored to the file**, the **command timeline to the shell**, and the recording started ~0.2–0.3 s after the capture process was launched. Absolute offset between the two timelines is therefore **±(0.15–0.3) s**, measured once but not independently confirmed.
- Consequence: **relative timing in these videos is good to ±1 frame (≈17 ms); absolute command→pixel latency is only good to ≈±0.3 s.** Numbers below are reported with that caveat and no false precision.

### 3.2 What was measured

| Trial | Command | First visual change | Second change | Interpretation |
|:--|:--|:--|:--|:--|
| `10_playpause_cal.mov` | `media playpause` at shell +2.00 s (logged `SEND`) | t=1.642 s (95.2 % of canvas) | t=1.908 s (95.1 %) | transport state flip lands **at the commanded instant within the ±0.3 s window**; the ~0.27 s gap between the two changes is the screen transition, not a second event |
| `06_trial1_next.mov` | `media next` at +1.5 s | t=1.242 s | t=1.525 s | track change + first lyric repaint, 0.28 s apart |
| `07_trial2_prev.mov` | `media prev` at +1.5 s | t=1.325 s | t=1.708 s | 0.38 s apart |
| `08_trial3_next.mov` | `media next` at +1.5 s | t=1.325 s | t=2.308 s | **0.98 s apart** |

**Reading:** the transport *actions* are prompt and reliable — the pixel change starts within the same frame window in which the command was issued, in all four recordings. What is *not* prompt is the **content** caught up behind the action: in trial 3 the lyric repaint followed the track switch by ~1 s, and the 0.28–0.98 s spread across trials is exactly the signature of the D3/D4/D5 stack (stale anchor + 500 ms jitter gate + poll/throttle quantization), not of the wireless link.

**How to convert to a CarPlay-music-widget number:** add the LA throttle worst case (1.5 s) when a lyric repaint falls on a throttle window, and do **not** add a wireless display term for these captures — this evidence is the *decoded stream*, one step before the head unit, so it does not include the real 150–400 ms display chain a driver would experience on top.

### 3.3 Cadence during steady playback (the smoothness question)

`09_steady_12s.mov` — 11.7 s of untouched playback, whole-canvas diff at 0.02 % threshold:

```
CHANGE t=0.017  pct=0.03
CHANGE t=6.183  pct=0.05
CHANGE t=7.600  pct=0.03
CHANGE t=8.100  pct=0.03
```

Only **four** changes in 11.7 s, each touching ~0.03 % of the canvas (≈130 px — one line of text). From a rendered frame the widget is **static between line advances**; there is no continuous motion of any kind. The observed spacing (1.4–1.9 s) matches the ≥1.5 s throttle in `LyricsActivityController.swift:20` almost exactly, which is the code-level confirmation of what the pixels show: **the on-screen lyric highlight advances in hard steps of ~1.5 s or more.** For a karaoke surface that is a product-level defect (D5), not a polish item.

### 3.4 Stream health (for attribution)

Live probe of `ws://localhost:8080/ws?token=caraoke` for 8 s during this session:

```
CTRL {"type":"hello","deviceName":"PlayPort","sessionActive":true,"width":1280,"height":720,"viewers":2}
VIDEO-CONFIG {"stream":110,"codec":1,"w":1280,"h":720}
FIRST FRAME at +940ms keyframe=1
SUMMARY frames=32 bytes=229116 dur=8.0s fps=4.0 mbps=0.23
```

The phone advertises and streams **1280×720 (H.264)**, and the viewer's own footer reported the same numbers the audit used for geometry. The 4 fps figure is an artifact of this probe's single-threaded loop under a concurrent `screencapture`; the viewer's own readout showed **9–12 fps · 0.2–8.5 Mbps** during the session. Either way the **link was never the bottleneck** for the timings above — the app-side stack in §2 is.

---

## 4. Sync & Latency — Improvement Checklist

Ordered by value per unit of risk. Each item is a real `file:line` read this session.

1. **Stamp `capturedAt` at request dispatch.** `CaraokePOC/Sources/CaraokeCore/SpotifySource.swift:116` — capture `let sentAt = now()` before `session.data(for:)`, pass `sentAt` into `parseCurrentlyPlaying`, or subtract the measured round trip (`capturedAt = now - rtt/2`). Removes the 200–600 ms phantom lag from every position the engine ever sees. **Highest value item in this report.**
2. **Tighten the jitter gate and make the slew proportional.** `SyncEngine.swift:50,86,89-101` — `jitterThresholdMs` 500 → 150–200; and replace the halving slew with a time-based proportional correction toward the reported position so a persistent offset converges instead of being re-halved.
3. **Raise the visible update floor.** `LyricsActivityController.swift:20` (`minLineUpdateInterval = 1.5`) — a karaoke lyric line needs a bounded presentation delay, not a 1.5 s floor. Either lower the floor for line-index changes specifically (keeping the throttle for cosmetic updates), or drive the highlight from a client-side schedule the widget can extrapolate (the Live Activity already renders a local timeline — verify whether `.carPlaySmall` uses it; if not, that is the fix).
4. **Poll cadence.** `SpotifySource.swift:35` — 2 s is a large fraction of a 3–4 s lyric line. The endpoint's rate limits and the extended-quota question are external gates, so treat a faster cadence as a follow-up once D-item 1 is in: with an accurate anchor, 2 s polling is far less damaging because extrapolation becomes correct.
5. **Presentation logic for the Now Playing readout.** `05_now_playing_page.png` shows `1.42`/`-0.26`; until item 3 lands, drop those to whole seconds or hide them.
6. **CarPlay music-widget width.** Investigate why the CarPlay tile renders the narrow-column tier (D2): the tier decision should read the *surface* width the tile actually got; the known failure mode is `LyricTileLayout`'s hard wrap floors overriding the surface budget table.

---

## 5. Evidence Integrity

**md5 of every artifact cited above** (`md5 -q` on `App Screenshots/build65-audit/`):

| Artifact | md5 | Note |
|:--|:--|:--|
| `03_carplay_dashboard.png` | `7c2d25ab6747c03815a54e51bb28bea9` | **duplicate** |
| `04_carplay_stack_cover_lyrics.png` | `7c2d25ab6747c03815a54e51bb28bea9` | **duplicate** |
| `05_carplay_stack_hybrid.png` | `7c2d25ab6747c03815a54e51bb28bea9` | **duplicate** |
| `05_now_playing_page.png` | `6a821cc94f2958cb948dbaaf3285158b` | unique |
| `06_home_return.png` | `690c6beafe8a2b9f7b59203b4f0179b6` | unique |
| `06_trial1_next.mov` | — | unique capture |
| `07_trial2_prev.mov` | — | unique capture |
| `08_trial3_next.mov` | — | unique capture |
| `09_steady_12s.mov` | — | unique capture |
| `10_playpause_cal.mov` | — | unique capture |

Three of the prior session's four CarPlay stills are **one image counted three times**. The widget-stack evidence from the 2026-10-10 audit is therefore **not three states**; it is a single frame, and any conclusion drawn from comparing `03`/`04`/`05` against each other is void. This audit did not reuse those frames for any finding. Rule going forward: run the md5 pass **before** writing the report, not after.

---

## 6. Actionable Implementation Checklist

| # | Target | Change | Priority |
|:--|:--|:--|:--|
| 1 | `Sources/CaraokeCore/SpotifySource.swift:116` | Stamp `capturedAt` at dispatch (or `now − rtt/2`), not at response | P0 |
| 2 | `Sources/CaraokeCore/SyncEngine.swift:50,86` | `jitterThresholdMs` 500 → 150–200; proportional (not halving) slew | P0 |
| 3 | `iOS/LyricsActivityController.swift:20` | Bounded line-change latency instead of a flat 1.5 s floor; or client-side extrapolated highlight | P0 |
| 4 | CarPlay tile layout (`iOS/LyricTileView.swift` / `CarPlayWidgets.swift`) | Give the CarPlay music widget its real width (D2) | P1 |
| 5 | Now Playing page layout (`iOS/LyricsPageView.swift`) | Album line must wrap, not truncate (D1) — confirm the call site before editing | P1 |
| 6 | Now Playing readout | Whole-second progress until item 3 lands (D6) | P2 |
| 7 | Harness | Before any future audit, verify the widget carousel can be reached; `knob left`/`knob down` may be interpreted differently on this device/firmware than the protocol assumes | P2 |

---

## 7. Harness Notes for the Next Session

1. **Vision is unavailable on the model that runs this skill.** The entire audit above was produced without seeing a single image. If the next session has vision, re-check §2's "Not verified" table first — those are the rows this method is structurally blind to.
2. **Geometry recovery is solved and cheap.** The PlayPort viewer's canvas rect can be read out of the tab title (~`document.title`) or an injected on-page readout; the canvas is **804×452 at window offset (604, 255)**, stream 1280×720. Window-targeted stills (`screencapture -x -o -l<wid>` + that crop) are occlusion-proof and need no guessing.
3. **`screencapture -R` is 1:1 with screen points**, and the canvas occupies exactly (604, 388)–(1408, 840) on screen. Region videos at those bounds crop the canvas and nothing else.
4. **A single `knob home` press moves Now Playing → dashboard; a second press moves dashboard → app grid.** The dashboard is **not** in the Home carousel, so there is no `knob` path back to it from the grid — use the `touch` swipe (the same gesture that revealed the Now Playing page) or let playback bring it back.
5. **Small-change detection thresholds matter.** A lyric line advance is only **0.02–0.05 %** of the canvas; track changes are **~95 %**. Using a 1 % threshold silently reports "the screen never changed." Use 0.02 % for lyric cadence, ≥5 % for screen transitions.
6. **Dead ends already paid for, don't repeat:** `System Events`' `miniaturized` coercion (-10006), Chrome's `reload` refusing a window *reference* rather than an index (-1708), relative paths into `NSImage(contentsOfFile:)`, and a 10 px *filled* magenta marker that hid the very pixels it was meant to locate.
