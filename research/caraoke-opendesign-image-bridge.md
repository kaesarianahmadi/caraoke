# Caraoke × OpenDesign — Image-to-Text Bridge (paste-ready)

> OpenDesign's model pipeline is text-only and will never read pixels — giving it a PNG alongside the markdown spec changes nothing. The bridge: DSH reads OpenDesign's project folder on disk and converts any image to text via the vision bridge. This file holds the extractions in paste-ready form.

**Bridge path (reusable):**
`~/Library/Application Support/Open Design/namespaces/release-stable-intel/data/projects/4760f07c-e154-4ca7-b7bd-ba3f627975fa/`
Screens live as HTML in `screens/` (home, player-lyrics, settings, live-activity) + `index.html` (launcher). Renders and reference images land in the project root as PNG. Any image there → DSH converts → paste this kind of text back.

---

## 1. render-home-light.png — what the light-mode render actually shows

**Composition:** iPhone mockup on a light-grey canvas; state chips at top: `A · Playing`, `B · Idle`, `C · Off`, `D · Needs setup`; caption `CARAOKE · STATE A: READY, MUSIC PLAYING`. Status bar 9:41.

**Screen content, top → bottom (all text verbatim):**
- Header: brandmark + **Caraoke** title, settings (gear) icon on the right
- **Now Playing card:** Mr. Brightside — The Killers; progress row `1:24` … `-1:28` (negative remaining); a **Live** indicator; a `Lyrics >` chevron row
- **Live Lyrics card:** toggle switch (green/on) — "Puts synced lyrics on CarPlay while your music plays. Pauses safely when you park."
- **Music sources:** Apple Music — `Connected` · Spotify — `Not connected`
- Footer: `Use while parked · Designed for passengers`

**Defect scan:** no clipped/overlapping text, no obvious misalignment detected; layout reads as a clean single-column iOS settings-style home. Light palette renders as expected (light canvas, dark ink text, amber accents on the Live/badge elements).

**How to use with OpenDesign:** when you want it to *reason about the rendered output*, paste this section next to your feedback — e.g. "per the render extraction, the Live chip reads correctly; darken X". It cannot re-ingest the PNG.

---

## 2. IMG_4788.PNG — Dynamic Lyrics settings screen (competitor reference, now text)

Dark-mode iOS Settings screen with sectioned preference cards: **General** (General settings), **connect music** (Apple Music / Spotify / Go), **Shazam Mode**, **Support us** (Good reviews / Share with friends), **contact us** (common problem / Feedback / About us), version `v2.0.3`, ICP filing `粤ICP备2024176912号-2A`. Status 11:35, battery 46.

## 3. IMG_4792.PNG — Dynamic Lyrics features/how-to screen (competitor reference, now text)

Dark settings integration for 'Dynamic Lyrics' while playing Ivy — Frank Ocean (via Spotify): banner "how to display lyrics on CarPlay"; **Live Activities** card — "Show lyrics on the Dynamic Island, Lock Screen, CarPlay, and Apple Watch" with synced preview lines (In the halls of your hotel / Arm around my shoulder so I could tell / How much I meant to you / Meant it sincere back then); **Widget** card — "You can add widgets to desktop, CarPlay, StandBy, etc." with widget preview (Ivy - Frank Ocean + active line), and `Click to view full lyr…`.

## 4. IMG_4793.PNG — Dynamic Lyrics lock screen (competitor reference, now text)

Dark lock screen: Fri 28 Aug, 11:36, widget "No upcoming events"; media player — **blond** (Ivy) · Frank Ocean, `2:17 / -1:52`, plus a synchronized lyrics panel with lines: "It's not the same, ivory's illegal / Don't you remember? / I broke your heart last week / You'll probably feel better by the weekend".
