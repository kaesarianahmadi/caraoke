# Caraoke — App Icon & Screenshot Specs (for OpenDesign)

Support material for Phase A Step 6 (you own the visual design; these are the
required canvas sizes sourced from Apple HIG / App Store Connect requirements,
2026 standards).

## App icon

| Asset | Size | Notes |
|---|---|---|
| Marketing icon (App Store Connect) | **1024×1024 px** PNG/JPEG, no alpha, no rounded corners (iOS masks it) | The one to design first |
| App icon (asset catalog) | 1024×1024 single-size (Xcode 14+) | Same asset |
| Alternate icon (optional, Product Page Optimization test) | 1024×1024 | The brainstorm suggested testing black minimal vs amber-glow variants |

Design direction per PRD palette "Night Podium": deep blue-black substrate
`oklch(0.16 0.015 260)`, stage-glow amber accent `oklch(0.78 0.16 55)`, "C"
glyph. Keep the mark readable at 60 px (home screen small size).

## Live Activity / widget canvases (SwiftUI, adaptive — design at reference sizes)

| Surface | Reference width | Notes |
|---|---|---|
| Lock Screen (iOS 16.2+) | ~393–430 pt | Leading/trailing padding handled by system; lyric line = hero |
| Dynamic Island expanded | 371 pt | Clamps 2 lines current + 2 next per PRD |
| CarPlay small family | ~compact tile | Our `LyricTileView` handles; keep type ≥17 pt equivalent (PRD 6.2) |

## App Store screenshots (required for submission)

| Device class | Exact size | Needed |
|---|---|---|
| iPhone 6.9" (16 Pro Max class) | **1320×2868 px** portrait | 3–10 screenshots (up to 10) |
| iPhone 6.5" (11/12/13 class) | 1284×2778 px | 3–10 (legacy row still commonly required) |
| Optional: iPad 13" | 2064×2752 px | Only if iPad support ships |

Screenshot shot-list (maps to the marketing funnel): 1) chorus on CarPlay
(the reveal), 2) home screen with Ride Mode switch, 3) Live Activity on lock
screen, 4) lyric unavailable / offline state (honesty = trust), 5) paywall
with yearly highlighted. Use original fixture lyrics only.

## App preview video (optional, strong for this category)

- 15–30 s, 6.9" first; scripted per the brainstorm's 10-second demo beat:
  song plays → chorus appears on CarPlay → everyone sings.
