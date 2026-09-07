# Multi-Agent Harness Architecture & Post-Mortem Brief

## 1. Project Background (Sanitized)
- **Target Application:** Production-grade iOS client application written in modern Swift / SwiftUI, integrating system push notifications, background tasks, external relay communications, Live Activities / ActivityKit, and local storage.
- **Current Completion Stage:** ~70% complete. Core features, backend relay integration, and TestFlight CI/CD pipelines (via GitHub Actions and fastlane/xcodebuild) are established and verified on physical devices.
- **Remaining Scope:** Edge-case crash handling, error resilience, APNs synchronization hardening, UI/UX polish, performance profiling, and App Store submission compliance.
- **Core Problem:** Progress slowed down drastically not because of iOS complexity, but because of friction in the autonomous multi-agent orchestrator setup.

---

## 2. DeepSeek Harness (DSH) System Architecture
- **Host Runtime:** Local Node.js / TypeScript environment with Web GUI running at `127.0.0.1:3080`.
- **Sandbox & Execution:** Local filesystem sandbox (`workspace-write`), terminal bash tool (`bash -c` fresh shells), structured filesystem tools (`read`, `edit`, `write`, `glob`, `grep`).
- **Memory Subsystem (Mnemon):**
  - Hot runtime memory injected into system context via Markdown projections (`MEMORY.md` for project facts/conventions, `USER.md` for user preferences).
  - Managed cold Document store with semantic keyword retrieval (`mnemon_document_search`, `mnemon_recall`).
- **Native Multi-Agent Primitives:**
  - `subagent`: Spawns isolated child agent in background or foreground; returns final output to parent.
  - `subagent_fork`: Spawns child agent seeded with conversation turn history.
  - `workflow`: JavaScript programmatic orchestrator script for batch/pipeline agent dispatch.
  - `ralph`: Fresh-agent iteration loop using shared disk as state.

---

## 3. The Attempted Multi-Agent Implementation ("Chief of Staff" OS)
To scale beyond a single context window and prevent token degradation, a custom multi-agent organization was implemented on top of DSH:

### Roles & Topology
- **Chief of Staff (Orchestrator):** Single user-facing agent in the active DSH session (Model: `3.8-flash-ag`). Responsible for intake, task planning, delegating to specialists, reviewing diffs, and communicating with the user.
- **SwiftUI Feature Builder:** Specialized worker for layout, animations, and UI states (Models: Gemini 3.8 Flash / Qwen 3.8 Max via 9router).
- **Silent Failure Hunter:** Specialized worker for error handling, network edge cases, Swift concurrency, and decoding failures (Model: DeepSeek V4 Pro via 9router).
- **Store & Security Gatekeeper:** Specialized worker for App Store guideline auditing, secret leaks, and security compliance (Model: Grok 4.6 via 9router).

### Supporting Infrastructure
- **Proxy Router (`9router`):** Local proxy running at `127.0.0.1:20133` aggregating multiple OAuth accounts and API providers (Google Cloud Code, Grok, DeepSeek, OpenRouter).
- **Dashboard Feedback Server:** Node.js HTTP service on `127.0.0.1:3088` injecting structured turn-1 prompts with strict role definitions into new DSH sessions.
- **External Dispatch Hook (`staff_caller.mjs`):** Script executed via bash by the Chief agent to query external models through 9router, writing telemetry receipts to `dashboard.json`.
- **Strict Protocol Rules:**
  1. *Zero Solo Coding:* Chief agent was explicitly forbidden from editing `.swift` files directly.
  2. *Mandatory Dispatch:* Chief was forced to dispatch tasks to worker scripts in Turn 1 before taking actions.
  3. *Single-Voice Identity Lock:* Worker agents had no independent user-facing presence; Chief ingested and re-summarized their outputs.

---

## 4. Failure Modes & Friction Points

