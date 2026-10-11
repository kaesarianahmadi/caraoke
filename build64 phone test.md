# Build 64 Phone & CarPlay Live Test Defect Analysis

**Date:** 2026-09-22  
**Build:** 64 (`CURRENT_PROJECT_VERSION: "64"`)  
**Harness:** Real iPhone tethered via USB + Apple CarPlay Head Unit display mirror  
**Test Dataset:** 48 full-resolution screenshots (`/tmp/build64_screenhots_caraoke/`)  
- **CarPlay (Landscape 1578×888, 24 shots):** `IMG_5711`, `IMG_5713`, `IMG_5716`, `IMG_5718`, `IMG_5719`, `IMG_5722`, `IMG_5724`, `IMG_5726`, `IMG_5727`, `IMG_5729`, `IMG_5730`, `IMG_5731`, `IMG_5736`, `IMG_5737`, `IMG_5739`, `IMG_5741`, `IMG_5743`, `IMG_5745`, `IMG_5747`, `IMG_5749`, `IMG_5751`, `IMG_5753`, `IMG_5755`, `IMG_5757`
- **iPhone iOS 26 (Portrait 1170×2532, 24 shots):** `IMG_5712`, `IMG_5714`, `IMG_5715`, `IMG_5717`, `IMG_5720`, `IMG_5721`, `IMG_5723`, `IMG_5725`, `IMG_5728`, `IMG_5732`, `IMG_5733`, `IMG_5734`, `IMG_5735`, `IMG_5738`, `IMG_5740`, `IMG_5742`, `IMG_5744`, `IMG_5746`, `IMG_5748`, `IMG_5750`, `IMG_5752`, `IMG_5754`, `IMG_5756`, `IMG_5758`

---

## 1. Executive Summary & Design Rule Scorecard

| Surface | Defect / Metric | Guideline Rule | Build 64 Status | Severity |
|:---|:---|:---|:---:|:---:|
| **CarPlay Dashboard** | Mid-flight text collision | Clean crossfade, no coordinate overlap | **FAIL** (IMG_5730) | CRITICAL |
| **CarPlay Dashboard** | Skeleton loading bar flash | No distracting animations while driving | **FAIL** (IMG_5727, 5737) | HIGH |
| **CarPlay Dashboard** | 5-row text cramming & top clipping | 2–3 glanceable lines, 10pt safe insets | **FAIL** (IMG_5731, 5753, 5757) | HIGH |
| **CarPlay Full App** | Track title ellipsis truncation | Full readable title or marquee scroll | **FAIL** (IMG_5747) | MEDIUM |
| **Live Activity** | Extension crash alert | Zero crashes, <30MB WidgetKit memory | **FAIL** (IMG_5738) | FATAL |
| **Live Activity** | Top ascender edge clipping | Smooth linear gradient edge mask | **FAIL** (IMG_5750) | HIGH |
| **Live Activity** | Bottom line border collision | 14pt minimum bottom clearance | **FAIL** (IMG_5733) | HIGH |
| **Live Activity** | Row jumping (1 line to 4 lines) | Stable 2–3 line vertical balance | **FAIL** (IMG_5742, 5754, 5756) | MEDIUM |
| **Home Screen 4x4** | Over-wrapping / column cramp | Unused width balance (maxLyricWidth) | **FAIL** (IMG_5721, 5723) | MEDIUM |
| **Home Screen 2x4** | Vertical dead space | Balanced vertical centering | **FAIL** (IMG_5721) | LOW |
| **In-App Home** | Floating miniplayer occlusion | 44pt+ touch target & bottom safe insets | **FAIL** (IMG_5714, 5720, 5728, 5740) | HIGH |

---

## 2. CarPlay Screen Defect Analysis

### Defect C1: Simultaneous Mid-Flight Text Collision During Lyric Transition
- **Evidence:** `IMG_5730.PNG` (CarPlay Dashboard, Drake — *Passionfruit*, 8:25 AM, 18 km/h).
- **Observed Behavior:** As the line transitions from *"Passionate from miles away"* to *"Passive with the things you say"*, both strings render concurrently in the exact same vertical bounding box. The letters of both lines overlap directly on top of each other, creating an unreadable visual smudge.
- **Rule Violation:** Car Safety HIG (`research/driveverse-verification.md` & `research/dynamic-lyrics-uiux-spec.md`). Glancing driver requires instant legibility under 2 seconds; overlapping glyphs cause cognitive distraction.
- **Root Cause:** `LyricTileView.swift` uses a `VStack` where outgoing items transition with `.move` or uncoordinated `.opacity` without enforcing exclusive line slot reservations. When state updates arrive within 300ms, the outgoing line remains visible while the incoming line fades in on identical coordinates.

