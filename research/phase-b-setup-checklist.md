# Phase B — Setup Checklist (your two accounts + one push)

Everything code-side is ready (`​.github/workflows/ci.yml` runs the full suite
on GitHub's macOS cloud the moment the repo exists). Three actions unlock it.

## 1. Apple Developer Program (the $99 gate — everything depends on this)

1. https://developer.apple.com/programs/enroll/ — enroll as an **Individual**
   (simplest; the app publishes under your name — an Organization needs a
   registered business entity + D-U-N-S).
2. Apple ID verification + identity check: typically approved in 24–48 h.
3. After approval, tell me — I'll prep the App Store Connect record details
   (bundle ID `app.caraoke.ios` or similar, IAP products, privacy answers).

## 2. Spotify developer app (needed for the Spotify you insisted on)

1. https://developer.spotify.com/dashboard → Create app:
   - Name: `Caraoke` · Redirect URI: `caraoke://callback`
   - APIs: Web API · Scopes we use: `user-read-currently-playing`,
     `user-read-playback-state`
2. Copy the **Client ID** into `CaraokePOC/iOS/Resources/Secrets.plist`
   (copy `Secrets.example.plist`; the file is gitignored).
3. Submit the extended-quota request (draft ready:
   `research/spotify-quota-request-draft.md`). Approval takes days–weeks —
   this is why we start now, before launch.

## 3. GitHub repo (I take over after step 1 of this)

**Option A — install GitHub CLI, then hand control to me:**
```sh
brew install gh
gh auth login          # browser flow
```
Then tell me "repo it" — I create the private repo, push the baseline, and
watch the first CI run myself.

**Option B — manual, no tools:**
1. github.com/new → name `caraoke` → **Private** → create (no README).
2. Give me the repo URL (e.g. `https://github.com/<you>/caraoke.git`) — I'll
   push. Pushing needs credentials: either
   - a **Personal Access Token** (github.com/settings/tokens → classic, `repo`
     scope) pasted to me, or
   - you run the two commands yourself:
     ```sh
     git remote add origin https://github.com/<you>/caraoke.git
     git push -u origin main
     ```

## 4. What CI gives us immediately

- Full 115-check suite on macOS cloud + `swift test` (XCTest)
- **`CaraokeCore` compiled against the real iOS SDK** — the first true
  ActivityKit-era compile, impossible on this Mac
- Every future commit verified before it touches device testing

## Still pending on this checklist after your actions

- Phase C: TestFlight build on your iPhone + one real-car CarPlay session
  (decides the background-update mechanism — see
  `research/background-update-strategy.md`)
- App Store Connect record + IAP products (after enrollment approval)
- Privacy policy + terms pages (I draft; you host on GitHub Pages for free)
