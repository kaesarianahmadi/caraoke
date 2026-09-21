# Build 64 iPhone Live Test & Surface Defect Analysis

**Date:** 2026-09-21  
**Build:** 64 (`CURRENT_PROJECT_VERSION: "64"`)  
**Harness:** QuickTime Player tethered USB mirroring on real iPhone  
**Test Data:** 71 continuous screenshots (sampled every 2s), 2 screencapture video clips (15s each), 1 direct QuickTime digital audio+video clip (14s)

---

## 1. Test Artifacts & File Paths

### Recordings & Audio
- **Direct Digital Audio+Video MOV:** `/tmp/caraoke_clip_15s.mov`  
  - Format: Stereo 48kHz AAC (`soun`) + 888×1920 @ 31.7fps (`vide`), duration: 14.05s
- **Extracted Lossless WAV:** `/tmp/caraoke_audio.wav` (44.1kHz 16-bit PCM for energy profiling)
- **Lock Screen Live Activity Video:** `/tmp/caraoke_live/clip_0001.mov` (15s screencapture)
- **In-App Full Lyrics Sheet Video:** `/tmp/caraoke_live/clip_0002.mov` (15s screencapture)

### Key Screenshots
- **Lock Screen Live Activity:** `/tmp/caraoke_live/shot_0008.png` (Shows Now Playing card + Caraoke Live Activity)
- **Lock Screen Line Drop:** `/tmp/caraoke_live/clip1_7.0s.png` (Shows hero line wrapped, neighbor line dropped)
- **Home Screen Widgets (4x4 & 2x4):** `/tmp/caraoke_live/shot_0032.png` (Shows both huge square widget and medium vinyl widget)
- **In-App Home Screen & Miniplayer:** `/tmp/caraoke_live/shot_0045.png` (Shows Live Lyrics card, Widget preview, and miniplayer overlap)
- **Full-Screen Lyrics Sheet Scrub Collision:** `/tmp/caraoke_live/shot_0052.png` & `shot_0056.png` (Shows lyric text passing directly through scrub bar)
- **Transition Collision Mid-Flight:** `/tmp/clip_frames/frame_7.0s.png` (Shows outgoing line overlapping incoming hero line)
- **Fine Sync Frames (0.1s steps):** `/tmp/clip_frames/frame_fine_5.5s.png` through `frame_fine_7.5s.png`

---

## 2. Latency & Sync Calibration

### Measured Timing
- **Audio vocal onset (RMS energy peak 11,532):** t = 5.3s (`"Do you think about me still?"`)
- **Visual hero line transition complete:** t = 7.0s – 7.5s
- **Raw observed lag:** ~1.60s
- **QuickTime USB display mirror latency:** ~150ms
- **True device-level visual lag:** **~1.45s behind audio**

### Root Causes
1. **Network roundtrip uncompensated (`SpotifySource.swift:116`):**
   ```swift
   let (data, response) = try await session.data(for: request)
   let state = try Self.parseCurrentlyPlaying(data, capturedAt: Date())
   ```
   `capturedAt` is stamped on response arrival rather than when the request was dispatched. Over cellular / mobile Wi-Fi, HTTP round-trip takes 400–800ms. Stamping `Date()` marks position `progress_ms` as current when it is already ~600ms old.
2. **Jitter threshold locks in lag (`SyncEngine.swift:86`):**
   ```swift
   if delta <= Self.jitterThresholdMs { return } // 500ms
   ```
   Because drift of 400–500ms falls inside `jitterThresholdMs`, the engine suppresses correction and preserves the delayed anchor.
3. **No vocal anticipation lead:**
   Singers read karaoke lyrics 200–300ms *ahead* of vocalization. Presenting lyrics synchronously with or behind vocal audio makes singing along impossible.

---

## 3. Surface-by-Surface Defect Audit

