# Caraoke — Design Requirements & Guidance for OpenDesign

> **Purpose:** single source of design truth, matching what the app **actually is** today (every state, field, and action below exists in the shipped codebase) while pulling the visual language up to the category standard set by Dynamic Lyrics (灵动歌词) — the competitor whose Live Activity design currently leads the App Store category.
> **How to use:** feed this whole file to OpenDesign as project context, then work screen by screen. Anything marked **[SYSTEM]** cannot be redesigned around — it is how the software works. Anything marked **[Borrow]** comes from verified competitor screenshots. **[Δ]** = concrete change to make to the current OpenDesign screens.
> **Sources:** `research/dynamic-lyrics-uiux-spec.md` (Dynamic Lyrics full extraction), `research/caraoke-opendesign-image-bridge.md` (your current renders, extracted), the CaraokePOC codebase (components, states, copy).

---

## 1. What Caraoke actually is (so the design matches the machine)

**One mental model:** Caraoke is a *lyrics renderer* for the car. It detects now-playing from Apple Music or Spotify (BYO Client ID), fetches synced lyrics from LRCLIB, and projects **one synchronized lyric stream** onto system surfaces: the Live Activity (Lock Screen), Dynamic Island, and the CarPlay Dashboard. The in-app UI is a control panel, not a player.

**[SYSTEM] The product has exactly one primary control:** the Ride Mode on/off switch. There is no play button, no queue, no lyrics browser, no themes. The CarPlay surface is **read-only** — Apple renders it, users never tap it.

**[SYSTEM] The Live Activity gets exactly these 7 data fields and nothing else** (`LyricsActivityAttributes.ContentState`):

| Field | Type | What the design may do with it |
|---|---|---|
| `title` | String | Song title |
| `artist` | String | Artist name |
| `currentLine` | String | **The hero.** Largest text on every surface |
| `nextLine` | String? | Quieter "coming up" line |
| `isPlaying` | Bool | Controls Live/Paused semantics |
| `progress` | Double 0–1 | Thin progress bar |
| `lineIndex` | Int? | Internal (drives update policy) |

There is no album art, no translation, no word-level timing, no control buttons in the payload. **Do not design surfaces that need data the payload doesn't carry** — that is how designs diverge from what ships.

**[SYSTEM] The five Live Activity states that must be designed** (all real states of the pipeline):
1. **Playing** — isPlaying=true, current+next lines live
2. **Paused** — current line stays fully visible (never an empty state), pause indicator, no "Live" pulse
3. **No lyrics found** — track has no synced lyrics (`LyricsRepository` returned nil) → calm fallback showing `♪ title`
4. **Loading** — lyrics being fetched for a brand-new track (brief; shimmer or dimmed placeholder)
5. **Stale/ended** — activity ended (30 s no-playback grace, Ride Mode off, or system dismissal)

**[SYSTEM] Rendering rules (iOS enforces these):**
- CarPlay shows the **small activity family** — a compact tile ~2 lines; falls back to Dynamic Island compact if weak. The CarPlay tile is the hero surface of the whole product.
- `activityFamily` comes from `@Environment`, so CarPlay-small and Lock Screen share one adaptive tile (`FamilyAdaptiveTile` → `LyricTileView`).
- Activity background: dark translucent material (`.activityBackgroundTint(.black.opacity(0.7))`), system capsule/continuous radii. Never pure flat black, never light mode.
- Anti-false-signal rules (PRD 6.1): the Live dot pulses **only while playing**; no spinner outside Loading; the word "Live" never appears while Paused; Paused keeps the line visible.
- Clamp rules: CarPlay current line ≤2 lines @ ~17 pt, next line 1 line; Lock Screen current ≤3 lines @ ~26 pt; Dynamic Island expanded ≤2 lines both. Long titles/artists truncate with tail ellipsis.

---

## 2. Competitor-verified visual language (borrow this)

Extracted from Dynamic Lyrics' public screenshots (US/CN/JP storefronts) — the category's baseline that users already recognize:

**[Borrow] The lyric-line styling system (the core pattern):**
1. **Active line:** 100% opacity, bold, largest, pure white
2. **Neighbor lines:** dimmed ~55–60% (iOS `secondaryLabel` on dark ≈ `#EBEBF5` at 55–65%)
3. **Farther lines:** progressively dimmer; on full-screen surfaces, blurred
4. **Progress:** one thin bar, elapsed time left, remaining time right shown as **negative** (`-3:57`) — this exact convention
5. **Source badge:** small "Music" / "Spotify" indicator inside expanded surfaces
6. **Consistency:** the *same* active/inactive rules scale across every surface — that consistency IS the product feel

**[Borrow] Materials & geometry:**
- Surfaces = iOS dark glass: `#1C1C1E` ~90–100% material — never flat black, never light glass
- Continuous corner radii: Live Activity card ≈ 24–32 pt; widgets ≈ 22–26 pt; floating elements 16–20 pt
- Typography: SF Pro only; hierarchy from weight + size + opacity, never color changes
- Elapsed/remaining times: tabular numerals (SF Mono feel), `1:04` left · `-3:57` right

