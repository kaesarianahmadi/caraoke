# Dynamic Lyrics (灵动歌词) — Complete UI/UX Reference Spec

> **Purpose:** A single text-only design reference for OpenDesign (which cannot read images). Describes every public UI surface of the competitor app "Dynamic Lyrics" so it can be used as design context.
> **Compiled:** 2026-08-31, from App Store screenshots (US + CN + JP storefronts, iTunes lookup id `6476125287`), the App Store listing text, and musiclyrics.cn, extracted through a vision bridge.
> **Confidence markers:** **[V]** = verbatim from screenshot transcription or listing copy. **[I]** = inferred/reconstructed (system-standard iOS geometry, estimated values). All hex colors are estimates.

---

## 0. App snapshot

| Field | Value |
|---|---|
| Name | Dynamic-Lyrics (灵动歌词) **[V]** |
| Developer | Guangzhou Haoke Information Technology Co., Ltd **[V]** |
| Price | Free + "Dynamic Lyrics® Membership" (auto-renewing subscription OR one-time lifetime) **[V]** |
| Version / Released | 2.0.3 / 2024-04-08 **[V]** |
| Category | Music, Utilities **[V]** |
| Rating | 4.28★ (8,637 ratings, US) **[V]** |
| Languages | AR, EN, FR, JA, KO, ZH, ES **[V]** |
| Website | musiclyrics.cn **[V]** |

**Core promise [V]:** Real-time lyrics + translations shown on Lock Screen (Live Activity), Dynamic Island, home-screen widgets, StandBy, floating windows, full-screen page, and CarPlay. Works with Apple Music and Spotify. Shazam mode identifies music playing in any app/webpage/surroundings. Lyrics sharing cards. Membership unlocks all premium features, future updates, ad-free.

**One mental model [I]:** the app is a *lyrics renderer*, not a player. It detects now-playing from a source app, then projects one synchronized lyric stream onto 7+ system surfaces. Almost all visible UI is rendered on **dark translucent system surfaces with white text**; the app's own chrome stays mostly hidden behind the system surfaces it feeds.

---

## 1. Global design language

### 1.1 Color system
| Role | Value | Notes |
|---|---|---|
| Surface (system widgets) | `#1C1C1E` ~90–100% dark material [I] | Live Activities, widgets, floating window — iOS dark glass, never pure black flat |
| Surface (in-app full-screen) | Artwork-derived blurred gradient [V: "pastel-purple blurred background" for Lover] | Adaptive tinting from album art |
| Primary text (active lyric) | `#FFFFFF` [V: "highlighted in bold white"] | |
| Secondary text (inactive lyric) | `#EBEBF5` @ 55–65% [I — iOS secondaryLabel on dark] | |
| Tertiary text (metadata, artist) | `#EBEBF5` @ 30–40% [I] | |
| Translation text | Same white but smaller + dimmer than its source line [V] | |
| Marketing palette | Vivid coral-red / pink gradient backdrops behind device mockups [V: "vibrant red background", "vibrant pink backdrop"] | Store-marketing only, not in-app |

### 1.2 Typography
- System font throughout (SF Pro) [I — no custom fonts visible in any transcription].
- Scale ladder [I, estimated from mockups]:
  - Marketing headline: Bold ~34–40pt
  - StandBy lyrics: ~34–40pt+ (largest in-app text)
  - Full-screen active line: Bold ~22–28pt
  - Full-screen inactive lines: Regular ~17–20pt
  - Lock Screen Live Activity lines: ~15–17pt
  - Widget lines: ~13–15pt
  - Dynamic Island compact marquee: ~13–15pt
- Translation line ≈ 70–80% of its source line's size, regular weight [I].

### 1.3 Shape, material, depth
- Continuous corner radii everywhere [I]: Live Activity card ≈ 24–32pt; iOS widgets ≈ 22–26pt (system families); floating window ≈ 16–20pt; Dynamic Island = system capsule.
- Dark blur/translucency materials; floating window is translucent so underlying app stays visible [V: "always stays on top without affecting other operations"].
- Depth cues: soft shadow under floating window [I]; no heavy borders visible.

