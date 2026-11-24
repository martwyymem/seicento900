# Handoff (2026-11-24, paused at 92% of the 5-hour usage limit; reset 11:10 UTC)

Goal right now: ship **0.5.9** (campaign bug-fix release), push to GitHub, publish the release builds.

## Done on main
- `5587319` release gate `tools/release_gate.sh` + pruned car blend shapes.
- `8d3fc9e` campaign arcade rules (no pits/wear/fuel/safety car, Fiat 4 laps).
- `f680eaf` co-driver calls: jump, 200 to finish / flying finish (narrows needs an `hw` bake).

## Still to merge for 0.5.9
1. Worktree `/Users/martwyymem/.t3/worktrees/Seicento/t3-2f2363b2-180a4868602068d4` (branch `t3/2f2363b2`): commit `7c1a411` (pit timer clamp, always-zoomed minimap, no paint darkening) PLUS an uncommitted edit in `godot/scripts/ui/race_hud.gd` stripping the dead whole-track minimap code. Its full suite was run in the background: log `/private/tmp/claude-501/-Users-martwyymem-Developer-Seicento/730f2050-173f-47f1-be2d-712510039c03/scratchpad/minimap_suite.log` (expect `0 failure(s)` / `exit 0`). If green: commit there, then `git merge --no-ff t3/2f2363b2` on main.
2. Arrows replacing the racing line + BRAKE cue fix: Gemini 4 Neon delegate, branch `t3/dynamic-chevron-line-brake-cue`. Merge when it reports (if it hangs "waiting for run_tests", take it over).

## Ship steps
- `tools/release_gate.sh` on the merged HEAD (all green).
- Bump `config/version` in `godot/project.godot` to 0.5.9, Windows file/product_version 0.5.9.0, macOS version 16 (see memory windows-exe-release); update TASKS.md baseline; commit.
- Push: `git -c credential.helper= -c "credential.helper=!gh auth git-credential" -c "url.https://github.com/.insteadOf=git@github.com:" push origin main` then tag `0.5.9` and push the tag.
- `gh release create 0.5.9 --target <full sha>` with the exe and the zipped app (`ditto -c -k --keepParent`), upload under nohup with retries.

## Running elsewhere (later releases)
Hypercar handling (Opus), campaign from the open world (Opus), A->B sprints (Opus), stage dressing + spectators (Neon). B1 rival car ladder: rerun after the reset (findings in TASKS.md).
