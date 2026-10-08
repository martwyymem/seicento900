# how2 — where the important settings live

A map of the places you'll most likely want to change. All game paths are relative to `godot/`
(the active Godot 4.7 project); `tools/` paths are relative to the repository root. The root-level
`js/`, `css/` and `index.html` are the old browser game, kept only as a reference for the port.

Run the game with `godot --path godot`, the tests with `godot --headless --path godot -s tests/run_tests.gd`.
For more background read [`godot/README.md`](godot/README.md).

## Quick answers

| I want to…                                        | Change this                                                              |
| ------------------------------------------------- | ------------------------------------------------------------------------ |
| make the car faster / slower, change gearing      | `data/seicento.tres` (fields in `scripts/data/car_spec.gd`)              |
| change tyre grip or how fast tyres wear           | `data/tyres/S.tres`, `M.tres`, `H.tres`, `W.tres`                         |
| change a circuit's pit lane, kerbs, run-off, trees | `data/tracks/<key>.tres` (fields in `scripts/data/track_def.gd`)          |
| change race defaults (laps, weather, opponents…)  | `scripts/data/race_settings.gd`                                          |
| change default laps / wear per circuit            | `TRACK_DEFAULTS` in `scripts/ui/game.gd`                                 |
| make the AI easier or harder                      | `DIFFICULTY` in `scripts/sim/race.gd`                                    |
| rename the bots or change their colours           | `BOTS` in `scripts/sim/race.gd`                                          |
| change championship rounds or points              | `CHAMPIONSHIP_CALENDAR`, `CHAMPIONSHIP_POINTS` in `scripts/ui/game.gd`   |
| change pit-stop times                             | `CREWS` in `scripts/sim/strategy.gd`                                     |
| tune flags, safety car, damage, penalties         | constants at the top of `scripts/sim/race_control.gd`                    |
| change key bindings                               | `_unhandled_input` and `_update_input` in `scripts/ui/game.gd`             |
| change the menu / HUD colours and fonts           | `scripts/ui/cmr_style.gd`                                                |
| change HUD layout sizes or the help text          | constants at the top of `scripts/ui/race_hud.gd`                         |
| change graphics presets (Low…Ultra)               | `QUALITY_NAMES`, `TREE_SCALE`, `apply_graphics()` in `scripts/ui/race_world.gd` |
| change sky / fog / light colours                  | colour constants at the top of `scripts/ui/race_world.gd`               |
| change trackside TV camera behaviour              | `TV_*` constants in `scripts/ui/race_world.gd`                           |
| change the car's 3D model                         | `tools/blender/build_seicento.py`, then rebuild (see below)              |

## Data resources (edit in the Godot Inspector)

These are `.tres` resources; open them in the editor and the fields have tooltips from the `##` comments
in their class scripts under `scripts/data/`.

- **Car** — `data/seicento.tres`, class `scripts/data/car_spec.gd` (`CarSpec`). Mass, fuel tank,
  dimensions, gear ratios, final drive, torque curve, drag (`cd_a`), brakes, suspension, steering lock,
  and the tyre-model calibration (`grip_k`, `load_sensitivity`). Physics `substeps` is here too.
- **Tyres** — `data/tyres/<S|M|H|W>.tres`, class `scripts/data/tyre_compound.gd`. `grip` is a
  multiplier (Medium = 1.0); `life` is metres of tread at nominal load. The list of compounds is
  `Tyres.KEYS` in `scripts/sim/tyres.gd`.
- **Circuits** — `data/tracks/<key>.tres`, class `scripts/data/track_def.gd` (`TrackDef`). Width,
  start line, pit lane (`pit_entry`, `pit_exit`, `pit_offset`, `box_*`), run-off and barrier type,
  banking, kerbs, scenery theme, tree density, grandstand span, floodlights and corner names.
  The keys are `gp`, `nordschleife`, `monaco`, `indy`, `lemans`, `monza`, `silverstone`, `spa`,
  `suzuka`, `zandvoort`, `fiat`.
- **Race settings** — `scripts/data/race_settings.gd` (`RaceSettings`). Every option on the set-up
  page, with its default: track, laps/hours, start hour, opponents, difficulty, grid, collisions,
  slipstream, race control, weather, wear and fuel multipliers, pit rules, crew, player name, colour,
  gearbox and assists.

