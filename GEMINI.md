# Antigravity Workspace Rules: Token Saver Suite

> **Scope**: Active exclusively within this repository workspace (`Caraoke App`) when running in the Antigravity environment.

---

## 1. Output Compression (Caveman Mode - Ultra)
- **Zero Conversational Fluff:** Omit pleasantries, acknowledgments ("Sure", "I'd be happy to", "Understood"), recap intros, and polite closings.
- **High Information Density:** Communicate directly, concisely, and telegraphically. Use short bullet points, direct facts, and minimal connective prose.
- **Direct Responses:** Answer questions with immediate technical answers. Avoid re-summarizing user instructions or files already visible in the workspace.
- **Explain Diff, Not Intent:** When editing code, state the exact change and reason in 1–2 sentences without restating the entire file context.

---

## 2. Minimalist Code Generation (Ponytail Mode - Ultra)
- **YAGNI Extremist:** Solve only the immediate problem specified. Zero speculative abstractions, zero preemptive helper functions, and zero unnecessary indirection.
- **Stdlib & Native First:** Rely on Swift standard library, native Apple frameworks, and existing project modules. Never introduce new packages or helper utilities if existing code can do the job.
- **Deletion over Addition:** Favor removing dead code, trimming unused branches, and keeping code footprints minimal.
- **Surgical Edits:** Apply targeted, minimal contiguous diffs. Do not perform unsolicited refactorings, style reformatting, or aesthetic rewrites of adjacent code.

---

## 3. Tool Output Compression (RTK Discipline)
- **Concise Command Output:**
  - Use terse flags for shell commands: `git status -s`, `git diff --stat`, `git log -n <N> --oneline`.
  - Avoid dumping raw, unbounded terminal outputs. Filter commands with `head`, `tail`, or bounded regex (`grep -m <N>`).
- **Targeted File Inspection:**
  - Avoid reading entire files when inspecting code. Use `view_file` with targeted `StartLine` and `EndLine` slices around the relevant symbols.
  - Do not echo large logs or generated artifacts into context when exit codes or filtered error messages suffice.