#### Visual Representation (IMG_5730)
```
+-------------------------------------------------------------+
| CarPlay Dashboard Media Tile (350x260 pt)                   |
|                                                             |
|  [Cover Art]        [ << ]       [ || ]       [ >> ]        |
|  More Life                                                  |
|-------------------------------------------------------------|
| ACTUAL (Build 64):                                          |
|                                                             |
|           Passionate from miles away                        |
|           Passi#e w#th th# th#ngs y#u s#y   <-- COLLISION!  |
|                     old ways                                |
|                                                             |
| EXPECTED:                                                   |
|                                                             |
|           Passionate from miles away        (fading out)    |
|                                                             |
|           Passive with the things you say   (hero active)   |
|                                                             |
+-------------------------------------------------------------+
```
- **Code Fix:** Replace simultaneous asymmetric movements with a unified stack crossfade `.transition(.opacity.animation(.easeInOut(duration: 0.25)))`. Bind view IDs monotonically to timeline indices.

---

### Defect C2: Gray Skeleton Loading Bars Visible on Dashboard Media Tile
- **Evidence:** `IMG_5727.PNG` (8:24 AM), `IMG_5737.PNG` (8:27 AM).
- **Observed Behavior:** When a track transitions or lyrics are re-fetching over cellular relay, the lower half of the media dashboard tile renders three horizontal gray placeholder bars (`widthFraction: 0.90, 0.70, 0.50`).
- **Rule Violation:** Apple CarPlay Guidelines. High-contrast pulsing placeholder graphics in driving UI are prohibited because they attract involuntary peripheral vision shifts.
- **Root Cause:** In `LyricTileView.swift:404`:
  ```swift
  case .loading:
      boxed(VStack(alignment: .center, spacing: 8) {
          skeleton(widthFraction: 0.90)
          skeleton(widthFraction: 0.70)
          skeleton(widthFraction: 0.50)
      }, spec: spec, alignment: .center)
  ```
  Status flips to `.loading` immediately on track boundary, purging the title/artist intro text.

#### Visual Representation (IMG_5727, IMG_5737)
```
+-------------------------------------------------------------+
| ACTUAL (Build 64 Skeleton Flash):                           |
|                                                             |
|  [Cover Art]        [ << ]       [ || ]       [ >> ]        |
|-------------------------------------------------------------|
|           [===============================]                 |
|           [======================]                          |
|           [===============]                                 |
|                                                             |
| EXPECTED (Automotive Intro Holding State):                  |
|                                                             |
|  [Cover Art]        [ << ]       [ || ]       [ >> ]        |
|-------------------------------------------------------------|
|                                                             |
|                     Passionfruit                            |
|                        Drake                                |
|                                                             |
+-------------------------------------------------------------+
```
- **Code Fix:** For `surface == .carPlaySmall` and `.carPlayLyrics`, suppress `skeleton()` rendering entirely. Display `title` and `artist` at 15pt semibold until `status == .playing` delivers valid lyric lines.

---

### Defect C3: 5-Row Vertical Cramming and Top Ascender Clipping
- **Evidence:** `IMG_5731.PNG` (8:25 AM), `IMG_5753.PNG` (8:33 AM), `IMG_5757.PNG` (8:33 AM).
- **Observed Behavior:**
  - In `IMG_5731.PNG`: 5 rows crammed into ~80pt:
    `"I can't blame you,"` / `"no, no"` / `"Um, trying to think"` / `"of the right thing to"` / `"say"`
  - In `IMG_5753.PNG`: Top line `"taking a hold on me (where, where, wh..."` has its top ascenders sliced off by the upper boundary and is truncated with `...`.
  - In `IMG_5757.PNG`: 5 rows crammed into the dashboard card:
    `"Let's get the"` / `"party started"` / `"See you at the bar,"` / `"you was hardly"` / `"talkin'"`