Generated data (don't hand-edit; rebuild with the tools):

- `data/tracks/<key>.json` — centreline and elevation, from `tools/build_tracks.py`.
- `data/tracks/<key>_env.json` — buildings, woods, water round the track, from
  `tools/fetch_surroundings.py` → `tools/build_surroundings.py`.
- `data/tracks/<key>_far.json`, `<key>_land.png` — distant land to 40 km, from `tools/fetch_horizon.py`,
  `tools/fetch_landcover.py` and `tools/fetch_places.py`.

## Gameplay tuning (constants in code)

### `scripts/sim/race.gd` — the race
- `BOTS`, `BOT_NUMBERS` — the JS reference's field (names, paint colours, numbers), raced with
  `RaceSettings.real_drivers` off; the game's opponents are `Drivers.ROSTER` (below).
- `DIFFICULTY` — per-level bot `skill` (share of the limit), `spread` between bots, `mistakes` rate and
  rubber-band strength `band`.
- `ASSIST_PACE` — how fast the full-assist brake lets you take corners.
- `TOW_MAX`, `wake_strength()`, `tow_drag()` — slipstream.
- `ERR_RAMP` — how quickly a bot's driving error builds up.
- `NEAR_PHYS_PICK_UP`, `NEAR_PHYS_DROP` (ahead), `NEAR_PHYS_BEHIND`, `NEAR_PHYS_BEHIND_DROP` — "Bot physics: nearby only" switching distances.
- `START_FUEL_LAPS` — extra fuel every car loads for the standing start (with dynamic running).
- `MIX_EVERY`, `MIX_BAND` — how often a bot (or the autopilot) rethinks its fuel mix, and the laps of fuel
  between its switch to the save mix and its switch back.
- `class Weather` — when showers start and how heavy they are.

### `scripts/sim/race_control.gd` — flags, safety car, damage, stewards
All tunables are the block of constants at the top: damage (`DMG_FLOOR`, `DMG_SPAN`, `REPAIR_*`),
yellow-flag pace (`YELLOW_PACE`, `PLAYER_SLOW`), safety car (`SC_*`), marshal recovery times
(`RECOVER_*`), red flags (`RED_*`), pile-ups (`PILEUP_*`) and the place give-back window (`GIVE_BACK`).

### `scripts/sim/strategy.gd` — pit strategy
- `CREWS` — pit-stop times per crew (`fixed` overhead, `tyres` change time, refuel `rate` in L/s).
- `PIT_SPEED` — pit-lane speed limit (60 km/h).
- `FUEL_MARGIN`, `RESERVE` — how much spare fuel a plan carries.

### `scripts/sim/brain.gd` — learning AI
- `BIN` — length of each learned track section. Learned data is saved to `user://brain.json`.

### `scripts/sim/qualifying.gd` — qualifying
- `LONG_LAP`, `CO_DRIVER`, `FIELD_EASE` — session length and how fast the field's quali laps are.

### `scripts/sim/pace_notes.gd`, `scripts/ui/co_driver.gd` — pace notes and the co-driver
- `GRADES`, `HAIRPIN_TURN`, `SQUARE_TURN` — corner radii (m) for each grade; `INTO_GAP`, `AND_GAP`,
  `DIST_MIN`, `DIST_MAX` — linking words and distance calls; `CREST_K` — how sharp a crest gets called.
- `LEAD_TIME`, `LEAD_MIN`, `LEAD_MAX` (co_driver.gd) — how early each call comes; `RATE`, `VOLUME` — the voice.

### `scripts/sim/service.gd` — damaged parts and the service area
- `PARTS` — each part's share of the damage, repair minutes and description; `ZONES` — which parts a
  front, side or rear hit reaches; `ALLOCATION` — service minutes between championship rounds.

### `scripts/sim/car_setup.gd`, `scripts/sim/drivers.gd` — car set-ups and the field's drivers
- `SETTINGS` — the settings on the Set Up page (name, end labels, help text); `NOTCHES` — notches either side of
  stock; `apply()` — what each notch changes in the `CarSpec` (brake split, spring rate, roll stiffness split,
  ride height, steering gain).
- `ROSTER` (drivers.gd) — the opponents in grid-filling order: name, number, colour, set-up, and their
  character (`pace`, `quali`, `wet`, `wear`, `errors`, `wets`, explained at the top of the file).
  `RaceSettings.real_drivers = false` swaps it for the JS reference's field (`Race.BOTS`, stock cars); the
  parity race (`tests/test_race.gd`) runs that way.

### `scripts/sim/physics.gd` — vehicle dynamics
- `SURF_GRIP`, `SURF_DRAG` — grip and drag on track / asphalt run-off / grass / gravel.
- `TX_*`, `TY_*` — Pacejka Magic Formula tyre curve shapes.

## Front end, options and saving

### `scripts/ui/game.gd` — menus, race loop, input
- `TRACK_KEYS`, `TRACK_NAMES` — circuits offered in the menus (same order in both).
- `TRACK_DEFAULTS` — default laps and tyre wear per circuit.
- `CHAMPIONSHIP_CALENDAR`, `CHAMPIONSHIP_POINTS` — championship rounds and points.
- `FRONT_MENU`, `TOP_MENU_TABS` — main menu entries.
- `WARP_VALUES`, `WARP_TICKS`, `WARP_SIM_SHARE` — time warp.
- `UI_SCALES`, `UPSCALERS`, `UPSCALE_PRESETS`, `SHARPENING`, `FPS_LIMITS` — Options page choices.
- `STILL_FPS`, `BACKGROUND_FPS` — frame caps when paused / in the background.
- `TICK` — simulation step (1/120 s). Keep it: parity tests depend on it.
- `_unhandled_input()` — in-race keys (P, C, V, H, …); `_update_input()` — throttle/brake/steer keys
  and gamepad.

### Save files
Saved under Godot's `user://` folder (on macOS:
`~/Library/Application Support/Godot/app_userdata/Seicento 900 Cup/`). Paths go through
`scripts/sim/save_data.gd`; tests and tools run with `-s` write to `user://dev_sandbox/` instead.

