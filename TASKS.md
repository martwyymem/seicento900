# The Master Directives & Task Bible (TASKS.md)

> "add other weathers like: snow, hail, fog. stylize the game as ps1/ps2 graphics. create some orignal tracks based on cities like: Tokyo, Brzeszcze, Kraków, Oświęcim, Wilamowice, Bielsko Biała, Pszczyna. create some shaders to reminisce of good old times in gaming like GTA: SA, CMR2.0, FH1, NFS Carbon, NFS Most Wanted. create campaign that makes sense. make menu actually logical and delete redundacy. Use sub-agents, ask when you need something"

Later directives from the user (2026-10-22/23), in short:
- "make these tracks realistic … add buildings that actually are there in real life, add road blockage, don't add shit like grandstands there if they do not exist"
- "why so many choices in main menu if you setup them again in the race menu"; "make menu simpler, like easier to use on controller"
- "add a rally mode for some of these tracks, add regular time trial mode"
- "make the repairs actually matter between races in championship (which should be customizable) and campaign"
- "Campaign Mission 7 is impossible"
- "make the graphics actually look good … especially PS1 filter and GTA:SA"
- "add resolution and aspect ratio, add audio volume settings"
- "the changing of map is quite lag heavy"

---

## ⚠️ MANDATORY INSTRUCTION FOR ALL AI AGENTS & MODELS
Every agent and model operating in this repository **MUST read this document before planning or writing any code**. This file is the single source of truth ("The Bible") for the project's vision, architecture, task breakdown, and acceptance criteria. When extending or modifying the game, verify alignment with the pillars below.

---

## Status board (2026-10-23)

| Area | Status |
|---|---|
| Weathers (Pillar 1) | Done |
| Retro styles (Pillar 2) | Retuned from an offline emulator; in-game check and fixes under way (QA pass) |
| Real city tracks (Pillar 3) | Bór done from OSM; Bielsko, Wilamowice, Pszczyna, Kraków routes researched, being built; Brzeszcze, Oświęcim, Tokyo research unfinished |
| Campaign (Pillar 4) | Flow fixed, difficulty curve and easing done, damage carry-over done; full on-screen loop being QA'd |
| Menu & options (Pillar 5) | Controller-first menu, championship set-up, resolution/aspect/audio done; QA'd on screen in progress |
| Rally & time trial (Pillar 7) | Rally sim (`rally.gd`) written; time trial module, HUD and menu wiring in progress |
| Repairs (Pillar 8) | Per-part effects and carry-over done |
| Performance (Pillar 9) | Track switch lag in menus being fixed |
| Night / rain lighting (Pillar 2) | Night in rain looks like a grey day with white glare; being fixed in the QA pass |

---

## Pillar 1: Dynamic Weather Systems
Expand beyond simple dry/wet into atmospheric and physical weather conditions affecting car handling, audio, shaders, and visuals:

- **Dry**: Full grip ($\mu \approx 1.0$). Sunny/overcast daylight or night.
- **Wet**: Dynamic rain showers, track puddles, reduced grip ($\mu \approx 0.70 - 0.85$), spray off tyres, wipers and water reflections.
- **Snow**: Falling snowflake particles, white/cool-tinted snow cover on track runoffs and verges, low friction ($\mu \approx 0.50 - 0.65$), crunching snow audio.
- **Hail**: High-speed ice pellet particles, metallic pinging sound against windshield and bodywork, treacherous handling ($\mu \approx 0.55 - 0.60$).
- **Fog**: Heavy volumetric and distance fog limiting visibility to 30–50 metres (Silent Hill / classic CMR morning rally style), glowing headlights piercing the haze, damp asphalt ($\mu \approx 0.88$).
- **Variable**: Dynamic transition between conditions over race stints.