### 1.4 The lyric-line styling system (the app's core visual pattern) [V]
Consistent across every surface:
1. **Active line:** full opacity, bold/larger, white; on full-screen it is the only crisp line — "inactive lines are blurred and dimmed."
2. **Neighbor lines:** dimmed (~50–60% opacity); farther lines progressively dimmer/blurred.
3. **Translation:** rendered directly *under* its source line, smaller and dimmer — in compact surfaces only for the active line; in full-screen for every line.
4. **Progress:** thin bar, elapsed time left, remaining time right shown as negative (`-3:57`) [V].
5. **Karaoke emphasis:** the floating window repeats the current line (appears twice in transcription) [V] — current-line repetition as emphasis.
6. **Source badge:** compact "Music" / "Spotify" indicators appear in Dynamic Island expanded state and widget headers [V].

---

## 2. Surface-by-surface specs

### S1 — Lock Screen Lyrics (锁屏歌词) — Live Activity
**Demo content [V]:** 平凡之路 (Ordinary Road) — 朴树 (Pu Shu); also Lover — Taylor Swift (iPad shot).
**Layout (top→bottom) [V+I]:** standard lock screen (large clock ~01:37, date 3月30日 星期六) → Live Activity card:
- Row 1: album art (left, rounded) + song title (bold white) + artist (secondary) 
- Row 2: 2–3 lyric lines, active line brightest, others dimmed [V: "也穿过人山人海 / 我曾经拥有着的一切 / 转眼都飘散如烟"]
- Row 3: thin progress bar; `1:04` left, `-3:57` right **[V]**
- Pause control visible in widget-header position **[V: iPad shot shows ⏸ 暂停]**
**Style:** dark blurred capsule card, white text, continuous radius ~28pt [I]. iPhone shot header: `1:01 / -4:00` **[V]**.
**Marketing tagline [V]:** 在锁屏实时活动显示歌词 — "Display lyrics in the Lock Screen Live Activity."

### S2 — Dynamic Island Lyrics (灵动岛歌词)
**Compact pill [V]:** current line as marquee — 我曾经跨过山和大海 scrolling; black capsule, white ~13–15pt text.
**Expanded island [V]:** stacked bilingual block —
- Active CN line: 我曾经跨过山和大海
- EN translation directly below: "I once crossed mountains and seas."
- Next line preview: 也穿过人山人海
- Source badges: **Music** / **Spotify** [V]
Shown over home screen with Search bar; island coexists with normal home-screen content [V: "perfectly integrated… without affecting other notifications"].

### S3 — Home-Screen Widgets (桌面小组件)
**Demo [V]:** 平凡之路 - 朴树; lines 我曾经跨过山和大海 / 也穿过人山人海; state 播放中 (Playing); control 暂停 (Pause); label 音乐 (Music); app identity 灵动歌词; lyricist credit 词：韩寒/朴树 (iPad large widget).
**Structure [V+I]:** standard iOS widget header row (app icon + 灵动歌词 + status "Playing" + pause button) → body: title/artist line + 1–3 lyric lines. Multiple sizes and styles offered [V: "multiple sizes and styles"]; dark themed over colorful wallpaper **[V: "two dark-themed music widgets on a colorful iPadOS wallpaper"]**.

### S4 — StandBy Mode
**Demo [V]:** All For You — Cian Ducrot; iPhone horizontal on a MagSafe stand; vinyl-style album art beside **large stacked lyric lines**: "I hope that he tries / I hope that he walks you home / every night / I hope that he kisses you ten…"
**Tagline [V]:** "Display cover and lyrics on StandBy." Layout = album art + full-width large typography; biggest lyric type in the app [I]. Auto-shows when device lies flat **[V: listing]**.

