# App Store Connect — "Caraoke Plus" IAP Setup Checklist (paste-ready)

> The only missing monetization piece. The app code is DONE and matches these IDs exactly
> (`CaraokePOC/Sources/CaraokeCore/EntitlementModel.swift`). This is pure ASC data entry,
> ~30 minutes, no code changes. Prices are US base; other storefronts auto-convert.

## 0. Prereqs (skip if already done — verify once)

- [ ] Signed **Paid Apps Agreement** (done — build-10 upload requirement) + any
      **banking/tax** info ASC asks for in **Payments & Billing** (Indonesia: no tax form
      needed for the no-revenue/free case; only if revenue starts will banking matter).
- [ ] App record exists: **Caraoke: Live Lyrics** / `app.caraoke.ios` (done).

## 1. Create the subscription group

App Store Connect → **Monetization → Subscriptions** (your app) →

1. **+ Subscription Group** → name it exactly: `Caraoke Plus` (internal reference
   "Caraoke Plus premium"), save.
2. Inside the group, note the **Reference Name** field is editable per subscription
   (used for reporting only).

> Rule (the code depends on it): **both auto-renewable subscriptions must live in the
> same group** so a user switching month ↔ year doesn't get double-billed, and StoreKit 2
> surfaces upgrade/downgrade offers automatically.

## 2. Create the 3 products (IDs are locked — type them exactly)

| Type | Product ID (exact) | Display name / Reference name | Price (US base) | Localization note |
|---|---|---|---|---|
| Auto-Renewable Subscription | `caraoke.plus.monthly` | "Caraoke Plus — Monthly" | **$1.99 / month** | Subtitle: "Try it for a trip" |
| Auto-Renewable Subscription | `caraoke.plus.yearly` | "Caraoke Plus — Yearly" | **$11.99 / year** | Subtitle: "Best value — just $1.00/month" — mark **Recommended** |
| Non-Consumable (one-time) | `caraoke.plus.lifetime` | "Caraoke Plus — Lifetime" | **$20 once** | Display name: "Founding Lifetime"; "limited launch offer" |

Steps per product (App Store Connect → **Monetization → Subscriptions / In-App Purchases**):

- **Auto-renewable subs:**
  1. **+ Subscription** (inside Caraoke Plus group) → choose plan (Monthly / Yearly) →
     create.
  2. **Subscription Details**: fill *Display Name*, *Description* ("Access to Caraoke Plus
     features (live lyrics fully enabled)." — keep simple), *Price* → **Create** the price
     point $1.99 / $11.99 (add all storefronts or let it auto-convert).
  3. **Subscription Localization**: at least English (Primary) — title/subtitle above.
  4. *(Recommended)* Set **Introductory Offer** = "Free Trial" 3 days if you want a trial
     later; can add anytime, even after launch. Not required for MVP.
  5. **Review**: submit the IAP itself for review (IAPs review separately; do this once,
     before or with the build).

- **Non-consumable:**
  1. **+ In-App Purchase → Non-Consumable**.
  2. Reference/Display name "Caraoke Plus — Lifetime", **$20**, localized name
     "Founding Lifetime — one payment, keep Caraoke forever", review submit.

## 3. Verify entitlements wiring (already in code — sanity check only)

```text
CaraokeProducts.all = { caraoke.plus.monthly, caraoke.plus.yearly, caraoke.plus.lifetime }
isEntitled(any of the 3) == true   // one entitlement, any plan grants it
products = Product.products(for: CaraokeProducts.all)   // fetch prices at runtime
Transaction.updates + AppStore.sync()                    // renewals, refunds, restore
```

No code change needed as long as the ASC product IDs match the constants above
**character-for-character**.

## 4. Sandbox testing before launch (recommended, ~1 hr)

1. ASC → **Users and Access → Sandbox** → add a **Sandbox Apple ID** tester (any email
   that's NOT the real Apple ID).
2. On the test device: Settings → App Store → sign out of the production Apple ID,
   sign the device into the **Sandbox tester** account.
3. In Caraoke: open paywall → buy Monthly (sandbox) → verify Home/Settings flips to
   "Caraoke Plus" entitled.
4. Test **renewal**: sandbox renews ~6× faster (a 1-day sub renews every ~5 min).
5. Test **restore** (Settings → Restore purchases) and **Lifetime** purchase.
6. Sign back into the real Apple ID when done.

*(Sandbox IAP uses the same app build — punch both "buy" paths at least once.)*

## 5. Price/consistency double-checks (why these numbers)

- Monthly **$1.99/mo** → "Try it for a trip" (subtitle) — shortest commitment.
- Yearly **$11.99/yr** = $1.00/mo effective → "Best value" + Recommended badge — first
  listed in the paywall per `PaywallContent.plans` order (yearly, monthly, lifetime).
- Lifetime **$20 once** → "Founding Lifetime" + "limited launch offer" footnote.
- These are the **locked Phase A decisions**; changing them later is easy in ASC
  (new price points), but keep the app's fallback literal strings in sync
  (`EntitlementModel.swift` lines 33–49) if you ever change them.

## 6. If a reviewer tests the paywall

Review notes already say the app ships with a bundled demo track; add one line to the
notes: "Paywall uses StoreKit 2 with products caraoke.plus.monthly/.yearly/.lifetime in
the Caraoke Plus subscription group; sandbox purchase steps provided." (Handy, not
required.)