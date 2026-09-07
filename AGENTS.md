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
6. **Security & Deployment Gate:** Secrets and credentials must never be committed to the public repository. Verify build and version bumping (`CURRENT_PROJECT_VERSION` in `project.yml`) before TestFlight CI pushes.