- **Rule Violation:** Car Safety Compliance: 2-line glance rule. No more than 2–3 rows of text may exist in a secondary automotive tile. Ascenders must never touch outer frame bounds.
- **Root Cause:** `LyricTileView.swift:632`:
  ```swift
  else if surface == .carPlaySmall || surface == .carPlayLyrics {
      return row.kind == .hero ? 4 : 3
  }
  ```
  Allowing 4 hero rows + 3 neighbor rows permits up to 5-7 lines inside a rigid 80pt box. Usable height is exceeded, forcing text against boundaries.

#### Visual Representation (IMG_5753)
```
+-------------------------------------------------------------+
| ACTUAL (Build 64 - 5 Rows Jammed & Top Clipped):            |
|                                                             |
|  [Cover Art]        [ << ]       [ || ]       [ >> ]        |
|-------------------------------------------------------------|
|  - taking a hold on me (where, where, wh...  <-- TOP CLIPPED|
|  I need a one dance                                         |
|  Got a Hennessy in                                          |
|  my hand                                                    |
|  (where, where?)                                            |
+-------------------------------------------------------------+
| EXPECTED (Glanceable 2-Row Budget with Safe Margins):       |
|                                                             |
|  [Cover Art]        [ << ]       [ || ]       [ >> ]        |
|-------------------------------------------------------------|
|                                                             |
|          taking a hold on me (where, where?)                |
|          I need a one dance                                 |
|                                                             |
+-------------------------------------------------------------+
```
- **Code Fix:** Set `budget.heroRows: 2` and `budget.neighborRows: 1` for `carPlaySmall` in `LyricType.swift`. Set `allowance` to max 2 lines for hero, 1 for neighbor. Enforce 10pt vertical padding.

---

### Defect C4: Track Title Ellipsis Truncation in Full-Screen CarPlay App
- **Evidence:** `IMG_5747.PNG` (CarPlay full-screen Caraoke app, Mac Miller ft. Ty Dolla $ign — *Cinderella*, 8:31 AM).
- **Observed Behavior:** In the left metadata column, the song title is truncated:
  `Cinderella (feat. Ty Doll...`
- **Rule Violation:** App Specification Section 4.3 (CarPlay App Architecture): Track titles must wrap to 2 lines before truncating.
- **Root Cause:** Label has `.lineLimit(1)` without secondary wrap allowance or marquee scrolling.
- **Code Fix:** Update track identity view in `CarPlayWidgets.swift` to `.lineLimit(2)` with `minimumScaleFactor(0.85)`.

---

## 3. Lock Screen Live Activity Defect Analysis

### Defect L1: Fatal Extension Crash on Real Device
- **Evidence:** `IMG_5738.PNG` (iPhone Lock Screen, 8:27 AM).
- **Observed Behavior:** Live Activity suddenly terminates; iOS displays a system crash alert:
  ```
  +---------------------------------------------------+
  |          "Caraoke: Live Lyrics" Crashed           |
  |  Do you want to share additional information      |
  |  with the developer?                              |
  |                                                   |
  |      [ No Thanks ]              [ Share ]         |
  +---------------------------------------------------+
  ```
- **Rule Violation:** App Store Review Guideline 2.1 (Performance / Crashes). Automatic rejection trigger.
- **Root Cause:** Memory limit violation (>30MB jetsam limit in WidgetKit extension) or unhandled force-unwrap in `SharedWidgetStore` / ActivityKit background timeline payload encoding.
- **Code Fix:**
  1. Add `do-catch` blocks around all ActivityKit payload updates in `LyricsActivityController.swift`.
  2. Clamp cached `artworkData` payload to maximum 300KB (downscale image before encoding into `ActivityContent`).

---

### Defect L2: Top Ascender Edge Clipping on Outgoing Context Row
- **Evidence:** `IMG_5750.PNG` (iPhone Lock Screen, Drake — *One Dance*, 8:33 AM).
- **Observed Behavior:** The topmost lyric line `"('Cause I got a...)"` is cut off flush by the top card border; only 3–4 pixels of letter descenders are visible.
- **Rule Violation:** Glass card spec (`design/swiftui-frontend-guidance.md`). Content must fade smoothly into background opacity; glyphs must never abruptly clip against the container stroke.
- **Root Cause:** The Live Activity container height is fixed at `119pt`, but `padding(.top)` is only 6pt. Outgoing line rolls into the top 0–10pt zone where no fade mask exists.

