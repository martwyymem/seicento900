# Project Instructions for Claude & AI Models

Read [`AGENTS.md`](AGENTS.md) and [`TASKS.md`](TASKS.md) before planning or writing any code.

## Mandatory `TASKS.md` Live-Update Rule

Every model working in this repository **MUST keep [`TASKS.md`](TASKS.md) updated continuously**:
1. **Start / scope change:** Add or update your work under `## Active Now` in `TASKS.md` when you begin a task or its scope changes.
2. **Every milestone:** Check off finished items, move shipped work into `## Shipped Baseline`, add newly discovered follow-ups or playtest items, and document any new invariants as they happen — never wait for someone to ask.
3. **Every commit & release:** Include the `TASKS.md` update in the commit/release so `TASKS.md` always matches `HEAD`.
4. **Parallel subagents:** If multiple subagents share a single checkout, the coordinating parent thread updates `TASKS.md` on their behalf to avoid merge/overwrite collisions; standalone or worktree agents update `TASKS.md` directly.