### Implementation Checklist
- [x] Update [`godot/scripts/data/race_settings.gd`](godot/scripts/data/race_settings.gd) with weather enum: `"dry"`, `"wet"`, `"snow"`, `"hail"`, `"fog"`, `"variable"`.
- [x] Update [`godot/scripts/sim/race.gd`](godot/scripts/sim/race.gd) `Weather` class simulation, forecasts, and tyre friction scaling.
- [x] Update [`godot/scripts/ui/race_world.gd`](godot/scripts/ui/race_world.gd) for GPU particle systems (snow, hail) and dense volumetric fog parameters.
- [x] Add snow/frost coverage support in terrain and road shaders.
- [x] Add sound effects in audio synthesis pipeline for hail clatter and snow crunching.

---

## Pillar 2: PS1/PS2 Retro Graphics & Nostalgia Shaders
Homages, not filters that ruin the picture: every style must keep the road edges, the racing line, other cars and the horizon readable at speed, and the HUD is never filtered.

- **Mode 1: PS1 / Retro 90s**: ~240-line internal resolution with nearest upscale, RGB555 colour, a subtle 4x4 ordered dither locked to the low-res pixel grid (never crawling at screen-pixel scale). No full-screen vertex jitter or affine warp (a post-process can't do them and they hurt readability).
- **Mode 2: Need for Speed: Most Wanted (2005)**: Yellow-green/golden grade that keeps car paint, tinted bloom, firm but not crushed blacks.
- **Mode 3: Grand Theft Auto: San Andreas (2004)**: Warm orange-yellow haze in a band at the horizon that fades out before the road, lifted shadows, soft glow. Not a sepia/brown wash over everything.
- **Mode 4: Need for Speed: Carbon (2006)**: Cool teal/blue grade (reds stay red), blue shadows, deeper contrast, cool glow on lights.
- **Mode 5: Colin McRae Rally 2.0 (2000)**: Clean, crisp, saturated, lightly sharpened. The cleanest style.
- **Mode 6: Forza Horizon 1 (2012)**: Warm, saturated, golden highlights, gentle glow, slight vignette.
- All graded modes use a highlight shoulder so bright areas never blow out to flat white.

### Implementation Checklist
- [x] Create dedicated post-process shader [`godot/shaders/retro_postprocess.gdshader`](godot/shaders/retro_postprocess.gdshader).
- [x] Attach post-processing pipeline to `render_view` in [`godot/scripts/ui/game.gd`](godot/scripts/ui/game.gd) so 3D world is styled while 2D HUD remains sharp.
- [x] Expose retro style selector in Options menu and live hotkey cycling (`F1` / gamepad shortcut).
- [x] Retune all six styles (offline emulator previews in `/tmp/retro_emu/`, contact sheet `/tmp/retro_compare.png`).
- [ ] Check every style in the running game (day and night/rain) and fix mismatches with the emulator.
- [ ] Night/rain lighting: night must look like night (headlights, lamp posts), wet must look wet without white glare that hides the road edge (`race_world.gd` lighting, `ground.gdshader`/`road.gdshader` wet specular).
- [ ] Options text no longer promises effects no style has (e.g. "heat shimmer").

---

## Pillar 3: Original City Tracks (Polish Heartland & Tokyo) — built from the real map
**Rule:** every city track is a closed loop of real public roads from OpenStreetMap, with only buildings that really exist, a road blockage on every real side road that joins the route, and no circuit furniture (grandstands, pit building, gantry, TV towers, kerbs, hoardings, marshal posts) where none exists. Don't invent geography: if the original theme is impossible on real roads, use the closest real alternative and say so.

**Pipeline:** `python3 tools/build_street_tracks.py <key> [--refetch] [--check out.png]` builds a track from its route file `tools/street_routes/<key>.json` (OSM way ids in driving order, start node, corner names, track settings). OSM and elevation responses are cached so rebuilds run offline. Real buildings, woods, water and railways come from `tools/fetch_surroundings.py` + `tools/build_surroundings.py`. The TrackDef flag `street_stage = true` switches off circuit furniture (start is a painted line only). The old `tools/generate_city_tracks.py` skips any track that has a route file; its corner names were written as `d =` instead of `distance =`, so all its corners sat at 0 m.

| Track | Real route | Length | Status |
|---|---|---|---|
| **Bór** (Brzeszcze-Bór) | ul. Bór → Strażacka (OSP Bór) → Borska (level crossing) → Lachowicka (second crossing, past the fishponds) → ul. Bór | 3.30 km | Built: 559 real buildings, 33 ponds, 9 side-road barriers, roadside pit lane on ul. Bór. Open: guardrails on both sides of the whole lap, no far-horizon data |
| **Bielsko-Biała** | Kamienica/Olszówka loop under Szyndzielnia: al. Armii Krajowej → Karbowa → Karpacka → Gościnna → Armii Krajowej (the road up Szyndzielnia isn't a loop; the FSM plant is 7 km away) | 5.1 km, 71 m climb | Route ready, building |
| **Wilamowice** | Rynek → Paderewskiego → Kęcka → Krakowska → Hecznarowice field lane (Jana Pawła II) → Handlowa → Latosińskiego → Sobieskiego → Rynek (gently rolling, no ridge) | 7.3 km | Route ready, building |
| **Pszczyna** | Round the castle park: Wojska Polskiego → Żorska → Szymanowskiego → Chopina → Katowicka → Dworcowa → Piastowska (cobbles) → Rynek → Brama Wybrańców | 3.71 km | Route ready, building |
| **Kraków** | The first ring round the Planty (the Planty itself is footpaths): Basztowa → Dunajewskiego → Podwale → Straszewskiego → Podzamcze (under Wawel) → św. Idziego → św. Gertrudy → Westerplatte; trams on ~1.85 km | 3.68 km | Route ready, building |
| **Brzeszcze** | Mining/railway town loop, must not overlap Bór | — | Research unfinished |
| **Oświęcim** | Town centre / Soła riverside only; keep clear of the Auschwitz-Birkenau memorial grounds and never name corners after it | — | Research unfinished |
| **Tokyo** | Shuto C1 (14.8 km, multi-level, tunnels) vs a shorter real loop; the format can't yet express tunnels/levels | — | Research unfinished |

### Implementation Checklist
- [x] Track spline geometry, TrackDefs, surroundings, land textures and registration for every city key (first version, invented — being replaced).
- [x] OSM pipeline and `street_stage` flag; Bór rebuilt.
- [ ] Bielsko, Wilamowice, Pszczyna, Kraków rebuilt from their routes; laps in `TRACK_DEFAULTS` and the campaign adjusted to the new lengths (~4–6 min races).
- [ ] Brzeszcze, Oświęcim, Tokyo researched and rebuilt.
- [ ] Decide guardrails vs open verges on rural street stages.

---

## Pillar 4: Meaningful Career / Campaign Mode
A narrative-driven, structured career tracking a grassroots Polish racer's journey from a humble factory Seicento 900 to an international street-racing legend:

- **Act I: Silesian Grassroots** (Wilamowice, Brzeszcze, Bór, Pszczyna) — Local trials, tuning the stock 39 hp engine, learning slipstreaming, railway crossings and the fishponds.
- **Act II: Regional Championship** (Bielsko-Biała, Oświęcim, Kraków) — Climbing through the Beskidy and the historic royal city against aggressive regional rivals.
- **Act III: Global Legends** (Fiat Proving Grounds, Tokyo Midnight Showdown) — The ultimate test on the factory proving track and Tokyo's expressways.

### Features
- Target objective per stage (e.g. finish top 3 to unlock the next venue); trophies and progress in `campaign.json` (`scripts/sim/campaign.gd`).
- Narrative briefings and mechanic tips before each stage.
- **Fair difficulty curve** (an average player must be able to finish it): stages 1–3 Easy P3; 4–6 Medium P3 (Bielsko P2); 7 Kraków 11 Medium bots P3; 8 Fiat Medium P3; 9 Tokyo 11 Hard bots, win from pole. Don't raise these without play-testing.
- **Start where the target is:** a stage starts in its target slot (`grid` "p3"/"p2", `race.gd` accepts "p<N>"; a win target starts from pole). Starting mid-grid behind faster bots on narrow street circuits made stage 7 onwards near-impossible, even for the co-driver.
- **Easing:** every failed try on a stage (a DNF counts) drops its field one difficulty level, down to Easy; a win resets it; the briefing says "eased from X after N tries".
- **Car damage carries over** between stages; a mandatory Car & Service stop before the next stage.
- **Open world hub (Brzeszcze)**: CAMPAIGN opens a free-roam map of the whole town (OSM + EU-DEM, `tools/build_open_world.py`, `scripts/world/`), Forza Horizon style. Each stage is a beacon at its real start or on the real road out of town towards its venue. There are traffic, speed traps, discoveries, a skill chain earning fans, GPS, a day/night cycle and a festival hub. Results lead back to the beacon (through the service area when damaged). See `godot/README.md` → Campaign open world.
- [ ] Stage descriptions and tips rewritten to match the rebuilt real tracks (e.g. Bór has no "Staw Bór embankment" or gravel runoff; Kraków isn't on the Planty itself; Bielsko has no Szyndzielnia hairpin).

---

## Pillar 5: Streamlined, Controller-First Menu & Options
- **Main Menu**:
  1. **CAMPAIGN**: Opens the open world of Brzeszcze (drive to a stage's beacon; the stage list is in its pause menu and lists the briefing of the furthest unlocked stage); ENTER STAGE races it with the stage's circuit, laps, weather and field (only driver, paint, car set-up, gearbox and aids stay the player's).
  2. **QUICK RACE**: The one custom-race page (track, laps, opponents, difficulty, weather up front; format, start time, gearbox/aids/grid, driver & paint, car set-up, pit strategy, rules & AI folded under ADVANCED).
  3. **RALLY**: Hidden until Pillar 7 is wired (entry is ready, commented out, between QUICK RACE and TIME TRIAL).
  4. **TIME TRIAL**: Solo hot-lapping (see Pillar 7).
  5. **CHAMPIONSHIP**: A season set up before round 1 — calendar preset (Classic GP, Polish Tour, World Tour, Full) or ticked circuits, order as listed or shuffled, race length (Sprint/Standard/Long), opponents, difficulty, weather fixed or random per round, points preset, qualifying (drive/simulate/skip), damage & repairs (Off / Realistic 60 min / Hardcore 30 min). Saved in `championship.json` and locked once round 1 is raced; RESET SEASON unlocks.
  6. **OPTIONS**: Display (window mode, resolution, aspect ratio, frame pacing, 3D upscaling, lighting, interface size), retro style, audio volumes, co-driver.
  7. **QUIT**.
- The mode is chosen on the main menu only: the set-up page has no mode toggle; its title names the mode (`QUICK RACE`, `CHAMPIONSHIP · ROUND 3/8`, `CAMPAIGN · STAGE 2/9`); B/Esc goes back.
- **Controller:** D-pad/left stick move, A select, B back, LB/RB pages, START race/continue; ◂ value ▸ selectors (`scripts/ui/menu_selector.gd`) instead of popup lists; prompts follow the connected device; a thick bright focus ring; focus restored after dialogs and page switches.
- **Resolution:** Native plus 720p–4K presets that fit the screen; windowed resizes and centres; in fullscreen (macOS can't change display mode) it becomes the 3D **render resolution**, stacked with 3D upscaling.
- **Aspect ratio:** Auto (fill), 16:9, 16:10, 21:9, 4:3 with black bars; HUD and menus stay inside.
- **Audio volume:** Master, Engine, Effects, Co-driver (0–100 % in 10 % steps, live, saved in `graphics.cfg [audio]`; 100 % = the original levels). The co-driver uses system text-to-speech, so his volume is set directly (Co-driver × Master). No music exists, so no music slider.
- [ ] On-screen QA: pad glyphs render, focus never lost, fullscreen → windowed resize, bars at 21:9/4:3, volumes.

---

## Pillar 6: Subagent & Testing Protocol
- Use subagents whenever parallel tasks (generating tracks, compiling shaders, updating test harnesses) can be accelerated. Split work by file ownership so agents don't edit the same file; edit surgically, never rewrite shared files; don't commit unless asked.
- Every modification must be validated by running:
  ```sh
  godot --headless --path godot -s tests/run_tests.gd
  ```
  plus `tests/_run_race_test.gd` (parity race) for any change to race behaviour, and a headless boot (`godot --headless --path godot --quit-after 60`) with no script errors.
- **Zero failure tolerance**: all suites pass (`test_car`, `test_physics`, `test_track`, `test_strategy`, `test_dynamics`, `test_ui_and_audio`, `test_service_season`, `test_options`, `test_qualifying`, `test_lap_records`, `test_pace_notes`, `test_world_audio`, `test_retro_pipeline`, and new rally/time-trial suites).
- **Windows:** default to headless. Windowed Godot runs (screenshots, UI flows that need a drawn frame) only when the user has allowed them in the current session, one windowed agent at a time, short runs. Otherwise judge visuals from existing screenshots or offline emulation and list what still needs an on-screen look.
- A new script with `class_name` needs the global class cache refreshed (`godot --headless --path godot --import`) or the game fails to boot with "Could not find type".

---

## Pillar 7: Rally & Time Trial
- **Rally** (`scripts/sim/rally.gd`, after CMR 2.0 and the user's WRC 3DS reference scripts): an event is several special stages driven solo against the clock from a standing start, co-driver pace notes on, rivals' stage times simulated from their pace with form, spins, punctures and retirements (seeded, deterministic), splits, jump-start and cut penalties, overall classification, and service between stages using the Car & Service page. Suited tracks: Bór, Wilamowice, Bielsko, Brzeszcze, Pszczyna (rural/street stages). Gravel only if the physics handles a whole loose-surface stage without affecting other tracks.
- **Time Trial**: solo hot-lapping, no pit rules/wear/fuel, laps until quit; live delta to best lap with the ghost, coloured sector splits (purple/green/red), lap list, invalid laps for cuts, one-button restart (keyboard and gamepad); records in `LapRecords`.
- HUDs readable from the couch: rally stage time, splits vs leader, stage position; time-trial delta bar, sectors, best/last.

### Implementation Checklist
- [x] Rally events, stage tracker and rival model (`rally.gd`).
- [ ] `scripts/sim/time_trial.gd` (`class_name TimeTrial`; `race.gd` loads it only if present until then).
- [ ] Rally and time-trial HUDs in `race_hud.gd`.
- [ ] Menu wiring: un-hide RALLY (event picker, stage results, standings, service between stages); TIME TRIAL sets `settings.mode = "time_trial"` and binds restart.
- [ ] `test_rally.gd`, `test_time_trial.gd`.

---

## Pillar 8: Repairs That Matter
- Damage is split into parts (`scripts/sim/service.gd`) and each part hurts its own system: Engine (power, misfires above 15 %), Gearbox (slow shifts, missed shifts above 40 %, top gear lost above 70 %), Brakes (longer stops, pull under braking), Suspension (grip), Steering (vague, off-centre), Body (drag), Exhaust (a little power, louder), Electrics (dim, flickering headlights).
- A sound car drives exactly as before (every effect multiplies by 1.0 at zero damage; tested, parity race passes).
- Damage carries over between championship rounds and campaign stages (saved with the season / `campaign.json`); after the race the results lead to SERVICE AREA ▸, which lists each unrepaired part and what it will do next race. AI cars start every race repaired. No money economy.

---

## Pillar 9: Performance
- [ ] Changing the circuit in menus must not hitch: update labels and the 2D map at once, rebuild the 3D menu backdrop only after the selection rests (debounced), skip redundant rebuilds, build track/env data off the main thread where safe, cache recently built backdrops. Measure before/after.