### S5 — Floating Lyrics (悬浮歌词)
**Demo [V]:** small translucent card floating over the home screen just above the dock; shows 灵动歌词 + 音乐 source label + current line 我曾经跨过山和大海 (repeated — current-line emphasis).
**Behavior [V]:** adjustable position, always on top, "supports various customizations." Compact pill-like card, blurred material, ~16–20pt radius [I].

### S6 — Full-Screen Lyrics (全屏歌词) — in-app page
**Demo [V]:** Lover — Taylor Swift. Status 14:11 → title + artist at top → scrollable synced lyrics with Chinese translations → active line bold white, inactive "blurred and dimmed" → pastel-purple artwork-blur background **[V]**.
**iPad variant [V]:** dark-themed player; header 全屏歌词 — 查看和搜索完整歌词 ("view and search full lyrics"); chips/labels 灵动岛&锁屏 (Dynamic Island & Lock Screen); full lyric list scrolling (14+ lines transcribed); bottom bar: 平凡之路 - 朴树 + 点击查看完整歌词 ("tap to view full lyrics"); clock 01:43 3月30日周六.
**Search [V]:** tagline confirms search exists on this page — the only search affordance in the app's public UI.

### S7 — Lyrics Translation (歌词翻译)
**Line pairing [V]:** every EN line followed by its CN translation, e.g.:
- But I want them all → 但我渴望的是永恒
- Can I go where you go → 我能否不离不弃随你天涯海角？
- Can we always be this close → 我们能否永远这般亲密无间？
- Forever and ever → 永永远远
- And ah take me out → 啊 带我离开吧
- And take me home → 带我回到我向往已久的家吧

**Language picker [V]:** overlay sheet titled 翻译为: 中文 (zh) ("Translate to: Chinese") listing ≥16 languages with the current one marked: 韩语 (ko), 阿拉伯语 (ar-AE), 越南语 (vi), 西班牙语 (es), 葡萄牙语 (pt), 荷兰语 (nl), 英语 (en-GB), 英语 (en), 泰语 (th), 波兰语 (pl), 法语 (fr), 日语 (ja), 意大利语 (it), 德语 (de), 土耳其语 (tr).
**Source selection [V]:** Spotify, Apple Music, and Shazam icons shown together in the translation marketing shot — provider choice is a first-class step.

### S8 — CarPlay (车载歌词)
**Dashboard variant [V]:** night-driving scene; status 12:56, 0 km/h; map tile (百度地图 Baidu Maps) with ETA 15:19, 到达 (Arrive), 2:23 小时, 161 公里, cue 120米 进入 无名路 ("120m, enter Nameless Rd"); separate **lyrics tile** with bilingual lines: 但若是你能听见我的心声 / "Tell me if you hear me" / 就请告诉我 / 若你能听见我 / "And I should have called".
**Widget variant [V]:** dark CarPlay tile with clock 12:53, album art, playback controls, "All For You - Cian Ducrot", bilingual lines: "Is it too late? Forgive me" / 此时再说请原谅是否已为时过晚? / "Did you mean what you said?" / Are… / 归咎于我.
**Safety copy [V]:** "Please focus on driving… CarPlay lyrics are only for passengers."

### S9 — Shazam Mode (copy-only [V])
Identify music "playing on any app, webpage, or in your surroundings" and view its lyrics. No public screenshot of this flow was found — UI unseen.

### S10 — Lyrics Sharing Cards (copy-only [V])
"Share beautiful lyrics cards effortlessly with friends." No public screenshot of the card editor — UI unseen.

### S11 — Membership / Paywall (copy-only [V])
"Dynamic Lyrics® Membership": unlock all premium features, free future updates, ad-free; subscription OR one-time lifetime; iTunes auto-renew; charged within 24h before period end; cancel ≥24h before renewal; trial auto-converts if not cancelled. Paywall UI unseen in screenshots.

---

## 3. Implied UX flows [I — reconstructed from copy + screenshots]

