# App Store Record — Submission Draft (Phase D prep)

Paste-ready content for App Store Connect. Full details verified against the
project state (brand, pricing, surfaces). Complete the bracketed fields with
your launch date / link specifics.

## Identity

| Field | Value |
|---|---|
| App name | **Caraoke: Live Lyrics** |
| Subtitle | **Car Karaoke & Live Lyrics** |
| Primary category | **Music** |
| Secondary category | (optional) None |
| Bundle ID | `app.caraoke.ios` (+ `app.caraoke.ios.widgets` extension) |
| Price base | US storefront: $1.99/mo · $9.99/yr · $14.99 lifetime (anchor $27 strikethrough, 45% off); other storefronts auto-convert, override only where you have data |
| App icon | 1024×1024 per `research/app-icon-screenshot-specs.md` |

## Description

> Every road trip has a chorus. Caraoke brings real-time, word-by-word synced lyrics to your drive so everyone can sing along.
>
> Start Ride Mode before you hit the road. When your music plays, the lyrics follow automatically on your Lock Screen and Dynamic Island. Glanceable, hands-free car karaoke designed for road trips, passengers, and sing-alongs.
>
> **Features**
> • Ride Mode: Hands-free lyrics display designed for mounted phones and passengers.
> • Dynamic Island & Lock Screen: Glanceable current and upcoming lyric lines without touching your phone.
> • Apple Music & Spotify: Connect your favorite music player with one tap.
> • Synchronized Lyrics: Word-by-word tracking timed to every beat.
> • Zero Distraction: High-contrast, glanceable typography built for passengers. No scrolling required.
>
> **Perfect For**
> • Road trips with friends and family
> • Passenger seat karaoke duets
> • Learning the words to your favorite tracks on the commute
>
> *Note: Focus on driving. Caraoke lyrics are designed for passengers and parked sing-alongs.*

## Keywords (≤100 chars)

```
lyrics,car karaoke,road trip,sing along,live lyrics,passenger,music,duet
```
(71 chars, room to spare.)

## What's New (first release)

```
Ride Mode, live lyrics on Lock Screen & Dynamic Island, Apple Music + Spotify, lifetime option.
```

## Promotional text (optional)

> Keep the words on the screen for the whole ride — start Ride Mode before you
> leave.

## App Review notes (submit with the build)

- **Purpose:** displays the user's currently-playing song's synced lyrics as
  an iOS Live Activity, mirrored to the CarPlay Dashboard by the system.
- **No custom CarPlay app, no CarPlay entitlement.** The CarPlay surface is a
  system-rendered Live Activity (`.supplementalActivityFamilies([.small])`).
- **Playback detection:** reads the public MediaPlayer framework's
  `MPMusicPlayerController.systemMusicPlayer` (Apple Music) and the official
  Spotify Web API (OAuth 2.0 + PKCE, read-only scopes). **Spotify connect
  uses a bring-your-own-Client-ID flow:** the user creates their own private
  Spotify app at developer.spotify.com/dashboard (guided in-app, 2–3 min)
  and pastes its Client ID in Settings; authorization then runs entirely
  through Spotify's official OAuth with the token stored in the iOS
  Keychain. The app never plays or modifies audio; it only reads the
  now-playing state. A Spotify Premium subscription (Spotify's requirement
  for Web API access since Feb 2026) is disclosed in the setup UI.
- **Lyrics source:** LRCLIB (lrclib.net), displayed with attribution in
  Settings (Community lyrics via LRCLIB). Requests carry only the track's
  title/artist/duration. No lyrics stored server-side (the app has no server);
  caches on-device only, clearable in Settings.
- **Review demo steps:** 1) Allow Live Activities when prompted. 2) Connect
  Apple Music (or grant Spotify). 3) Tap Start Ride Mode. 4) Play a song in
  Apple Music/Spotify — lyrics appear on the Lock Screen and, on iOS 26, the
  CarPlay Dashboard. The app ships with a bundled demo track for review if no
  music service is available.
- **No account, no sign-in.** Purchases via StoreKit 2: auto-renewable
  subscriptions ($1.99/mo, $9.99/yr, both with a 3-day free trial) + a
  non-consumable lifetime ($14.99, normally $27).

## App Privacy questionnaire (honest mapping)

| Prompt | Answer |
|---|---|
| Does your app collect data? | Yes — but minimal and **not linked to you** |
| Data Not Linked to You | **Product Interaction** (none stored) + **App Functionality**: track metadata (title/artist/duration) is sent in HTTPS requests to the LRCLIB lyrics service to fetch the right lyrics; Spotify OAuth token + playback state stay on-device (Keychain), never transmitted by us |
| Tracking | No |
| Data linked to you | None |
| Age rating | 4+ (no objectionable content; lyrics only) |
| User-generated content | No |
| Contact info | App support email (support@caraoke.app) in the "Support" field |
| Export compliance | Standard (all HTTPS); no encryption beyond TLS — "does not contain encryption exempt under... " → confirm with the standard 5.5.1 answer or the general exemption |

## App Store Connect steps (after enrollment approval)

1. Create the app record (bundle ID `app.caraoke.ios`) + register the widget
   extension bundle.
2. Subscription group "Caraoke Plus": `caraoke.plus.monthly` ($1.99),
   `caraoke.plus.yearly` ($9.99) — each with a 3-day free trial introductory
   offer — + non-consumable `caraoke.plus.lifetime`
   ($14.99, anchor $27); set US as base storefront, enable all storefronts by default.
3. Fill Privacy, Age Rating, Export Compliance, Support URL
   (GitHub Pages `https://<you>.github.io/caraoke/`), and the legal URLs
   (`site/privacy.md`, `site/terms.md` drafts ready to publish).
4. Add App Store Connect **API key** (Users and Access → Integrations) —
   Issuer ID + Key ID + `.p8` — so CI can upload TestFlight builds.
5. Set the version, paste this description/keywords, and upload screenshots
   from OpenDesign per `research/app-icon-screenshot-specs.md`.
