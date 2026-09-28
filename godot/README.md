# Seicento 900 Cup — Godot port (work in progress)

Godot 4.7, GDScript. The JS game in the repo root stays as the reference until this version matches it.

Run `godot --path godot` to open the front end. The set-up page covers lap and timed (endurance) races on
all ten circuits, opponents and difficulty, weather, start time, grid position, driving aids, gearbox,
driver profile and paint, pit rules, tyre wear, fuel use, crew, AI learning and bot physics. As in the
reference, the strategist lists the fastest pit plans for those settings (lap time, fuel per lap, pit-stop
cost and tyre life per compound) and a stint editor validates hand-built plans; the chosen plan is what the
race starts with. Circuits apply their default race length and tyre wear, endurance turns refuelling on,
the page remembers its settings between sessions and shows what the learning AI knows about you on the
selected circuit (with a Forget button). Championship mode shows the calendar with progress and the saved
standings, plans each round automatically and scores F1-style points.

The race view has the procedural 3D circuit, merged low-poly cars with lights, wheel spin/steer and body
roll, a day/night sky, rain, headlight beams, skid marks, start lights and six cameras (chase, far chase,
roof, trackside TV, bird's-eye, full track). The whole interface is styled after Colin McRae Rally 2.0 (`scripts/ui/cmr_style.gd` builds the shared
theme): a rally-blue animated backdrop, slanted light bars with a lime selection, a turntable car preview
and bold italic type. In the race the HUD shows a gradient timing tower, a pace-note box with an arrow
bent by the next corner, a segmented lap-progress bar and clock, an event feed, a pit-wall panel (tyres,
fuel, plan, next stop), a segmented rev arc with a big gear digit, a minimap, name tags and a help
overlay. There is a pause menu, time warp with co-driver, skip-to-results after retiring or finishing,
and a results screen with championship points.

The UI is laid out on a 1600×900 canvas and scaled to the window (`canvas_items` stretch, `expand`
aspect), so it keeps its proportions at any resolution; the 3D views render at the window's full pixel
size. Options → Interface size makes the UI smaller or larger on top of that.

## Remaining port work

- The reference's alternative top-down 2D race view is not ported.
- Terrain blending, scenery materials and shadows could still be refined against the reference renderer.
- The set-up page relies on standard Godot focus navigation; the reference's keyboard/gamepad row
  navigation of the front-end pages (e.g. stepping through plans with left/right) is not replicated.

## Performance notes

The race runs a fixed 120 Hz simulation with render interpolation and a spiral guard (at most 40 × warp
steps and ~40 ms of simulation per frame). The per-tick hot paths (`Physics.step`, `Race.traffic`,
`side_room`, `collide`, `Track.project`) avoid allocations and redundant work while keeping the arithmetic
identical to the reference: the physics parity tests still match to 1e-14 and fixed-seed races reproduce
bit for bit. Rough costs on an M4 Pro: 57 µs per car-tick of full physics, ~0.5 ms per tick for a
16-car field on rails (time warp / skipping).

## Layout

- `data/` — tunable resources you edit in the Inspector: `seicento.tres` (car), `tyres/*.tres` (compounds),
  `tracks/*.json` (generated centrelines + elevation; rebuild with `python3 tools/build_tracks.py`).
- `scripts/data/` — resource classes (`CarSpec`, `TyreCompound`, `TrackDef`, `RaceSettings`).
- `scripts/sim/` — simulation, ported from `js/` (`CarModel`/`Tyres` ← car.js, `Physics`, `Track`,
  `Strategy`, `Race`, `Driver`, `Brain` (learning AI), `Weather` and helpers).
- `scripts/ui/` — `game.gd` (menus, set-up, race loop, input, pause, results, championship),
  `race_world.gd` (3D circuit, sky, cameras), `race_car_visual.gd`, `race_hud.gd`, `race_audio.gd`.
- `ui/` — main game scene and race world scene.
- `tests/` — headless parity tests against the JS version.

Coordinates: the JS/2D x (east) and y (south) map to Godot X and Z; Y is up.

Keyboard: W/↑ throttle, S/↓/Space brake, A/D or ←/→ steer, E/Q shift (manual gearbox), P box this lap,
[ / ] tyre choice for the next stop, − / = fuel for the next stop, R re-plan, O autopilot, C camera,
L racing line, H help, M mute, , / . time warp, Esc pause, Enter skip to results once retired or finished.
Gamepad: left stick steers, triggers for throttle/brake, Start pauses.

## Tests

```sh
node tools/parity/car_ref.js                           # refresh JS reference values (from repo root)
godot --headless --path godot -s tests/run_tests.gd    # compare
```