1. **Setup:** choose music provider (Apple Music / Spotify / Shazam) → grant detection permission → surfaces go live.
2. **Passive listening:** now-playing detected → Live Activity + Dynamic Island appear automatically on lock screen → tap through to full-screen lyrics.
3. **Translation:** open translation feature → language picker sheet → pick target → bilingual lines render on *all* surfaces (island, lock, widget, full-screen, CarPlay).
4. **Share:** generate lyric card → system share sheet.
5. **Monetize:** membership paywall (subscription vs lifetime toggle), trial → auto-renew.

---

## 4. Copy deck (verbatim strings, EN ⇄ CN)

| CN | EN |
|---|---|
| 锁屏歌词 | Lock Screen Lyrics |
| 在锁屏实时活动显示歌词 | Display lyrics in the Lock Screen Live Activity |
| 灵动岛歌词 | Dynamic Island Lyrics |
| 桌面小组件 | Home-Screen Widgets |
| 在主屏幕显示实时歌词 | Show real-time lyrics on the home screen |
| 悬浮歌词 | Floating Lyrics |
| 在任何地方显示悬浮歌词 | Show floating lyrics anywhere |
| 全屏歌词 | Full-Screen Lyrics |
| 查看和搜索完整歌词 | View and search full lyrics |
| 歌词翻译 | Lyrics Translation |
| 翻译为: 中文 (zh) | Translate to: Chinese (zh) |
| 车载歌词 | CarPlay Lyrics |
| 灵动歌词 | Dynamic Lyrics (app name) |
| 播放中 | Playing |
| 暂停 | Pause |
| 音乐 | Music |
| 灵动岛&锁屏 | Dynamic Island & Lock Screen |
| 在听吗 | Are you listening? |
| 点击查看完整歌词 | Tap to view full lyrics |
| 词：韩寒/朴树 | Lyrics: Han Han / Pu Shu |
| 到达 | Arrive |

Demo songs: 平凡之路 (Ordinary Road) — 朴树 (Pu Shu) · Lover — Taylor Swift · All For You — Cian Ducrot.

---

## 5. Borrowable patterns & gaps (for Caraoke)

**Worth borrowing [I]:**
1. **One lyric engine, many surfaces** — identical active/inactive/translation rules scaled per context. This consistency is the product.
2. Negative remaining time (`-3:57`), thin progress bar, elapsed-left/remaining-right.
3. Source badge (Music/Spotify) inside expanded island + widget headers.
4. iOS widget header pattern: app icon + name + live status ("Playing") + play control.
5. Translation under active line only in compact surfaces; full pairing in full-screen.
6. Artwork-derived adaptive backgrounds in-app; fixed dark materials on system surfaces.
7. Marketing discipline: one screenshot per surface, header + one-line tagline.

**Gaps = differentiation room for Caraoke [I]:**
- **No word-level karaoke highlighting observed anywhere** — line-level only. A karaoke app can own word-by-word fill.
- Floating window emphasizes by *repeating* the current line rather than animating it.
- No visible theming/font customization for lyric surfaces in public UI (customization claimed in copy, never shown).
- Paywall, Shazam flow, and share-card editor are invisible in marketing — no design reference exists for them publicly.

---

## 6. Source image URLs

US storefront (iPhone): `…/6e293aae…__U9501_U5c4f_U6b4c_U8bcd@3x.png` (lock) · `…/f6627788…__U684c_U9762_U5c0f_U7ec4_U4ef6@3x.png` (widget) · `…/8690c652…__U60ac_U6d6e_U6b4c_U8bcd@3x.png` (floating) — base `https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/…`
CN storefront (8 iPhone shots incl. CarPlay, translation ×2, StandBy) and JP storefront (8, incl. Dynamic Island) — retrieved via `https://itunes.apple.com/lookup?id=6476125287&country=cn|jp` → `screenshotUrls`.
iPad set: lock / widget / floating / full-screen (US `ipadScreenshotUrls`).
Website images: `https://musiclyrics.cn/img/` → 锁屏歌词.png, 灵动岛歌词.png, 桌面小组件.png, 悬浮歌词.png, 全屏歌词.png, 歌词翻译.png, Standby.png, CarPlay首页歌词.png, CarPlay小组件.png.