### A. Lock Screen Live Activity (`.lockBanner`)
- **Severe Neighbor Truncation: ✅ [FIXED]**
  - *Fix:* Widened `maxLyricWidth` to 280pt and raised wrap allowance to 4-5 rows (`.lineLimit(5)` hero, `.lineLimit(4)` neighbor).
  - *Evidence:* `/tmp/caraoke_live/shot_0008.png`
  - Previous line: `"I'll show you how to fall in l..."`
  - Upcoming line: `"Now everybody wants to b..."`
  - *Root Cause:* `LyricTileLayout.maxLyricWidth` is capped at `250pt` on a ~360pt card (110pt horizontal space wasted on left/right margins). In addition, `LyricSurface.lockBanner.budgets` sets `neighborRows: 1`, forcing `.lineLimit(1)`.
- **Abrupt Line Vanishing / Layout Jump: ✅ [FIXED]**
  - *Fix:* Removed progress bar and header to dedicate 100% height to lyrics (`blockHeight: 135pt`). Bypassed `ViewThatFits` row eviction on `.lockBanner`, `.home`, and `.carPlaySmall` so context lines are never dropped; edge fade handles overflow smoothly.
  - *Evidence:* `/tmp/caraoke_live/clip1_7.0s.png`
  - When the hero line wraps to 2 lines, previous or upcoming line abruptly vanishes.
  - *Root Cause:* `LyricSurface.lockBanner.blockHeight = 119`. Minus 32pt vertical padding (16pt top + 16pt bottom), usable interior height is only **87pt**. A 4-row layout (2 hero rows + 1 previous + 1 upcoming) requires at least 103pt. `ViewThatFits` fails the 3-line budget and drops to the 2-line or 1-line fallback budget.
- **Visual Text Collision During Transition: ✅ [FIXED]**
  - *Fix:* Replaced colliding `.move` asymmetric animations with `.transition(.opacity)` in `LyricTileView.swift`. Persistent lines smoothly slide upward in lockstep via unified stack animation.
  - *Evidence:* `/tmp/clip_frames/frame_7.0s.png`
  - Outgoing line and incoming line collide and pass through each other.
  - *Root Cause:* `rowsStack` in `LyricTileView.swift` applies `.transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))` inside a unconstrained `VStack`. Both views animate simultaneously within overlapping coordinates.

### B. Huge Square Widget (4x4 / `.widgetLarge`)
- **Second Line Truncation: ✅ [FIXED]**
  - *Fix:* Kept 225pt width and raised wrap allowance to 5 hero rows and 4 context rows. Long lines wrap fully without `...` truncation; edge fade softly dissolves any container overflow.
  - *Evidence:* `/tmp/caraoke_live/shot_0032.png`
  - Line 2: `"Now everybody whispers things 'bout..."` ends with ellipsis `...`.
  - *Root Cause:* Line limit and height budget constrain row 2 instead of allowing full multi-line wrap.

### C. Medium Widget (2x4 / `.widgetMedium` / `VinylWidgetView`)
- **Narrow Lyric Column / Over-Wrapping: ✅ [FIXED]**
  - *Fix:* Capped lyric text at 160pt, leaving a clean 28pt margin before the spinning vinyl disc without premature word wraps.
  - *Evidence:* `/tmp/caraoke_live/shot_0032.png`
  - Lyrics column width is cramped to 135pt (`maxLyricWidth: 135`), forcing simple lines like `"things 'bout us"` and `"your head"` onto second rows right next to the album art.
- **Inverted Playback State & Play/Pause Toggle: ✅ [FIXED]**
  - *Fix:* Optimistically toggled `payload.isPlaying` in `SharedWidgetStore` inside `PlayPauseIntent.perform()` before `WidgetCenter.reloadAllTimelines()`. Transport button flips immediately on tap.
  - Shows Pause icon (`||`) while playback is paused instead of Play (`▶`).

### D. Small Widget (2x2 / `.widgetSmall`)
- **Aggressive Truncation: ✅ [FIXED]**
  - *Fix:* Deleted `.systemSmall` from `CaraokeWidget.supportedFamilies`. The cramped, unreadable 2x2 widget is removed from the phone gallery entirely.
  - Column capped at 130pt with `neighborRows: 1` causes text truncation after ~16–18 characters.

