# Handoff (2026-11-22, session paused near the usage limit)

User request: the Hypercar Seicento is undriveable on keyboard (weak brakes, spins when you steer under braking,
minimap too zoomed out, no warnings for when to brake). After that: commit once tests pass and release **0.5.3**.

## State (uncommitted, shared working tree)
- **Done by the main thread (not yet run in the full suite):**
  - `godot/scripts/ui/race_world.gd`: the racing line's red braking zones now come from the player's own car
    (`racing_line_speeds`, `_repaint_racing_line`, called from `set_race`). Stock races unchanged.
    Test `godot/tests/test_racing_line.gd` (passes alone; added to `run_tests.gd`).
  - `godot/scripts/ui/trackside_furniture.gd`: 100/200/300 m braking boards now on street tracks too (Goliath etc.).
    Not yet seen on screen or tested.
- **Delegated (T3 child threads, may still be running):**
  - Hypercar brakes and the spin when you steer under braking (Opus 5.5 high): `car_spec.gd`, `physics.gd`,
    `hypercar.gd`, `_hypercar_feel_probe.gd`, live_events PACE.
  - Race minimap zoom and early corner/BRAKE callouts (Gemini 4 Neon): `race_hud.gd`, `map_marker.gd`,
    `pace_notes.gd`, `co_driver.gd`, tests `test_map_marker.gd`, `test_pace_notes.gd`.

## Next steps
1. Read both child reports; check their before/after numbers.
2. `timeout 900 godot --headless --path godot -s tests/run_tests.gd` and `godot --headless --path godot -s tests/_run_race_test.gd`
   (re-baseline only if an intended change moved it; say so).
3. Commit. Bump to 0.5.3 (`project.godot` config/version, `export_presets.cfg` file/product_version 0.5.3.0,
   macOS short_version 0.5.3 and version +1), commit "Version 0.5.3".
4. Build from a clean HEAD copy (rsync godot/ to /tmp, `git archive HEAD godot | tar -x` over it), export
   "Windows Desktop" and "macOS", zip the app with `ditto -c -k --keepParent`.
5. Push main over HTTPS via gh credentials; `gh release create 0.5.3 --target <full sha>` with both assets
   (upload under nohup with retries).
6. Delete this file.

## Hypercar braking / keyboard spin (2026-11-22, sub-agent, stopped at the quota limit, NOT committed)

State: game behaviour unchanged (hypercar.gd untouched). Added, default-off (parity `_run_race_test.gd` passes, 191135 values, 0 drift):
- `CarSpec.brake_rear_grip` (0 = off): rear brake-by-wire, each rear wheel brakes at most this share of its own mu*fz (up to `brake_rear`).
- `CarSpec.abs_slip` (1.2 = old): how far past peak slip the ABS lets a wheel go. Both read in `physics.gd` (ABS block).
- `tests/_hypercar_feel_probe.gd -- kb [set=field:value,...]`: keyboard scenarios (Game._update_input ramps) on the flat rig AND in a real Race on the Goliath (grass/WALL/SPUN flags, decel g per speed); `-- trace tap=0.25 at=-170 [set=...]` prints a frame trace.

Findings (baseline in the probe): flat-rig decel 2.12 g @250, 1.89 @200, 1.54 @100, 1.31 @50; 300-0 195 m. Flat-rig taps never spin (beta <= 4 deg).
On the Goliath (8 m road, 2 m grass, wall at 6 m) a 0.25 s tap under braking at 170 km/h SPINS (beta 31-42 deg); longer taps reach the wall.
Cause 1: rears do almost no braking (rho 0.14) and fronts sit at 1.2x peak under ABS -> weak low-speed decel.
Cause 2: under 2 g braking the short wheelbase leaves ~1300 N per rear wheel; a tap starts a yaw weave (inner rear down to 300 N),
the car yaws back the other way ~0.5 s after the key is released and all four tyres go past the limit, on tarmac, before any grass.
Tried `set=brake_rear:2400,brake_rear_grip:0.8` (300-0 178 m, 2.43 g @250, flat stays clean) but the Goliath taps still spin; adding abs_slip 0.9 made it worse.
Next: damp the post-tap yaw weave (ESC on yaw overshoot under braking / more rear roll share / slower keyboard ramp at speed per CarSpec),
then tune EBD, then LiveEvents.PACE["hypercar"] braking + Track.profile_for/Race.brake_k (rail now brakes 1.25 g + aero, ~2.06 g @250).
