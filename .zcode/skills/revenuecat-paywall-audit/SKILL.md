---
name: revenuecat-paywall-audit
description: Audits In-App Purchases, paywall UI, and RevenueCat integration for Apple App Store Guideline 3.1.1 and 3.1.2 compliance. Verifies Restore Purchases button, EULA terms, Privacy Policy links, StoreKit error handling, and dynamic pricing display. Use when modifying or reviewing paywalls, subscription models, or purchase logic.
---

# RevenueCat & Paywall Compliance Audit

App Store Guideline 3.1.1 & 3.1.2 compliance guide for RevenueCat and StoreKit integrations.

## 1. Guideline 3.1.2 Auto-Rejection Rules

- **Restore Purchases Button:**
  - Must be visible and functional on every paywall screen.
  - Must display feedback to the user on completion (success, nothing to restore, or error). Never fail silently.
- **Terms of Use (EULA):**
  - Must have a clickable "Terms of Use" link on the paywall screen.
  - Default Apple EULA (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`) or custom URL.
- **Privacy Policy:**
  - Must have a clickable "Privacy Policy" link on the paywall screen.
- **Transparent Pricing & Terms:**
  - State renewal terms clearly (e.g., "$9.99/year, auto-renews until canceled").
  - Use dynamic StoreKit product strings (`product.localizedPriceString`), not hardcoded currency symbols.

## 2. Technical Architecture & Edge Cases

- **Offline / StoreKit Unreachable:**
  - Paywall must show retry button or cached offerings if `Purchases.shared.getOfferings` times out.
  - App must not crash or freeze if internet is absent during launch.
- **Transaction State Restoration:**
  - Listen to `PurchasesDelegate` updates across app launches.
  - Do not gate basic app navigation behind purchase loading.
- **Entitlement Checks:**
  - Check entitlement ID cleanly:
    ```swift
    customerInfo.entitlements["pro"]?.isActive == true
    ```
  - Graceful downgrade when subscription expires or is revoked.

## 3. Paywall Verification Checklist

- [ ] "Restore Purchases" present, clickable, and shows feedback.
- [ ] Direct link to Privacy Policy on paywall.
- [ ] Direct link to Terms of Use (EULA) on paywall.
- [ ] No hardcoded dollar amounts in UI text.
- [ ] Loading indicator displayed during transaction processing.
- [ ] App Store sandbox test account restores and cancels cleanly.
