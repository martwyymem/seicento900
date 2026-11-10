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

## Update 2026-11-10, later
- POI work was committed on main as d7f0244 (not by this run).
- QA round 2 done (Sonnet). Its probe `godot/tests/_qa_ow_look.gd` and `_qa_race_shots.gd` changes are in the
  main checkout, uncommitted. Findings: Monaco night-rain lamp-streak glare, Medium-preset wet-road glitter,
  Tokyo ground reads as grass, `test_options.gd` leaves 21:9 in the shared graphics.cfg; High/Ultra night rain
  24/31 ms on the GP (indicative). QA item 4 (open-world traffic, LoD2, flats, Wola/Rajsko) not looked at.
- A windowed Opus agent is fixing those four findings in its own worktree (from d7f0244), then item 4 if time.
- Golf IV (worktree t3-a1edc4d4) merged into the main checkout, uncommitted: model `golf4.glb` + `build_golf4.py`
  + `carkit.py`, spec `golf4.gd` (13.9 s 0-100, 171 km/h), `CarCatalog`, per-car `race_car_visual.gd`, pickers,
  `test_car_catalog.gd`. Verified on main: import 0, suite 53 ok / 0 failures, parity `completed=true errors=0`,
  boot clean. Not seen on screen. Still to do: a campaign mission's `reward_car = "golf4"` (after the campaign
  missions merge); lap ghosts still show the Seicento.
- Campaign missions (worktree t3-d7bfa3b9) merged into the main checkout, uncommitted: `missions.gd`, `drift_score.gd`,
  race rules, mission HUD plate, beacons, `test_missions.gd`. The Bór Knockout (`knockout_bor`) now awards the
  Golf IV (`reward_car`, appended to the campaign save's `cars`; results line "New car won"; CAR picker hint names
  the mission). Verified on main: suite 53 ok (after updating test_missions' stale "reward_car must be empty"
  check), parity `completed=true errors=0`, boot clean. TASKS.md updated from all four reports.
- Next: after the windowed fix agent finishes, a windowed pass on the Golf IV look and the mission flows
  (beacon -> race -> results -> beacon, rally mission service halts) - nothing of either has been seen on screen.
- Rendering fixes (worktree t3-76756a24) merged, uncommitted: city-theme floodlight masts at 0.35 power (Monaco
  glare 10.5-12.5% -> 5-6% near-white road), FSR sharpening softened (Medium 0.4->0.8, Low 0.8->1.2; Medium wet
  glitter gone), city-theme grey paving ground, test_options.gd restores graphics.cfg after each check. Verified on
  main: suite 54 ok / 0 failures, parity `completed=true errors=0`, boot clean.
- Windowed Opus agent now checking the Golf IV and the mission flows (worktree from d7f0244 + main_wip.patch).
- Dev menu (§ + 1) extended, uncommitted (`game.gd` `_dev_campaign_entries` / `_dev_world_entries` /
  `_dev_mission_race_entries`, `dev_menu.gd` header, `tests/test_dev_menu.gd`): open every stage and mission, give/take
  back mission cars, clear each mission, forget mission results; open world: drive to each mission beacon, discover
  or forget all POIs; mission race: knock out the drop-zone car, +1000 drift points. test_dev_menu passes; the
  open-world and in-race entries compile but were never pressed (windowed check needed).
- Windowed agent "Golf IV and campaign mission flows" (Opus) was finishing its verification when the usage limit ran
  low; read its report (thread task 2cb6965b) and merge its fixes, then run suite + parity + boot.

## Live events (2026-11-10, open-world FH-style events): state for the next session
- Built, headless only: `godot/scripts/world/live_events.gd` (sprint, speed zone, drift zone, trailblazer generated round the car), the OpenWorld integration (`_live_*` functions in `open_world.gd`), the HUD's `set_live`, `WorldProgress.live`, `tests/test_live_events.gd` (in run_tests), probe `tests/_live_events_probe.gd`. Docs in AGENTS.md and TASKS.md. Not committed; not seen on screen.
- Parity race passes. Full suite result: see the scratchpad suite.log of that session, or re-run `tests/run_tests.gd`.
- Half-done: `godot/scripts/world/street_rivals.gd` (`StreetRivals`, rival sim for a "street_race" kind) exists but nothing uses it and it has no tests. Next: the street_race kind in LiveEvents (KINDS/NAMES/COLORS/BLURB, generate like the sprint, rivals in begin/tick, place → medal), rival drawing via `traffic._car_node` + contact in `open_world.gd`, cleanup on abandon/finish/suspend, tests.
- Review findings FIXED and verified (2026-11-10):
  * Checkpoints on bridge decks passing from below: fixed by recording road surface `cp_z` in `LiveEvents._make()` and enforcing vertical tolerance check (`absf(z - cp_z[cp]) <= 4.0`) in `tick()`, fed from `drive.z`.
  * `_live_sync` blinking active card: fixed by tracking `active_live_id` and preserving `active_event` across board refills if still within trigger radius.
  * `_live_finished` clobbering GPS: fixed by only reassigning when GPS target specifically pointed at the finished live event (or was out-of-bounds) and player has not set a manual waypoint; excluded live events from `_next_open_event`.
  * Mid-run car/mod switch & respawn exploits: switching cars, toggling car mods, manual car reset, or water respawn now cleanly abandons any active live event with an explanatory notification banner.
  * Reset campaign dropping active checkpoint beacon: fixed by calling `_live_cp_beacon()` in `_refresh_events()` when an event is running.
  * `resample` division by zero: added guard against zero-length segments.
  * Knockout race finish projection (`race.gd`, `game.gd`): fixed `approximate_finish()` to properly simulate lap-by-lap knockout eliminations, populating `knocked_out` and `out_order` with DNF reasons, and enabled skip projection for knockout races.
- Test verification:
  * Full test suite `godot --headless --path godot -s tests/run_tests.gd`: all 54 suites OK, 0 failures.
  * Bit parity `godot --headless --path godot -s tests/_run_race_test.gd`: 191,135 values checked, `completed=true errors=0`.
  * Clean boot `godot --headless --path godot --quit-after 60`: exit 0, 0 script errors.
- Windowed Golf/missions QA fixes merged, uncommitted, verified clean on main (suite 54 ok, parity ok, boot ok).
- Still open: drift/rally/sprint/off-road missions and the "New car won" screen not seen on screen (`PART=mission MISSION=<id>` in the probe); overlapping S1 mission labels on the big map; "0 laps" on drag results; mission results button says BACK TO MENU; rally mission could double-record if its results screen rebuilds.

