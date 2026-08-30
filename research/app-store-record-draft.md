# App Store Record — Submission Draft (Phase D prep)

Paste-ready content for App Store Connect. Full details verified against the
project state (brand, pricing, surfaces). Complete the bracketed fields with
your launch date / link specifics.

## Identity

| Field | Value |
|---|---|
| App name | **Caraoke: Live Lyrics** |
| Subtitle | **Lyrics for the ride.** |
| Primary category | **Music** |
| Secondary category | (optional) None |
| Bundle ID | `app.caraoke.ios` (+ `app.caraoke.ios.widgets` extension) |
| Price base | US storefront: $1.99 / $11.99 / $20 lifetime (other storefronts auto-convert; override only where you have data) |
| App icon | 1024×1024 per `research/app-icon-screenshot-specs.md` |

## Description

> **Every ride has a chorus — see it on CarPlay.**
>
> Caraoke puts the current lyric line on your car's CarPlay screen through a
> Live Activity, so the whole car can follow along. Tap Start Ride Mode before
> you pull out. When the song starts, the words follow — no passing the phone
> around, no scrolling, no setup mid-drive.
>
> **How it works**
> • Connect Apple Music or Spotify.
> • Tap Start Ride Mode.
> • Caraoke reads what's playing and shows the current line (plus the next
>   one) on CarPlay, the Lock Screen, and the Dynamic Island.
> • CarPlay is glanceable and non-interactive — designed to keep eyes on the
>   road.
>
> **Made for road trips** — friends, couples, family, and the passenger seat.
> Works with the music you already play.

## Keywords (≤100 chars)

```
carplay,lyrics,sing along,road trip,car karaoke,live lyrics,passenger,music
```
(75 chars, room to spare.)

## What's New (first release)

```
Ride Mode, live lyrics on CarPlay, Apple Music + Spotify, lifetime option.
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
  Spotify Web API (OAuth 2.0 + PKCE, read-only scopes). The app never plays or
  modifies audio; it only reads the now-playing state.
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
  subscriptions ($1.99/mo, $11.99/yr) + a non-consumable lifetime ($20).

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
   `caraoke.plus.yearly` ($11.99) + non-consumable `caraoke.plus.lifetime`
   ($20); set US as base storefront, enable all storefronts by default.
3. Fill Privacy, Age Rating, Export Compliance, Support URL
   (GitHub Pages `https://<you>.github.io/caraoke/`), and the legal URLs
   (`site/privacy.md`, `site/terms.md` drafts ready to publish).
4. Add App Store Connect **API key** (Users and Access → Integrations) —
   Issuer ID + Key ID + `.p8` — so CI can upload TestFlight builds.
5. Set the version, paste this description/keywords, and upload screenshots
   from OpenDesign per `research/app-icon-screenshot-specs.md`.
