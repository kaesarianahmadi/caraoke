# Caraoke App Store Optimization (ASO) & Marketing Readiness

**App:** Caraoke  
**Target:** unreleased local audit after build 84
**Status:** not submission-ready; device, policy and service gates remain.
**Compliance baseline:** App Store Review Guidelines 2.1, 2.3 and 2.5.4.

---

## 1. App Store Metadata Spec

### App Title (Max 30 chars)
`Caraoke: Live Car Lyrics` *(24 / 30 chars)*

### Subtitle (Max 30 chars)
`Live Lyrics for Road Trips` *(26 / 30 chars)*

### Keywords (Max 100 chars, comma-separated, deduplicated)
`karaoke,car lyrics,carplay lyrics,sing along,road trip,lyrics,live activity,music lyrics,passenger` *(98 / 100 chars)*

### Promotional Text (Max 170 chars)
`Turn every road trip into a sing-along. Synchronized real-time lyrics stream straight to your Lock Screen and Dynamic Island. Designed for car passengers.` *(154 / 170 chars)*

### Primary / Secondary Categories
- **Primary:** Music
- **Secondary:** Entertainment

---

## 2. App Store Full Description

```text
Turn every drive into a concert. Caraoke streams synchronized, real-time lyrics right to your iPhone Lock Screen and Dynamic Island, letting passengers sing along without fumbling through music apps.

WHY CARAOKE?
• Real-Time Sync: Lyrics advance beat-for-beat with your music.
• Glanceable Design: High-contrast typography designed specifically for vehicle viewing.
• Lock Screen & Dynamic Island: See what's coming next without unlocking your device.
• Multi-Service Integration: Works with Apple Music and Spotify playback.
• Passenger First: Designed for road trip co-pilots, road-trippers, and family sing-alongs.

PASSENGER SAFETY & VEHICLE GUIDELINE NOTICE:
Caraoke display surfaces are designed exclusively for vehicle passengers. Drivers must keep eyes on the road and hands on the wheel at all times.

SUBSCRIPTION & TERMS:
Caraoke Premium unlocks unlimited real-time lyric streaming, custom themes, and ad-free playback. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current billing cycle in your Apple ID account settings.

Privacy Policy: https://caraoke.app/privacy
Terms of Service: https://caraoke.app/terms
Support: support@caraoke.app
```

---

## 3. What's New / Release Notes (Build 65)

```text
Unreleased local changes:
• Refined phone layout, readable lyric segmentation and offline help.
• Repaired selected-player resync and stale overlapping Spotify responses.
• Improved purchase disclosures, localized pricing and error feedback.
• Locked-phone sync and CarPlay latency still require device acceptance.
```

---

## 4. App Store Reviewer Testing Instructions (Guideline 2.1)

```text
TESTING INSTRUCTIONS FOR APP STORE REVIEW:
Caraoke synchronizes lyrics with currently playing audio for car passenger viewing via Live Activities and Dynamic Island.

Set up while parked, or test on an iPhone without a vehicle:
1. Launch Caraoke; Home gear → Connect music → choose the active music source.
2. Start a song in Apple Music, or connect an authorized Spotify account.
3. Turn on Live Lyrics; permit Live Activities in iOS Settings → Caraoke.
4. Open the phone lyrics page; its Resync samples playback and restarts updates.
5. Lock the phone; verify the Live Activity, track changes, pause/resume and seeks.
6. On touchscreen CarPlay, verify each widget resync and transport control.

There is no user-accessible Reviewer Demo Mode. Spotify's shared development
credentials require allowlisting; a review-ready service/account arrangement is
still required. Contact: support@caraoke.app.
```

---

## 5. Marketing Readiness Scorecard

| Gate | Current evidence | Required before submission |
|:---|:---|:---|
| Local core/syntax | 318 standalone checks passed; iOS syntax parsed | CI iOS typecheck/build after release authorization |
| Phone UI / CarPlay | Native compact-renderer snapshots only | iPhone Dynamic Type, navigation and real head-unit validation |
| Locked-phone sync | Resync/stale-state defects repaired locally | Multi-track locked drive, repeated resync, calls/Siri, offline recovery |
| Sentry hangs | Build-84 hang/watchdog issues unresolved | Device investigation; do not suppress or claim fixed |
| Relay | Worker route reachable only | Verify APNs configuration and delivery on device |
| Purchases | Pricing/disclosures/error paths repaired locally | Sandbox purchase, cancellation, pending, restore, storefront prices |
| Privacy | Public policy contradicted SDK/relay behavior | Review and publish corrected disclosures; align App Privacy answers |
| Background mode | Inaudible audio keep-alive exists | Resolve App Review 2.5.4 policy risk before submission |
| Providers / Spotify | LRCLIB + YouTube Music; Spotify limited beta | Content rights, provider terms and production service access clearance |

No App Store approval, zero-truncation guarantee or continuous background-sync
guarantee follows from local tests. Build number unchanged; nothing pushed.
