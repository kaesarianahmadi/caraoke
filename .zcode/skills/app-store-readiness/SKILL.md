---
name: app-store-readiness
description: Checklist and compliance verification for iOS App Store submission. Audits Info.plist privacy usage descriptions, export compliance encryption keys, demo account and reviewer notes, Privacy Manifests, and Guideline 2.1 / 2.3 checks. Use when preparing, reviewing, or debugging App Store submissions or metadata.
---

# App Store Submission Readiness

Comprehensive pre-flight audit for iOS App Store submission compliance.

## 1. Critical Rejection Traps

- **Export Compliance:** `ITSAppUsesNonExemptEncryption` must be `NO` in `Info.plist` (avoids French encryption declaration gate).
- **Missing Purpose Strings:** Any accessed system framework requires human-readable, non-generic descriptions:
  - `NSAppleMusicUsageDescription`: Explain music library access for song matching.
- **Guideline 2.1 (App Completeness & Reviewer Access):**
  - App Store reviewers do not drive cars or connect real CarPlay head units.
  - Reviewer notes must provide explicit instructions or demo mode toggle to simulate playing music and displaying lyrics.
- **Guideline 2.3 (Accurate Metadata):**
  - Never advertise native CarPlay standalone UI if lyrics are displayed via Lock Screen / Live Activity / Widgets.
  - State passenger orientation explicitly in copy.

## 2. Privacy Manifest (`PrivacyInfo.xcprivacy`)

Required for third-party SDKs (RevenueCat, telemetry) and required reason APIs:
- `NSPrivacyTracking`: Set `false` if no cross-app tracking.
- `NSPrivacyTrackingDomains`: Empty array if no tracking.
- `NSPrivacyCollectedDataTypes`: List purchase history (RevenueCat), app diagnostics/crash data.
- System Boot Time / File Timestamp / User Defaults: Ensure required reason codes are declared if SDKs touch them.

## 3. Reviewer Notes Template

```text
TESTING INSTRUCTIONS FOR REVIEWER:
Caraoke provides synchronized lyrics for car rides (Lock Screen & Dynamic Island).
1. Connect via Apple Music or use Demo Mode to simulate track playback.
2. Tap "Start Ride Mode" to activate the Live Activity lyric stream.
3. Reviewer test credentials (if applicable): [Provided here]
4. Direct contact: [Support Email / Phone]
```

## 4. Submission Checklist

- [ ] `CURRENT_PROJECT_VERSION` incremented.
- [ ] Privacy Policy URL live and matching metadata.
- [ ] Support URL live with working contact email.
- [ ] Reviewer demo mode / offline playback verified.
- [ ] No hardcoded secrets, test API endpoints, or debug overlays active.
