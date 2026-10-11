# Caraoke App Store Optimization (ASO) & Marketing Readiness

**App:** Caraoke  
**Target Release:** Build 65 (iOS)  
**Author:** Scout, Product & Marketing Specialist  
**Reviewed For:** Zee (`@zee`), Principal Engineer  
**Compliance Baseline:** App Store Review Guidelines 2.1 & 2.3, Apple Car Safety HIG

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
Build 65 — Stability & Surface Overhaul:
• Overhauled Live Activity lyric engine with rock-solid background sync and reduced memory footprint.
• Added full-page lyric view with smoother line transitions.
• Refined 2x4 and 4x4 Home Screen widgets for balanced typography and zero truncation.
• Fixed mid-flight lyric transition collisions.
```

---

## 4. App Store Reviewer Testing Instructions (Guideline 2.1)

```text
TESTING INSTRUCTIONS FOR APP STORE REVIEW:
Caraoke synchronizes lyrics with currently playing audio for car passenger viewing via Live Activities and Dynamic Island.

To review without a physical vehicle:
1. Launch Caraoke on iPhone.
2. Under Settings / Diagnostics, toggle "Reviewer Demo Mode" to simulate active track playback without external music subscription logins.
3. Tap "Start Ride Mode" on Home to start the Live Activity.
4. Lock the device to view synchronized lyrics on the Lock Screen.
5. Expand the Dynamic Island on supported hardware to verify compact lyric tracking.

Reviewer Test Account:
- Demo Mode: Pre-configured, zero-login required
- Contact: zee@kawstudios.com / scout@kawstudios.com
```

---

## 5. Marketing Readiness Scorecard

| Deliverable | Status | Location / Artifact | Notes |
|:---|:---:|:---|:---|
| **Organic Playbook** | READY | `marketing/caraoke-marketing-playbook.html` | Viral TikTok/Reels zero-budget acquisition strategy |
| **ASO Metadata** | READY | `marketing/aso-readiness.md` | Title, Subtitle, Keywords, Description, Promo text within Apple bounds |
| **Reviewer Package** | READY | `marketing/aso-readiness.md` Sec 4 | Guideline 2.1 simulated playback instructions |
| **Guideline 2.3 Compliance** | PASSED | Copy specifies Lock Screen / Live Activity passenger focus; avoids false CarPlay claims |
| **Export Compliance** | PASSED | `Info.plist`: `ITSAppUsesNonExemptEncryption = false` | No French declaration requirement |
| **Safety Disclaimers** | PASSED | Passenger-only explicit warnings embedded in description and onboarding |

---

## 6. Recommendations for Engineering (`@zee`)
1. Ensure the "Reviewer Demo Mode" button is accessible in debug and TestFlight builds for Guideline 2.1 pass.
2. Confirm Privacy Policy and Support URLs resolve before final App Store Connect metadata push.
