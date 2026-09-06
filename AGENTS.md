# AGENTS.md
- Do not preserve backward compatibility. Remove obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- Choose the simplest implementation that fully meets the current requirements. Avoid speculative abstractions, configuration, and indirection.
- Grow the system in layers. Start from the smallest version that works end to end, and add each new capability on top of a product that already works. Never trade a working product for unfinished complexity.
- Keep components modular and concerns clearly separated.
- Prefer established, well-maintained libraries when they reduce overall complexity or improve reliability. Do not reimplement common functionality without a clear reason.
- Lean on the dependencies already in the project before writing your own implementation or adding packages. Do not assume a library lacks a capability without checking its documentation and types.
- Make architectural decisions for the long term. Do not accept a stopgap that only works for now and is meant to be replaced later.

## Staff & Souls
- **Chief of Staff (Josh):** `.agents/chief-of-staff.soul.md` — Single user interface, orchestrator, review authority. Model: session model (`3.8-flash-ag`).
- **Axel (SwiftUI Feature Builder):** `.agents/swiftui-builder.soul.md` — UI layout, Dynamic Island, ActivityKit. Model: `ag/gemini-3.8-flash-high` (fast layout) / `holver-ai/qwen-3.8-max` via `router9` (heavy logic). Skills: `swiftui-patterns`, `make-interfaces-feel-better`.
- **Vance (Silent Failure Hunter):** `.agents/silent-failure-hunter.soul.md` — Swallowed errors, decode failures, APNs edge cases. Model: `cmc/deepseek/deepseek-v4-pro`. Skills: `error-handling`, `swift-protocol-di-testing`.
- **Ward (Store & Security Gatekeeper):** `.agents/store-security-gatekeeper.soul.md` — Secret leaks, App Store guidelines, Keychain. Model: `gcli/grok-4.6`. Skills: `security-review`.
