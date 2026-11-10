# Handoff: autonomous run of 2026-11-09

Written by the lead agent when the session's usage limit ran low (resets 2026-11-10 00:10 UTC). Delete this file once
the work below is merged.

## State of the main checkout
- `main` at `e39a67b`, nothing committed or pushed in this run.
- The game runs as before: `godot --path godot`. Baseline on `e39a67b`: full suite 51 suites `ok` (3:28).
- Uncommitted, from the windowed QA agent (safe: one comment and three probes, none in the suite):
  - `godot/scripts/ui/retro_pipeline.gd` (stale "heat haze" comment fixed)
  - `godot/tests/_retro_shots.gd` (uses the save guard)
  - `godot/tests/_qa_race_buttons.gd` (new: every RACE button starts a race, keyboard and synthetic pad)
  - `godot/tests/_qa_save_guard.gd` (new: backs up and restores the shared dev-sandbox saves around a probe)

## Update 2026-11-10 (resumed)
- POI work (worktree `t3-d6370480-...`) is merged into the main checkout, uncommitted: `scripts/world/poi.gd`,
  `tests/test_poi.gd`, edits to `open_world.gd`, `open_world_hud.gd`, `world_progress.gd`, `map_marker.gd`,
  `run_tests.gd`, `AGENTS.md`. Verified on the main checkout: import exit 0, full suite 52 ok / 0 failures,
  headless boot clean.
- Campaign events, Golf IV and QA agents were restarted in their own worktrees and threads.
- `godot/textures/loading/ow_cover_{1,2,3}.jpg` show as modified in the main checkout (09:48 today); not from this
  run, left alone.

## Work still sitting in agent worktrees (uncommitted, each based on `e39a67b`)
All under `/Users/martwyymem/.t3/worktrees/Seicento/`. The agents may have stopped early at the usage limit, so read
each one's last message and run the checks before trusting its diff.

| Worktree | Branch | Task | Seen at handoff |
|---|---|---|---|
| `t3-d6370480-51a9bb6f4fe1bf25` | `t3/discoverable-world-pois` | Phase 3 discoverable POIs on the open-world map | 6 files changed (+253/-68) plus new files |
| `t3-d7bfa3b9-d6005266a0b91c09` | `t3/campaign-event-variety` | Phase 3 campaign event types (sprint, knockout, rally, drag, drift, off-road) | 2 files changed (+107/-2) plus new files, early |
| `t3-a1edc4d4-2b3963a2cadc0a17` | `t3/add-golf4-campaign-car` | Phase 4 pilot car: VW Golf IV through Blender | only new files so far (`tools/blender/carkit.py`, ...) |
| `t3-b7cb2d64-52ffb0eca49fd1f1` | `t3/phase-one-onscreen-qa` | Phase 1 windowed QA | merged into main checkout (above) |

Golf IV agent's final report (stopped at the usage limit): only the Blender side exists. `tools/blender/carkit.py`
(helpers copied from `build_seicento.py`, which is untouched and still rebuilds `seicento.glb` byte-identical) and
`tools/blender/build_golf4.py` (real Golf IV size, Seicento object/material names, about 66k triangles). The unfinished
`golf4.glb` was deleted; rebuild with `blender -b -P tools/blender/build_golf4.py -- --renders DIR` and grep the log for
"Traceback" (Blender exits 0 on a Python error). Defects: tail lamps smear over the quarter panel (try
`corner_proj(0.35, 3.70, ...)`, lamp angles about 14-60 degrees), spike at the headlamp's inner end, roofline long behind
the B-pillar, no mirrors or door handles, rear/top/wheel/cabin renders unchecked. No game code: `CarSpec`, `CarCatalog`,
per-car calibration key (`track.cal_alt`, `Strategy.calibrate()`, `Track.profile_for()`), `race_car_visual.gd` (hard-wired
to the Seicento), picker, `FreeCar`, tests and the AGENTS.md recipe are not started. That worktree has its own
`HANDOFF.md` with line locations. Do not merge the Golf until the model is fixed.

## How to merge one worktree
```sh
cd <worktree> && git add -A && git reset -q -- '*.uid'   # stray .uid files of pre-existing scripts stay out
git diff --cached --binary HEAD > /tmp/x.patch
cd /Users/martwyymem/Developer/Seicento && git apply --3way /tmp/x.patch
```
Expect conflicts in `godot/scripts/ui/game.gd`, `scripts/sim/campaign.gd`, `scripts/world/open_world.gd`,
`tests/run_tests.gd` (suite lists). Keep new `.uid` files that belong to new scripts.

## Checks on the merged tree (all must pass)
```sh
godot --headless --path godot --import > /tmp/import.log 2>&1; echo exit=$?   # exit 139 = engine crash, retry once
timeout 1800 godot --headless --path godot -s tests/run_tests.gd
timeout 900 godot --headless --path godot -s tests/_run_race_test.gd           # completed=true errors=0
timeout 120 godot --headless --path godot --quit-after 60                      # no SCRIPT ERROR
```

## Next steps
1. Merge POIs, campaign events and the Golf IV; run the checks.
2. Wire a campaign mission's `reward_car` to the Golf (`CarCatalog.unlocked("golf4")` reads the `cars` list in the
   campaign save). Look at the Golf in a window.
3. Update `TASKS.md` from the agents' reports. Ready now from QA: tick Phase 1 "every RACE button starting a race"
   (keyboard and synthetic pad; a physical pad is untested) and Pillar 2 "Options text no longer promises effects".
   Retro styles pass on circuits by day and in night rain; the open world in the six styles is not seen yet (needs a
   probe that goes through `game._enter_open_world("")`).
4. QA not started: graphics presets and the Low night-rain frame, open world from the car, street stages, UI
   leftovers (pad glyphs, 21:9 and 4:3 bars, autopilot chip, tables in two skins).

## Things learned in this run
- The first `--import` in a fresh worktree can segfault Godot 4.7.2 (engine worker-thread bug) and shows a macOS crash
  dialog. Never pipe Godot through `tail` without checking the exit status.
- All worktrees share one `user://dev_sandbox/`; concurrent suites can disturb each other's saves. Re-run a
  save-related failure on its own. Old rally and championship saves there once made a probe open on SS3.
- QA screenshots came out 1280x548: a 21:9 setting was probably left in the shared sandbox `graphics.cfg`.