**[Borrow] The widget/Activity header pattern:** app identity (icon + name) + live status ("Playing") + a control, in one header row.

**[Borrow] CarPlay context:** CarPlay lives on a dashboard next to a map tile — the lyrics tile must survive bright daylight and night driving; treat contrast as a hard requirement, and include the safety line "CarPlay lyrics are only for passengers" somewhere in marketing (Dynamic Lyrics does; it disarms the safety objection).

**Do NOT borrow:** word-by-word karaoke fill (push-throttle risk, PRD D4 — and notably *Dynamic Lyrics doesn't do it either*), floating window, home-screen widgets, translations, Shazam mode, sharing cards — all out of MVP scope. The design should not include them.

---

## 3. Caraoke system palette (locked PRD 7.2 — "Night Podium")

| Token | Value | Role |
|---|---|---|
| `--bg` | `oklch(0.16 0.015 260)` | deep blue-black substrate |
| `--surface` | `oklch(0.21 0.018 260)` | cards, sheets |
| `--fg` | `oklch(0.95 0.005 260)` | primary text / active lyric |
| `--muted` | `oklch(0.62 0.012 260)` | secondary text / next line |
| `--border` | `oklch(0.30 0.015 260)` | hairlines |
| `--accent` | `oklch(0.78 0.16 55)` | stage-glow amber — budget ≤2 uses/screen (switch On-state + Live dot) |
| State colors | systemGreen / systemRed / systemOrange semantics only | success / error / warning |

Accent budget: only the Ride Mode switch (On) and the Live dot may be amber. Everything else greyscale-on-dark. Motion ≤150 ms, confirmation-only, `prefers-reduced-motion` respected.

---

## 4. Screen-by-screen requirements (matched to the shipped app)

### 4.1 `screens/home` — the control panel
**[SYSTEM] Information architecture is fixed** (this is what HomeView renders, top → bottom):
1. Gear icon (top-right) → opens Settings sheet
2. Brand block: icon + "Caraoke — Live Lyrics" + "Road Trip Lyrics"
3. Master **Ride Mode toggle** with two truthfully-bound captions: OFF → "Lyrics to CarPlay when music plays." · ON → "Lyrics are live."
4. **Now Playing preview** — current line (large) + next line (quieter); labelled "Now playing"
5. Home states that must be designed (real states): A ready+playing · B ready idle ("Start playing a song — lyrics will follow.") · C switch off ("Ready when you are.") · D needs Live Activities permission (switch gated — never shows On without the permission)
6. Footer: "Use while parked · Designed for passengers"

**[Δ] Deltas vs your current render:** keep the overall structure (it's correct) — tighten: (a) the toggle caption must swap with state exactly as above; (b) the Now Playing card must show **currentLine as hero**, not song title as hero — title/artist are metadata; (c) negative remaining time `-1:28` convention ✓ keep; (d) Music sources row should show Spotify as **"Add your own Spotify app (beta)"** entry point opening the BYO setup (see 4.3), never a plain Connected/Not-connected toggle; (e) the "Live >" chevron row inside Now Playing is not a real affordance in the app — remove or map it to opening the Live Activity preview.

### 4.2 `screens/live-activity` — the product surface (priority 1)
Design **5 families × 5 states** at real scale — this is the surface users see in the car:

| Family | Geometry guidance |
|---|---|
| **Lock Screen banner** (primary) | Dark glass card, radius ~28 pt: header row (app identity + status), title · artist row, current line ~17 pt bold white, next line ~15 pt @ 55%, thin progress + `1:04 / -4:00` |
| **Dynamic Island compact** | Marquee current line only, capsule, ~13–15 pt |
| **Dynamic Island expanded** | Current line + next line + source badge (Apple Music / Spotify) + progress |
| **Dynamic Island minimal** | Glyph + tiny text field |
| **CarPlay small** | The hero tile: 2-line-clamped current line @ ~17 pt, next line 1 line caption, no header chrome (no room) — highest contrast of all families |

**[Δ] Deltas vs your current live-activity screen:** per your own assessment it drifts from competitors — apply §2 without exception: dark glass not custom gradients; active/neighbor opacity ladder (100% / 55% / 35%); thin progress bar with negative remaining; **no buttons inside the activity** (iOS forbids interaction in CarPlay rendering); the pause glyph lives only in the header position, never over lyrics; source badge only in expanded/minimal. Every state in §1 (Playing/Paused/No lyrics/Loading/Stale) must exist per family — competitors show Playing only; the states are where Caraoke can visibly out-quality them.

### 4.3 `screens/settings` — match the real sheets
**[SYSTEM] Settings contains exactly these sections (SettingsView):**
1. **Caraoke Plus** → opens the paywall sheet
2. **Spotify** section (public): BYO Client ID flow — paste field ("Paste your Client ID"), Save Client ID, Connect Spotify / Disconnect, live Connection status; footer: "Connect Spotify with your own Spotify app (2–3 minutes, see steps above). A Spotify Premium subscription is required for the lyrics API, and the token stays on this device." **When no Client ID saved:** the in-app guide shows the 5 setup steps (dashboard → log in → accept terms → Create app → Redirect URI `caraoke://callback` → tick iOS → save → copy Client ID)
3. **Ride**: total ride time + reset
4. **Lyrics**: "Community lyrics via LRCLIB" + lrclib.net + Support LRCLIB links (attribution etiquette — keep visible, it's a hedge commitment)
5. **Storage**: clear lyrics cache
6. **Support**: mailto
7. **Version** + safety footer

**[Δ] Deltas:** align section order and row copy to the above (the design currently invents rows the app doesn't have — Spotify integration must show the **BYO paste field**, not a plain connect toggle; the LRCLIB attribution rows are mandatory, not decorative).

### 4.4 Paywall sheet (Caraoke Plus)
**[SYSTEM] Three plans, yearly visually recommended, lifetime secondary:**
- Yearly **$11.99/yr** — "Best value — just $1.00/month" + Recommended badge
- Monthly **$1.99/mo** — "Try it for a trip"
- Founding Lifetime **$20 once** — "One payment. Keep Caraoke forever." + "limited launch offer" footnote
- Headline: "Make every ride a sing-along" · sub: "Keep live lyrics ready on CarPlay, whenever the chorus comes on."
- Restore purchases link + auto-renew fine print (Apple-required wording: renews unless cancelled ≥24 h before period end; manage in Apple ID settings)
- **[SYSTEM]** Prices render from StoreKit `displayPrice` at runtime; design with the literal fallback strings above.

### 4.5 `screens/player-lyrics` — de-prioritize honestly
The MVP app (per PRD D7: one screen + sheets) has **no full-screen scrolling lyrics page** — that's a competitor feature we explicitly cut, and our pipeline doesn't feed it. Design it only as a **Phase-2 concept** clearly labelled as post-MVP, or repurpose the screen as the **in-app ride preview** (what HomeView shows while a ride is live: current/next lines in large type over the dark substrate). Do not spend polish here before the Live Activity surfaces are right.

### 4.6 App icon (1024×1024, no alpha, no pre-rounded corners)
"Night Podium": deep blue-black substrate `oklch(0.16 0.015 260)`, amber stage-glow "C" mark. Must read at 60 px. Placeholder asset catalog (`AppIcon.appiconset`) is already wired into the Xcode project — export the final PNG into `CaraokePOC/Assets.xcassets/AppIcon.appiconset/`.

---

## 5. Copy deck (verbatim from code — use exactly these strings)

| String | Where |
|---|---|
| "Caraoke — Live Lyrics" | App title |
| "Road Trip Lyrics" | Home tagline |
| "Ride Mode" · "Lyrics to CarPlay when music plays." · "Lyrics are live." | Master switch |
| "Now playing" | Home preview label |
| "Use while parked · Designed for passengers" | Footers |
| "Make every ride a sing-along" | Paywall headline |
| "Keep live lyrics ready on CarPlay, whenever the chorus comes on." | Paywall sub |
| $1.99 / month · $11.99 / year · $20 once — limited launch offer | Paywall plans |
| "Restore purchases" | Paywall |
| "Community lyrics via LRCLIB" | Settings |
| "Connect Spotify with your own Spotify app (2–3 minutes…)" | Settings footer |
| "caraoke://callback" | BYO redirect URI |
| "Clear downloaded lyrics cache" | Settings/Storage |
| "Contact support" | Settings |

Tone rules: plain words, no exclamation marks in-app, no "AI", no jargon; every error says what happened + what to do next (e.g. Spotify needsAllowlist state → "Spotify access is currently limited to beta testers. Apple Music is fully supported.").

---

## 6. Hard "do not" list (violates system, review, or the locked PRD)

1. No buttons/controls inside any Live Activity family (CarPlay renders read-only)
2. No album art in the activity payload surfaces (data doesn't exist in `ContentState`)
3. No word-by-word karaoke fill, no translations, no themes/font pickers, no tab bar
4. No light-mode Live Activity surfaces (dark glass is the industry + HIG baseline here)
5. No system permission prompt without its rationale row (Live Activities, Apple Music, Spotify BYO)
6. Never show "Connected/live" for a source that isn't (the switch never lies — PRD state D)
7. Nothing that implies the driver reads text while driving
8. No third-party SDK visual clutter; attribution rows stay visible

---

## 7. Definition of done (per screen)

1. Every state from §1/§4 rendered — no blank placeholders, no lorem
2. Copy matches §5 verbatim (it mirrors shipped strings)
3. Dark glass materials + opacity ladder per §2; amber budget ≤2/screen
4. CarPlay small tile legible in daylight and night
5. Zero elements requiring data/actions the backend doesn't have (check §1 payload table)
6. 44 pt tap targets (in-app), reduced-motion respected, contrast never decreasing on state change
