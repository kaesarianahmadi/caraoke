# Caraoke — Developer Name on App Store: Solo vs Company (Indonesia)

> Decision doc for: "Should I ship with my personal name, or set up a business so the
> App Store shows a company name?" Written for the user as a solo dev in Indonesia on an
> **individual** Apple Developer account. No code involved — enrollment/entity/app-transfer
> decisions. **Decide BEFORE first submission** (transfer gets harder after launch).

## 1. What determines the name you see

**Who owns the Apple Developer Account decides the seller name:**

| Account type | Public "Developer" name shown | Requirements |
|---|---|---|
| **Individual** (current) | **Your legal name** (e.g. "Kaesarian Ahmadi") | None beyond the $99/yr account |
| **Organization** | **Legal entity name**, optionally a **DBA** (trade name) | Registered entity + **D-U-N-S number** + entity docs; wait ~2–4 weeks |

- You **cannot** put a made-up brand name on an individual account — Apple verifies the
  legal name.
- On an Organization account you *can* have the public name be a **DBA/business name**
  (e.g. "Caraoke Studio") rather than the PT's formal name — but the underlying
  enrollment is still the entity.

## 2. Realistic paths (Indonesia)

### Path A — Ship now as Individual (zero delay, $0)
- Developer name = your legal name.
- **This is completely normal** for solo indie apps; users don't penalize it.
- You can still brand the *app name / listing* ("Caraoke: Live Lyrics") — the app name is
  not the developer name.

### Path B — Register PT Perorangan (one-person company) → new ORGANIZATION account → transfer app
1. Register **PT Perorangan** via OSS (UU Cipta Kerja) — locally ~IDR 500k–2jt + days.
2. Enroll as **Organization** Apple Developer ($99/yr): needs company documents +
   **D-U-N-S number** (Apple can issue free during enrollment, takes time) → wait for
   verification.
3. **App Transfer** from the individual account to the org account (both must be
   eligible; moves app record, ratings/reviews; **subscriptions and IAPs require care** —
   usually fine if no active paid-subscriber base yet).
4. Result: developer name = PT name (or DBA).

### Path B' — Same, but keep the account Individual + use a trade name? 
Apple generally does **not** allow a DBA on individual accounts. If the brand name is the
goal, it must be an Organization account (Path B). No shortcut.

## 3. Cost/effort trade-off

| | A: Individual now | B: PT Perorangan + org account |
|---|---|---|
| Developer name shown | Legal name | PT / DBA name |
| Time to launch | **Now** | + ~3–6 weeks (entity, D-U-N-S, enrollment, transfer) |
| Money | $0 extra | Entity fee + $99/yr org enrollment |
| App Transfer risk | none | Moderate — do it **before first submission** |
| Can do later? | Yes — transfer post-launch possible | — |
| Best for | "Get it live, build reputation" | "Brand day-one, investor/co-founder ready" |

## 4. My recommendation

- **For MVP & the next few months: Path A.** Ship as individual; the app name does the
  branding. No moving parts, no delay, and your money isn't gated behind an entity.
- **If brand-on-day-one matters** (e.g. you plan to co-found, or you dislike seeing your
  name publicly): start **Path B now** (entity + D-U-N-S run in the background while the
  design work happens) and do the **app transfer before final submission** — then
  everything (IAP group/products) lives on the org account from the start.
- Revisit after launch: transferring later is possible, but doing it pre-submission is
  dramatically cleaner (no active-subscriber migration).

> **Action if you choose A:** nothing changes, we proceed.
> **Action if you choose B:** register the PT first (one form on OSS), then we start the
> org enrollment — I can prep the D-U-N-S/Apple-verification checklist when you're ready.