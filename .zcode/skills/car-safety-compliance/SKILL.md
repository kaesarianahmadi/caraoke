---
name: car-safety-compliance
description: Verification of automotive safety standards, distracted driving compliance, glanceability, high-contrast typography, and passenger disclaimers for in-car iOS apps. Audits audio session routing, navigation prompt coexistence, and hands-free UX patterns. Use when reviewing automotive UI, Ride Mode, or in-car user experience.
---

# In-Car Safety & Distracted Driving Compliance

Guidelines for passing App Store review on car-facing and passenger-facing experiences.

## 1. Regulatory & Review Traps

- **Distracted Driving Rejection:** Apple rejects apps encouraging drivers to interact with or read detailed text on phones while driving.
- **Audience Positioning:** The app must explicitly position itself as a **passenger or parked experience**.
- **Mandatory Disclaimers:**
  - First launch or Ride Mode start must display a passenger safety notice: *"Focus on the road. Lyrics are intended for passengers and parked sing-alongs."*
  - Copy in App Store metadata must reinforce passenger focus.

## 2. In-Car Glanceable Typography & UI

- **Legibility:**
  - Minimum font size for current lyric line: 24pt+ on iPhone screen, 12pt+ in dense widget slots.
  - Active line must use high-contrast foreground (`.white` or bold dynamic color).
  - Upcoming / past lines must be de-emphasized (`.secondary` or 50% opacity).
- **Hands-Free Principle:**
  - No interactive micro-buttons during Ride Mode.
  - Automatic line progression timed to audio; never require manual tapping or scrolling while driving.
  - Large tap targets (min 44×44pt, preferably full-width buttons) for starting and ending Ride Mode.

## 3. Audio & Navigation Coexistence

- **Audio Session Category:**
  - Must not interrupt Apple Maps or Google Maps spoken directions.
  - If maintaining background execution via silent audio, use `.playback` with `.mixWithOthers` option to prevent cutting off the driver's primary music stream.
- **Interruption Recovery:**
  - Handle phone calls, Siri interruptions, and navigation announcements gracefully.
  - Automatically resume sync when route prompts finish.

## 4. Safety Checklist

- [ ] Clear passenger disclaimer shown before Ride Mode starts.
- [ ] Active line readable from passenger seat at arm's length.
- [ ] No required mid-ride manual scrolling or micro-interactions.
- [ ] Primary music and GPS navigation audio uninterrupted.
- [ ] Dark mode contrast verified for nighttime driving conditions.