- `race_settings.cfg` — last set-up page values, and `[car_setup]`: the car set-up kept for each circuit.
- `graphics.cfg` — Options page (`[graphics] quality` 0 Low … 3 Ultra, upscaler, FPS limit, …; `[audio] co_driver_voice`).
- `championship.json` — championship progress and standings, and the player's car between rounds (`car`: damaged parts, steering pull, service minutes used).
- `brain.json` — what the learning AI knows about you (set-up page → Forget clears it).
- `sky_cache.cfg` — cached HDRI sky analysis (`scripts/ui/world_assets.gd`).

Delete a file to reset that part of the game.

## Look and graphics

- `scripts/ui/cmr_style.gd` — the whole UI palette (purples/oranges), fonts and the shared theme.
- `scripts/ui/race_hud.gd` — HUD colours, panel widths (`TOWER_W`, `PITWALL_W`, `FEED_W`, `MAP_S`),
  refresh rate and `HELP_TEXT`.
- `scripts/ui/race_world.gd` — the 3D world:
  - `QUALITY_NAMES`, `TREE_SCALE`, `LAMP_POOL`, `apply_graphics()` — quality presets.
  - `SKY_*`, `HORIZON_*`, `SUN_*`, `FOG_*`, `CLOUD_*`, `ASPHALT_*` — time-of-day and weather colours.
  - `STAND_*`, `PIT_*`, `GANTRY_BEAM_Y` — must match `tools/blender/build_trackside.py`.
  - `TV_*` — trackside TV cameras; `CAMERA_NAMES` — camera list.
  - `KERB_COLOURS` — kerb stripe colours per `TrackDef.kerb_style`.
- `scripts/ui/surroundings.gd` — scenery from OpenStreetMap: `TREE_BAND`, `TREE_CELL`, `TREE_CAP`,
  `TREE_VISIBLE` (per quality), `PALETTES` (ground colours per circuit), `SPECIES` (trees per
  country), `LANDMARK_SIZE`.
- `scripts/ui/far_land.gd` — distant land colours and heights.
- `scripts/ui/trackside_furniture.gd` — marshal posts, tyre walls, bridges (`POST_SPACING`, …).
- `scripts/ui/ray_tracing.gd` — ray-traced reflection strength and cut-offs.
- `scripts/ui/world_assets.gd` — where optional HDRI skies / textures are looked for (`ROOTS`).
  Download them with `python3 tools/fetch_assets.py`; see `godot/ASSETS.md`.
- `scripts/ui/race_audio.gd` — procedural engine sound.
- `shaders/*.gdshader` — sky, road, ground, foliage, water, buildings, crowd. Uniforms at the top of
  each shader are the knobs.
- `project.godot` — window size (1600×900 design canvas), stretch mode, main scene.

## 3D models (Blender)

Models are built by scripts, never edited by hand. Change the script, then rebuild, e.g.:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_seicento.py -- --renders /tmp/seicento
```

| Script                                 | Writes                    | What                                        |
| -------------------------------------- | ------------------------- | ------------------------------------------- |
| `tools/blender/build_seicento.py`      | `godot/models/seicento.glb`  | the car                                   |
| `tools/blender/build_trackside.py`     | `godot/models/trackside.glb` | grandstands, pits, gantry, TV towers      |
| `tools/blender/build_furniture.py`     | `godot/models/furniture.glb` | marshal posts, boards, tyre walls, bridges |
| `tools/blender/build_trees.py`         | `godot/models/trees.glb`     | tree species                              |
| `tools/blender/build_landmarks.py`     | `godot/models/landmarks.glb` | circuit landmarks                         |
| `tools/blender/kit.py`                 | —                         | shared mesh helpers                         |

Keep object names (`Body`, `Details`, `Stripes`, `Wheel`) and material names (`Paint`, `Taillight`,
`Glass`, `Headlight`) stable — `race_car_visual.gd` looks them up by name.

## Adding a new circuit (outline)

1. Add its OSM way ids to `TRACKS` in `tools/build_tracks.py` and run `python3 tools/fetch_elevation.py <key>`
   then `python3 tools/build_tracks.py`.
2. Create `godot/data/tracks/<key>.tres` (a `TrackDef`) — copy an existing one.
3. Add the key and name to `TRACK_KEYS`, `TRACK_NAMES` and `TRACK_DEFAULTS` in `scripts/ui/game.gd`.
4. Optional scenery: `tools/fetch_surroundings.py` → `tools/build_surroundings.py`, and the distant land
   tools (`fetch_horizon.py`, `fetch_landcover.py`, `fetch_places.py`); add a palette in
   `PALETTES` / `COUNTRY` in `scripts/ui/surroundings.gd`.