#### Visual Representation (IMG_5750)
```
+-------------------------------------------------------------+
| Lock Screen Live Activity Card (360x119 pt)                 |
|                                                             |
|  ---------------------------------------------------------  |
|  ...  ,   ,     ,   ,  ...    <-- TOP ASCENDERS CUT OFF!    |
|                                                             |
|  I need a one dance (where, up, where, where?) [HERO]       |
|                                                             |
|  Got a Hennessy in my hand (where, where?)     [NEXT]       |
|  ---------------------------------------------------------  |
+-------------------------------------------------------------+
```
- **Code Fix:** Apply a 16pt top and bottom linear gradient alpha mask:
  ```swift
  .mask(
      LinearGradient(
          stops: [
              .init(color: .clear, location: 0.0),
              .init(color: .black, location: 0.14),
              .init(color: .black, location: 0.86),
              .init(color: .clear, location: 1.0)
          ],
          startPoint: .top, endPoint: .bottom
      )
  )
  ```

---

### Defect L3: Bottom Line Collision with Card Corner Radius
- **Evidence:** `IMG_5733.PNG` (iPhone Lock Screen, Drake — *Passionfruit*, 8:25 AM).
- **Observed Behavior:** Three lines are rendered:
  - Line 1: `"Passionate from miles away"`
  - Line 2: `"Passive with the things you say"`
  - Line 3: `"Passin' up on my old ways"`
  Line 3 is jammed into the bottom 4px of the card, colliding with the 24pt corner radius stroke.
- **Root Cause:** Line 1 wraps to 2 rows + Line 2 wraps to 2 rows = 4 rows. At 18pt font + 5pt spacing, required height is 92pt + 32pt padding = 124pt. Inside a 119pt fixed card, the 4th row crashes into the bottom border.
- **Code Fix:** Limit total simultaneous rendered rows to 3 (e.g. 2 hero rows + 1 next row, OR 1 prev + 1 hero + 1 next). When hero wraps to 2 rows, suppress the upcoming line.

---

### Defect L4: Severe Vertical Instability / Layout Jump (1 to 4 Rows)
- **Evidence:**
  - `IMG_5742.PNG` (8:30 AM): Card renders only **1 line** (`"I wanna be with you (Love me, just love me)"`). 70% of card is dead black void.
  - `IMG_5744.PNG` (8:30 AM): Card renders **2 lines**.
  - `IMG_5754.PNG` (8:33 AM): Card renders **4 lines**, pressed against incoming notification banners.
- **Rule Violation:** HIG Dynamic Island & Live Activity visual consistency. The card should maintain a consistent, stable optical weight and not fluctuate between a hollow box and an over-stuffed card.
- **Root Cause:** Dynamic row insertion without vertical stabilization. `rows(spec:budget:)` appends lines purely based on whether `previousLines` or `upcomingLines` is empty, without centering single-line content or balancing multi-line wraps.
- **Code Fix:** Enforce `centersVertically: true` on `.lockBanner`. Guarantee that single-line lyrics are placed at exact vertical center. When hero has 1 row, show 1 prev and 1 next.

---

## 4. Home Screen Widgets Defect Analysis

### Defect W1: 4x4 Large Widget Column Cramping & Word Fragmentation
- **Evidence:** `IMG_5721.PNG`, `IMG_5723.PNG` (Home Screen Large Widget).
- **Observed Behavior:**
  - In `IMG_5721.PNG`, text is fragmented into single-word lines:
    `"fuck that"`
    `"Fuck that shit"`
    `"Hold on, I got to start"`
    `"this motherfuckin'"`
    `"record over again"`
  - The lyric column is clamped to 225pt on a 338pt widget, wasting ~110pt of horizontal space and creating unnatural, choppy line wraps.
- **Rule Violation:** Design Spec Section 1.2 (`research/dynamic-lyrics-uiux-spec.md`): Large square widget must take advantage of full width to render lines naturally.
- **Root Cause:** `LyricTileView.swift:217` hard-caps `maxLyricWidth: 225`.
- **Code Fix:** Increase `maxLyricWidth` on `.widgetLarge` from 225pt to 275pt.

---

