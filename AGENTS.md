# AGENTS.md
- Do not preserve backward compatibility. Remove obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- Choose the simplest implementation that fully meets the current requirements. Avoid speculative abstractions, configuration, and indirection.
- Grow the system in layers. Start from the smallest version that works end to end, and add each new capability on top of a product that already works. Never trade a working product for unfinished complexity.
- Keep components modular and concerns clearly separated.
- Prefer established, well-maintained libraries when they reduce overall complexity or improve reliability. Do not reimplement common functionality without a clear reason.
- Lean on the dependencies already in the project before writing your own implementation or adding packages. Do not assume a library lacks a capability without checking its documentation and types.
- Make architectural decisions for the long term. Do not accept a stopgap that only works for now and is meant to be replaced later.

## Operational Protocol: Direct Senior Engineering
1. **Direct Code Ownership:** The primary session agent owns direct inspection, editing, and compilation of Swift, SwiftUI, relay, and configuration code. Direct use of `read`, `edit`, `write`, and `bash` (`xcodebuild`, `fastlane`, `git`) is standard.
2. **Lean Execution Loop:** On bug reports or feature requests:
   - Read & diagnose problem directly.
   - Apply targeted fix.
   - Verify via `xcodebuild` / test suite.
   - Commit cleanly.
3. **Optional Native Subagents:** Use native DSH `subagent` only when an independent background investigation, deep codebase audit, or parallel research task is genuinely needed without polluting session context.
4. **Skills as Technical Reference:** Consult reference patterns under `.agents/skills/` (`swiftui-patterns.md`, `error-handling.md`, `security-review.md`, etc.) for architectural compliance.
5. **Telegram Integration:** Feedback and bug reports received via `.agents/telegram-bridge/bridge.mjs` route directly into the active session for immediate action.
6. **Security & Deployment Gate:** Secrets and credentials must never be committed to the public repository. **STRICT AUTHORIZATION RULE:** NEVER push to `main`, NEVER trigger CI, and NEVER upload to TestFlight without explicit, unambiguous direct authorization from the user in chat. Document edits, markdown updates, or local fixes must NEVER trigger a push or build bump.

---

## Release Workflow: push to `main` → CI → TestFlight

**STRICT REQUIREMENT: PUSH ONLY WITH EXPLICIT USER AUTHORIZATION.**
- **Never push to `main` autonomously.**
- **Never bump `CURRENT_PROJECT_VERSION` or trigger CI/TestFlight unless the user explicitly commands it in the current turn.**
- **Local edits, documentation fixes, or refactors stay strictly local.**

**This is the only build/verification path. There is no local Xcode and no iOS SDK on this machine (Command Line Tools only). Do not attempt `xcodebuild` locally, and do not claim a build is verified until the CI run is green.**

### Trigger

`.github/workflows/ci.yml` runs on `push` to `main` (and on PRs to `main`). Four macOS jobs (last observed: ~5–6 min total):

| Job | What it proves |
|:---|:---|
| `core-suite` | `swiftc`-built standalone suite + per-file `swiftc -parse` of `iOS/*.swift` |
| `spm-tests` | `swift test` |
| `ios-app-compile` | `xcodegen generate` then full simulator build, no signing |
| `testflight` | Archive → export → **upload to App Store Connect** |

`testflight` is gated by the repo variable `HAS_ASC_CREDENTIALS == 'true'`.

### Required repo secrets (never committed, never echoed)

`ASC_ISSUER_ID` · `ASC_KEY_ID` · `ASC_KEY_P8` · `ASC_DEVELOPMENT_TEAM` · `DIST_CERT_P12` · `DIST_CERT_PASSWORD`

Write access to `main` therefore equals deployment rights, including the ability to land code that the signing workflow runs with those secrets in scope.

### The push procedure

1. **Bump the build number** in `CaraokePOC/project.yml` → `CURRENT_PROJECT_VERSION` (last shipped: `51`, this push is `55`). The workflow does **not** set it; it comes from `project.yml` via xcodegen. A push without a bump reuses the previous number and Apple rejects the upload.
2. Run the local gate (catches only what is checkable locally):
   ```bash
   cd CaraokePOC
   swiftc -Onone -module-cache-path .build/modulecache \
     Sources/CaraokeCore/*.swift Tests/main.swift -o .build/testrunner && .build/testrunner
   for f in iOS/*.swift; do swiftc -parse "$f" || echo "PARSE FAIL: $f"; done
   ```
3. Commit, then push: `git push origin main`.
4. **Watch the run to completion — do not report success early:**
   ```bash
   gh run list --limit 3
   gh run watch <run-id> --exit-status
   gh api repos/kaesarianahmadi/caraoke/actions/runs/<run-id>/jobs \
     --jq '.jobs[] | "\(.name): \(.status) \(.conclusion // "")"'
   ```
5. To read a failure: `gh run view <run-id> --log-failed | grep -aE "error:"`
6. Apple processing adds ~5–30 min after the job's "Completing upload" step before the build appears in TestFlight. That last mile is manual — there are no App Store Connect credentials on this machine.

### Push auth quirk (a 403 here is almost always this)

`git` resolves credentials through `gh`. Two accounts are logged in and **only one has write**:

```bash
gh auth status                 # check FIRST on any 403
gh auth switch --user <account-with-write>
```

`kaesarianahmadi` owns the repo (admin); `presetsdepot` is an added `write` collaborator; `IndahSaniyati` is **read-only**. A 403 reading "Permission … denied to `<account>`" with a perfectly valid repo-scoped token means the active account simply lacks write. Switching accounts is persistent.

### Hard-won constraints — do not repeat these

- **PUSH PERMISSION: NEVER PUSH WITHOUT EXPLICIT USER AUTHORIZATION IN CHAT.** Pushing to `main` triggers TestFlight CI and spends build numbers / CI minutes. Edits, docs, and fixes remain strictly local until the user explicitly says to push.
- **Swift 5.9: `try` cannot appear inside `??`.** `player ?? (try Foo())` fails with *"operator can throw but expression is not marked with 'try'"*. Build 46 died on exactly this. Use an explicit `if let` branch instead.
- **`swiftc -parse` catches syntax only, not types.** A type error compiles clean locally and only surfaces in `ios-app-compile`. Assume anything touching types is unverified until CI says otherwise.
- **A bumped build number must be a *new* number.** If a run's artifact never uploaded, that number is spent — bump again.
- **Report the run id and job conclusions** when a build is pushed; "pushed" is not "shipped".