### A. Meta-Tooling & Proxy Instability
- **Port Reversions & Process Collisions:** `9router` hardcoded default fallback ports in bundled chunks, frequently requiring automated patch scripts and LaunchAgents to keep proxies aligned.
- **Provider Account Validation Errors:** Cloud provider upstream risk-detection triggered HTTP 403 `VALIDATION_REQUIRED` errors across OAuth accounts, cascading into 2-minute backoff model locks during active development.
- **High Operational Overhead:** More engineering effort was spent fixing proxy ports, refreshing OAuth tokens, maintaining LaunchAgents, and debugging wrapper scripts than writing application code.

### B. High Latency and Multi-Hop Serialization
- **Synthetic Orchestration:** Because workers were called via external Node scripts (`staff_caller.mjs`) inside a single agent turn, every small fix required:
  `Chief analyzes -> runs bash -> calls 9router -> waits for remote LLM -> logs telemetry -> parses response -> verifies with second worker -> finally applies edit`.
- A 30-second single-line Swift fix often took 3–5 minutes across multiple LLM round-trips.

### C. Workspace Concurrency & State Clashing
- **Single Working Directory:** All workers and orchestrators targeted the exact same workspace directory. Without file-level or git-level branch isolation, simultaneous edits caused file conflicts and overwritten changes.
- **Serialization Fallback:** To avoid race conditions, tasks had to be executed sequentially, negating the throughput benefit of parallel multi-agent swarms while retaining all the token and orchestration costs.

### D. Token Bloat & Repetitive Re-hydration
- Turn-1 contracts, soul prompt definitions, skill guidelines, and dashboard schemas consumed 4,000–6,000 tokens of input overhead per session turn before any user problem was evaluated.
- Context had to be repeatedly summarized or manually passed to external workers who lacked repository-wide semantic index awareness.

### E. Architectural Impedance Mismatch
- DSH natively provides internal subagent primitives (`subagent`, `workflow`), but the custom architecture bypassed them in favor of external bash-invoked scripts calling `9router`.
- The system was caught in an uncanny valley: neither leveraging clean native DSH primitives nor running a fully distributed external multi-agent framework.

---

## 5. Current State of the iOS Application
- **Build Status:** Compiles cleanly via `xcodebuild` and CI; fastlane delivers TestFlight builds reliably.
- **Stability:** Core engine, background processing, and UI flow functional; remaining tasks are localized bugs, state race conditions, and UI polish.
- **Development Bottleneck:** The multi-agent harness overhead has become the primary bottleneck slowing down app delivery.

---

## 6. Migration Dilemma & Evaluation Request
The project faces two distinct paths:

### Path 1: Consolidate & Simplify within Current Setup
- Strip away the custom `.agents/` multi-agent proxy architecture, soul prompts, and dispatch scripts.
- Operate with a single focused agent (or native DSH subagents) directly interacting with `xcodebuild`, git, and the codebase.
- Finish the remaining 30% of the iOS app and ship to the App Store before re-evaluating multi-agent frameworks.

### Path 2: Migrate to a Dedicated Multi-Agent Harness
- Migrate the codebase out of DSH into a harness designed specifically for autonomous or parallel agent workflows:
  - **Claude Code:** Native git worktree isolation, subagents, background sessions, task synchronization.
  - **Pi:** Minimal, extensible programmable substrate for custom orchestrators.
  - **OpenHands / Cline / OpenCode:** Dedicated multi-agent servers with scheduling and role segregation.
- Risks of Path 2: Context switching overhead, learning curve, setting up macOS / Xcode / Simulator build bridges, potential delays in publishing the app.

---

## 7. Key Questions for AI Analysis
1. Given that an iOS application is already ~70% complete and verified on TestFlight, does migrating to a multi-agent harness now yield positive ROI, or is it a distraction from shipping?
2. If parallel multi-agent development is used for iOS, how should isolated compilation environments (e.g., Xcode `DerivedData`, concurrent iOS Simulator instances, git worktrees) be architected to prevent build collisions?
3. If migration is warranted, which specific harness architecture provides the lowest setup friction and highest reliability for autonomous issue resolution and overnight PR generation?