### Defect W2: 2x4 Medium Vinyl Widget Vertical Dead Space
- **Evidence:** `IMG_5721.PNG` (Home Screen Medium Vinyl Widget).
- **Observed Behavior:** When a short lyric plays (`"fuck that"`), the left column displays only the single phrase, leaving massive empty black space above and below it next to the rotating vinyl disc.
- **Root Cause:** When upcoming lines are delayed, no preview lines are fetched, and the view aligns to top-leading instead of true vertical center.
- **Code Fix:** Enforce `.frame(maxHeight: .infinity, alignment: .center)` in `VinylWidgetView.swift`. Show upcoming line preview at 50% opacity when hero line is under 20 characters.

---

## 5. In-App Home Screen & Miniplayer Defect Analysis

### Defect H1: Floating Miniplayer Completely Occludes "Music Sources" Section
- **Evidence:** `IMG_5714.PNG`, `IMG_5720.PNG`, `IMG_5728.PNG`, `IMG_5740.PNG` (In-App Home View).
- **Observed Behavior:** The persistent floating bottom miniplayer bar (`Track Title`, `Artist`, transport buttons, Spotify badge) hovers directly over the bottom list items in `Music sources`:
  - `Spotify (Active source)` is 70% covered.
  - Apple Music connection row is inaccessible without frantic over-scrolling.
- **Rule Violation:** iOS HIG Touch Target & Safe Area Clearance rules (`.agents/skills/make-interfaces-feel-better.md`). Interactive list rows must never be permanently obstructed by floating overlays.
- **Root Cause:** `HomeView.swift` wraps content in a standard `ScrollView` without bottom safe area inset padding for the floating overlay.

#### Visual Representation (IMG_5714, IMG_5740)
```
+-------------------------------------------------------------+
| In-App Home View (1170x2532 px)                             |
|                                                             |
|   Caraoke                                        [ ? ] [ * ]|
|   [ How to display lyrics everywhere > ]                    |
|                                                             |
|   Live Lyrics                              [ Toggle: ON ]   |
|   [ In-App Live Lyrics Preview Card ]                       |
|                                                             |
|   Widget                                                    |
|   [ 2x4 Medium Vinyl Widget Preview ]                       |
|                                                             |
|   Music sources                                             |
|   +-------------------------------------------------------+ |
|   | Apple Music                                           | |
|   | [===================================================] | |
|   | [ FLOATING MINIPLAYER BAR (LOVE. FEAT. ZA...)       ] | | <-- BLOCKED!
|   +-------------------------------------------------------+ |
+-------------------------------------------------------------+
```
- **Code Fix:** In `HomeView.swift`, add `.safeAreaInset(edge: .bottom)`:
  ```swift
  .safeAreaInset(edge: .bottom) {
      Color.clear.frame(height: 84)
  }
  ```

---

## 6. Actionable Implementation Checklist

```markdown
- [ ] 1. CarPlay Dashboard Text Collision & Glanceability (`CaraokePOC/iOS/LyricTileView.swift`):
      - Replace simultaneous coordinate transitions with unified .transition(.opacity)
      - Restrict carPlaySmall budget: max 2 hero rows, max 1 neighbor row
      - Add 10pt top padding inset to eliminate ascender clipping
- [ ] 2. CarPlay Automotive Intro State (`CaraokePOC/iOS/LyricTileView.swift`):
      - Suppress skeleton() animation on carPlaySmall and carPlayLyrics
      - Render static Title + Artist intro text while status == .loading
- [ ] 3. CarPlay App Metadata Wrap (`CaraokePOC/iOS/CarPlayWidgets.swift`):
      - Change CaraokeCarPlayIdentity title from .lineLimit(1) to .lineLimit(2)
- [ ] 4. Live Activity Stability & Edge Fades (`CaraokePOC/iOS/LyricsLiveActivity.swift`, `LyricTileView.swift`):
      - Clamp ActivityContent payload size to <300KB to prevent extension crashes
      - Apply 16pt top/bottom linear gradient alpha mask
      - Set centersVertically: true and cap simultaneous rows to 3
- [ ] 5. Home Screen 4x4 Widget Formatting (`CaraokePOC/iOS/LyricTileView.swift`):
      - Increase maxLyricWidth from 225pt to 275pt
- [ ] 6. In-App Home View Clearance (`CaraokePOC/iOS/HomeView.swift`):
      - Add .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
```