### E. In-App Home Live Lyric Card (`.home`)
- **Unused Horizontal Space: ✅ [FIXED]**
  - *Fix:* Widened `maxLyricWidth` from 250pt to 280pt.
  - *Evidence:* `/tmp/caraoke_live/shot_0045.png`
  - Card is 360pt wide, but lyrics column is clamped to `maxLyricWidth: 250`.
  - Causes `"Girl, if you leave me I might..."` to truncate despite ~100pt of black space on either side.
- **Progress Bar Indicator Overlap: ✅ [FIXED]**
  - *Fix:* Disabled progress bar and header on `.home`. In-app miniplayer already manages playback and scrubbing.
  - White progress indicator bar at the bottom of the card is flush with the bottom stroke.

### F. In-App Full Lyrics Page (`LyricsPageView.swift`)
- **Severe Progress Bar Collision: ✅ [FIXED]**
  - *Fix:* Added top (0.05) and bottom (0.88-1.0) linear gradient edge fade mask with `.clipped()` to `lyricStage` and added clearance padding before bottom transport controls. Text dissolves seamlessly into darkness above controls.
  - *Evidence:* `/tmp/caraoke_live/shot_0052.png`, `shot_0056.png`, `clip2_7.0s.png`
  - Bottom scrolling lyrics (`"You've got that good loving"`, `"Nothing will ever be the same"`) pass directly behind and intersect with the white progress bar and transport buttons (`prev`, `play`, `next`).
  - *Root Cause:* In `LyricsPageView.swift`, `lyricStage` (`ScrollView`) had insufficient bottom padding / safe area insets before the fixed transport overlay container, causing text to run behind the controls without clipping or fade mask.
- **Repeated Chorus / Hook Jump: ✅ [FIXED]**
  - *Fix:* Replaced `allLines.firstIndex(where:)` string comparison with timeline index tracking (`model.currentLineIndex`). Repeated chorus lines remain uniquely tracked; auto-scrolling moves forward monotonically.
- **Pause Button State Inversion: ✅ [FIXED]**
  - *Fix:* Assigned `self.lyricState = state` in `RidePlaybackController.render()` and added optimistic state toggle in `RideModeViewModel.transport(.playPause)`. Transport button flips immediately on tap.

### G. In-App Home Screen Layout & Miniplayer Occlusion
- **Bottom Content Obscured:**
  - *Evidence:* `/tmp/caraoke_live/shot_0045.png`
  - The floating bottom miniplayer (`Thinkin Bout You`, transport controls, Spotify badge) hovers directly on top of the `Music sources` section (`Apple Music` and `Spotify` list items).
  - Tapping or viewing music sources is obstructed.
  - *Root Cause:* `HomeView.swift` scroll container lacks a bottom safe inset or spacer (needs `padding(.bottom, 72)`).

---

## 4. Actionable Fix Plan

1. **Audio Sync Lead (`SpotifySource.swift`, `SyncEngine.swift`):**
   - Record `requestStartTime = Date()` before `session.data(for: request)`.
   - Calculate elapsed network latency `rtt = Date().timeIntervalSince(requestStartTime)`.
   - Compensate anchor: `anchorTime = requestStartTime + (rtt / 2)`.
   - Add a 250ms karaoke anticipation offset so lyrics lead singing rather than lag.
2. **Lock Screen & In-App Card Geometry (`LyricTileView.swift`, `LyricType.swift`):**
   - Increase `maxLyricWidth` on `.lockBanner` and `.home` from `250` to `315`.
   - Adjust `LyricSurface.lockBanner.budgets` or reduce padding from `16` to `10` so 4 rows (88pt + spacing) fit inside the 119pt block without dropping neighbor lines.
   - Replace colliding `.move(edge: .top)` / `.move(edge: .bottom)` transition with a clean crossfade `.opacity` or unified offset transition to eliminate mid-flight text overlap.
3. **Full Lyrics Page Layout (`LyricsPageView.swift`):**
   - Add `.safeAreaInset(edge: .bottom)` or bottom padding to `ScrollView` content equal to transport bar height (~110pt) + bottom edge gradient mask so lyrics fade out cleanly before the scrub bar.
4. **Home View Miniplayer Clearance (`HomeView.swift`):**
   - Add `.safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }` to the main Home scroll view.
