# Phase B — Setup Checklist (updated 2026-08-31, with your 3 questions answered)

Everything code-side is ready (CI runs the full suite + builds the app on
GitHub's macOS cloud once the repo exists). Three actions unlock progress.

## 1. Apple Developer Program — you do NOT need the Apple Developer app

**Important:** the macOS **Apple Developer app** is a convenience/news
companion and is NOT required — and yes, it wants newer macOS than your
Ventura machine, so just skip it. Enrollment and ALL management are web-based
and work fine in Safari on Ventura:

1. Enroll at **https://developer.apple.com/programs/enroll/** (Web, in Safari).
   Choose **Individual** (simplest; Organization needs a D-U-N-S number).
2. After enrollment (~24–48 h approval), everything else happens at:
   - **App Store Connect** — https://appstoreconnect.apple.com (Web):
     app record, IAP products, TestFlight, privacy answers, review submission.
   - **Certificates, IDs & Profiles** — same portal, Web: bundle IDs,
     provisioning.
3. **No Xcode on this Mac is not a blocker.** Builds/signing happen in cloud
   CI. Hand signing to CI with an **App Store Connect API Key**:
   appstoreconnect.apple.com → **Users and Access → Integrations → App Store
   Connect API** → create a key (Issuer ID + Key ID + .p8 download). I wire it
   into the GitHub workflow so the runner produces signed TestFlight builds —
   zero local Xcode required.

> Bottom line: ignore the "macOS incompatible" app; use the web portals + my
> CI workflow. Tell me "enrolled" and I'll generate the App Store Connect
> record details.

## 2. Spotify — exact click-path (web, works on Ventura)

1. **https://developer.spotify.com/dashboard** → log in with your Spotify
   account → **Create app**.
2. Fill: Name **Caraoke**, Description ("shows synced song lyrics in the
   car"), Website (optional), **Redirect URI: `caraoke://callback`**,
   tick **Web API**.
3. On the app page, copy the **Client ID**. (The **Client Secret** is NOT
   needed — Caraoke uses PKCE, a public client, so the secret never ships.
   Keep it private regardless.)
4. Paste the Client ID into
   **`CaraokePOC/iOS/Resources/Secrets.plist`** → replace
   `YOUR_SPOTIFY_CLIENT_ID` in the `SpotifyClientID` key (the file is
   gitignored; a copy already exists with the placeholder).
5. **Extended quota:** on the app page find **"Request extended quota"**
   (a "Quota"/"Development mode" link). Submit the draft from
   `research/spotify-quota-request-draft.md`. Approval takes days–weeks —
   this is why we start now.
6. The two scopes (`user-read-currently-playing`,
   `user-read-playback-state`) are requested by the app at connect time — no
   further dashboard config needed.

## 3. GitHub — YES, connect your OAuth account and I do the rest

GitHub CLI gains the machine access, then I create/push/watch CI myself. One
quick approval from you (no password ever shared):

```sh
# I'll install gh (already running). Then run THIS ONCE — in your Terminal or
# I print the device code for you to enter:
gh auth login
#   → Which host? GitHub.com
#   → Protocol: HTTPS
#   → Authenticate with: Login with a web browser
#   → It prints a one-time CODE; open the URL, click "Next", the browser
#     shows the code, approve the "repo" + "workflow" scopes.
```

That's an OAuth device-flow authorization done by you the human; the machine
then holds a token I can use to:
- `gh repo create caraoke --private --source=. --push`
- watch the first CI run and fix anything the real iOS SDK surfaces

> Prefer tokens? You can instead create a fine-grained PAT
> (github.com/settings/tokens, `repo` + `workflow`) and paste it to me — but
> the device-flow above is cleaner.

## What I'm doing right now in parallel (no action needed from you)

- Installing `gh` (done/background).
- The sync engine is now ported & tested (137/137) — the app-side wiring is
  ready to become a real app the moment there's a device build.
- `Caraoke.storekit`, legal page drafts, CI workflow, xcodegen project all
  committed and waiting.
