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

## PHASE 0 — FIX WHAT WE GOT (current priority, set 2026-10-26)

The scope outgrew the plan. **Until Phase 0 is done, do not start new features; everything in Pillars 1–9 not listed here is parked** (the "planned in the future, not now" items stay as they are below). **Ask the user when unsure.**

**Budget mode until Friday 2026-10-30 08:00:** Sonnet 5.5 at medium effort for all agents and delegates, no Opus/Fable, no high-effort or council/ultra reviews, headless by default, few subagents.

Work items (numbered by topic, not by order). **Execution order: cheapest first** (estimated effort, lowest first): 2, 1, 6 (done), then 3, 13 (done), 14 (building flicker, blocked on a windowed repro), 8b (menu title loop), 8a (race HUD), 4 (terrain), 9 (car model), 5 (map extent), 7 (performance), 12 (asset consistency), 11 (track personality), 10 (buildings and textures). Re-sort if an estimate turns out wrong.

1. **Campaign state:** there is no way to clear/reset the campaign, and navigation always points at the last raced stage (no. 9). Add a reset (with confirmation) and point navigation at the next unfinished stage.
2. **Reverse glitch (automatic gearbox):** in reverse, holding throttle *and* holding brake both speed the car up. Throttle must go backwards faster, brake must slow down (then stop/forward). Add a test.
3. **Train:** reported as not spawning/non-existent (EN57 landed in `f8483c4`; verify in the open world, fix visibility/spawn).
4. **Open-world terrain:** elevation sometimes flat where it shouldn't be; driving under a bridge puts the car on the bridge deck/ground wrongly; near river banks the car rides an invisible plane over the bank or the water instead of sliding off. Fix height sampling (road/bridge layers vs ground), then rebake if needed.
5. **Open-world extent and borders (decided 2026-10-26):** the map covers full Brzeszcze, Jawiszowice, Wola and Rajsko, plus part of Góra so the road connects back to Wola and Brzeszcze. Bend reality for a seamless Forza Horizon-style experience: the map is not a square and has no invisible wall. Edges are natural (road ends with barriers, closed or fenced ends). The S1 gets a turn-around point (e.g. a barriered end or loop) instead of continuing into another town. Reachable areas must be reachable by their real routes. Rebake with `tools/build_open_world.py`.
6. **Waypoint:** let the player place their own map marker as a waypoint.
7. **Open-world performance:** profile and cut cost (chunking/draw distances landed in `f8483c4`, gain unmeasured). Measure first, windowed only with the user's OK.
8. **UI (decided 2026-10-26):** it reads as clutter and is hard to explain to test players. Priorities: (a) the race HUD is ugly and out of place, above all the semi-transparent purple box around the speedometer; redesign it clean and readable, matching the active retro skin; (b) the main menu gets an infinite, seamless title loop (e.g. QUIT wraps round to CAMPAIGN with no visible jump); (c) then the remaining screens, fewer elements per screen, clear hierarchy, each skin looking like what it imitates.
9. **Car model:** closer to reality but still needs work (open list in the thread table: tail, tail lamps, rear plate, bumper lens edges, decal positions, tests on the new model).
10. **Buildings and textures:** maps feel grey and anonymous, buildings are plain boxes with windows. Add varied materials/textures and facade detail per building type.
11. **Tracks:** the new street tracks all feel alike. Give each its own character (landmarks, surfaces, elevation, scenery) once 9–10 give the tools.
13. **Crash repair bug (added 2026-10-27, urgent):** after a crash the car can't be fully repaired; you must finish a race before the service area repairs the rest, while opponents always have 0 % damage. The damage/repair system (`service.gd`, Pillar 8) should apply to **rally mode only**. Fix: in ordinary races, championship and campaign, repairs must be possible in full at any time (no finish-a-race gate) and the damage penalties must not hit the player alone; keep the part-by-part system and carry-over for rally. **Question for user:** should circuit races have no damage effects at all (visual damage only), or should the AI take damage too? Default until answered: no mechanical damage outside rally.
14. **Building flicker (added 2026-10-27, from a screen recording):** in the open world a block of flats beside the road changes colour from frame to frame (cream, white, beige) with grey smudge patches coming and going, and grey shards poke out of some windows. Suspects: two meshes drawn in the same place (z-fighting) between the wall and the chunked props or the town building mesh, a tint recomputed every frame, or the wall overlapping a second surface. Reproduce at that spot, find the overlapping surfaces, fix, and add a test where one is possible. Also check that the chase camera does not get pushed sideways against walls (the car sat in the corner of the frame).
12. **Asset quality:** assets feel thrown together ("slop"). Consistent scale, style and naming across the Blender scripts; fix as touched, no big rewrite.

Rules for Phase 0: one item at a time, each ends with `godot --headless --path godot -s tests/run_tests.gd` green (plus `_run_race_test.gd` for race behaviour); update this section's checkboxes/status when done.

- [x] 1 Campaign reset and navigation (2026-10-27: RESET CAMPAIGN in the open-world pause menu; navigation targets the first uncleared open stage)
- [x] 2 Reverse glitch (2026-10-27: brake drives backwards, throttle brakes; test in `test_dynamics.gd`)
- [x] 3 Train (2026-10-27: it existed and ran, but started 4 km from the station; now starts 450 m short of it and rolls in; test in `test_open_world.gd`)
- [x] 4 Terrain, bridges, river banks (2026-10-27: runtime fixes: bridge approach ramps built at load, one deck per road, car follows the drawn pond/bank terrain, deck edges drop at the parapet; `test_open_world_terrain.gd`. Open: baker should bake approach ramps (`tools/build_open_world.py`), terrain relief is genuinely low (40 m grid, smoothed, rivers not carved), no windowed drive-over yet)
- [x] 5 Open-world borders (2026-10-27: 18-vertex non-square play area covering Brzeszcze, Jawiszowice, Wola, Rajsko and east Góra; roads end in barriers, tree belt, hard edge, S1 turn-around loops at both ends; data 18.5 -> 27 MB; Wola and Rajsko not yet viewed from the ground, build time and framerate untimed)
- [x] 6 Player waypoint (2026-10-27: click or F/pad X cursor on the big map; needs an on-screen check)
- [x] 15 Tunnels and bridge collision (2026-10-27: 12 underpasses baked (railway deck lifted to 5.4 m, embankment cut, portals); bridge piers and parapets collide; `test_open_world_bridges.gd`; road stays at ground height (terrain can't be carved); baker approach ramps and the deck-underside look not done; some level crossings may have been removed by the raised railway ramps; AI traffic and daytime bore lighting unchecked)
- [x] 4b Underpasses and bridge collision (2026-10-27: 12 underpasses through railway embankments with portals and lit bore, bridge piers and parapets are solid, `test_open_world_bridges.gd`; baking the runtime approach ramps still open)
- [x] 7 Open-world performance (2026-10-28, windowed `godot/tests/_ow_perf_probe.gd`, 1600x900, vsync off, M4 Pro: every spot sits on the 120 Hz Metal cap, median 8.0-8.3 ms, p95 8.8-11.2 ms; heaviest is the Jawiszowice station (2726 draws, 3749 objects, 1.9M prims), lightest the S1 exits (~430 draws). Open-world load 6.5 s. Script time reads 10-22 ms but frames stay capped, so headroom is unknown: raise `scaling_3d_scale` to find the real limit if lower-end machines matter. No fix needed now)
- [x] 8 UI simplification and skins (2026-10-27: 8b main-menu strip loops; 8a race HUD redone in `race_hud.gd`: plate-free dash, compact timing list (leader, you, 2 ahead, 2 behind, interval to the car ahead), pit wall only when a stop is relevant, small start lights, controls strip auto-hides, skinned controls guide; seen in paused windowed shots only, live racing look and a second skin unchecked; race set-up redesigned 2026-10-27: Set Up / Advanced / Car / Strategy pages, Service only for rally and championship damage, Circuit Info tab removed, shots in the `tests/_setup_shots.gd` probe; real gamepad and starting a race via every RACE button unchecked; Options page simplified 2026-10-28: Display, Look, Audio, Co-driver on show, 3D upscaling/AA/lighting/reflections folded into one closed ADVANCED GRAPHICS section, explanation paragraphs cut to one line (also drops the "heat shimmer" claim), `_qa_menu.gd` indices fixed for the 7-entry home strip; pause menu, results, quali sheet and the interface-size note placement still not reviewed. 2026-10-30, windowed probe `tests/_screen_shots.gd` (pause, results, quali sheet, championship pause and results): the pause menu now dims the race and HUD behind it; the results table drops BEST LAP when nobody set a lap and STOPS/TYRES when nobody pitted; the resolution note under INTERFACE SIZE cut to one line; quali sheet and championship standings left as they are. Still unchecked: live racing HUD in a second skin, real gamepad)
- [x] 9 Car model (2026-10-27: tail lamps raised and reshaped, headlight lens cleaned off the bumper ledge, door panel matched to the decal, decals re-measured by raycast in `race_car_visual.gd`; seen in Blender renders and a windowed door shot; hood decal and the menu's lavender plate tint unchecked)
- [x] 10 Buildings and textures (2026-10-30: `building.gdshader` facades per type, used by the town and every circuit's surroundings: bare red brick on a fifth of houses, a third of farms, churches and half the halls (tall brick-hall windows with lintels); blocks of flats as prefab panels with joints, stacked loggias, a glass-block stairwell and painted accent strips on some; shops (`commercial`, new kind code 7) get a glazed ground floor under a coloured sign band; garden sheds in boards, garages with coloured ribbed doors; window mullions, curtains, sills and lintels, coloured or wooden front doors, rain streaks, a stone plinth; tiled roofs with scallops and moss, flat roofs with tar-paper seams and patches; night glow toned for shops and stairwells. Windowed probe `tests/_building_shots.gd` (one of each kind, day and night). Not done: corner quoins/cornices (the shader can't see wall ends), real textures, LoD2 roof tiles follow map axes not the slope)
- [x] 11 Track personality (2026-10-30: every street stage had the same grey concrete plate both sides. Now: `TrackDef.barrier` looks for street stages, visual only (`guardrail` W-beam on posts: Bór; `plastic` water-filled blocks, tinted by `barrier_color`: red Wilamowice, yellow Pszczyna, blue Bielsko; `jersey` bannered concrete: Kraków). `TrackDef.cobbles` (lap-distance zones) makes `road.gdshader` draw granite setts with no paint or tar seams: Pszczyna Piastowska and the Rynek (604-901 m), Kraków Podzamcze and św. Idziego (3015-3322 m); grip is unchanged, it is only a look. Landmarks from their real OSM footprints in `build_landmarks.py`: Kraków Barbakan and Brama Floriańska, Pszczyna castle; `test_track.gd` lets street stages carry those. Route files and `build_street_tracks.py` carry the new settings (list pairs become `PackedVector2Array`, `Color(...)` strings pass through). Item 10's facades apply everywhere. Not done: tram rails in Kraków, Wilamowice church model, a lower grip on the setts, windowed checks of Bór, Bielsko and Wilamowice after the changes)
- [x] 12 Asset consistency (2026-10-28, headless: `build_seicento.py` now uses the shared `kit.py` for `arg`, `lerp`, `newell` and the GLB export (`kit.export_glb(path, objects=None, texcoords=True)`); rebuilt GLBs are byte-identical, trackside differs run to run even with no change. New `tests/test_model_contract.gd` checks every GLB keeps the object/material names the code looks up and that cars, lamps, trees and roadside props are real-world size. Scale audit of all GLBs found nothing wrong. 2026-10-30: `kit.material` gained `coat` and `plain` (base colour without the vertex tint); `build_seicento.py` now uses `kit.material` and `kit.setup_preview`, and `seicento.glb` rebuilds byte-identical. Trackside's flat emission material only paints the sponsor atlas and stays local)
- [x] 13 Crash repair bug / damage in rally only (2026-10-27: the campaign no longer carries damage or stops at the service area; a championship keeps its own Damage & Repairs setting, default Off; in-race crash damage is unchanged and hits every car)
- [x] 14 Building flicker (2026-10-27: directional shadow acne on walls near edge-on to the high sun, the sun rotating every frame; fixed with `shadow_bias` 0.3 and `shadow_normal_bias` 3.0 in `open_world.gd`; windowed probe `tests/_flicker_probe.gd`: ~11,500 changed samples before, noise floor after. The chase-camera sideways push was not checked)

---

## PHASE 1 — PLANNED, NOT NOW (user list of 2026-10-27; do not start before Phase 0 is done)

1. **Surface handling:** distinct driving for gravel, dirt, tarmac and wet tarmac. Now everything feels like dirt, and the dirt road is actually faster than tarmac. Tune per-surface grip, drag and sound/visual feedback.
2. **Campaign event variety:** beyond circuit laps: sprint race, knockout race, rally event, drag race, drift event, off-road event.
3. **More tracks from the open-world map:** e.g. an S1 Sprint and other interesting routes through the baked Brzeszcze map.
4. **New cars for campaign progression:** Volvo V50 (2009), Hyundai i20, VW Golf 4, Dacia Logan, Dacia Sandero, Ford Focus (2015), Opel Zafira B (2005). Each unlocked along the campaign; model through Blender scripts in `tools/blender/`. **Question for user:** purchase/unlock rules and the order, and any restrictions per event.
5. **Rally mode uses the map:** several stages named alike (e.g. "Bór") currently reuse the same map over and over; build distinct stages from different parts of the open world.
6a. **Handbrake, drifting and fan levels (done 2026-10-28, headless, not driven by hand):** Space or the pad's A button is the handbrake in races and the open world (Space no longer brakes; in the open world the pad's B starts a stage). `Physics.Controls.handbrake` locks the rears and drops rear grip to 70%, which returns over ~0.5 s; the player's drift assist (full 0.6, abs 0.35, off 0) turns the nose back along the velocity and damps yaw once the slide passes ~29 degrees, so a handbrake turn holds ~30 degrees and straightens by itself; AI cars and the parity tests are untouched. The open world pays a LONG DRIFT bonus every held second. `FanLevels` (`scripts/world/fan_levels.gd`): 10 levels from 0 to 420,000 fans, shown on the open-world HUD with a level-up banner; campaign stages name a recommended level (nothing locked), pay fans on results (first clear base 3000 x stage number, +25% per place better than asked, repeats 25%, misses 10%) and show the reward on the beacon card and results. Tests `test_handbrake.gd`, `test_fan_levels.gd`. Open: feel of the slide (tune `HB_*` and `DRIFT_*` in `physics.gd` by driving), whether fan levels should lock stages, what fans buy (item below).
6b. **Fan-level rewards (user, 2026-10-28; partly done):** each fan level title should unlock a fun modifier toggled in the pause menu, and the top level a special car and a special final race. Done: the **Hypercar Seicento** (`scripts/data/hypercar.gd`): a stock Seicento's mass (815 kg), size and wheels with a Ferrari 499P's ~470 kW at the wheels, all-wheel drive (new `CarSpec.awd`, `Physics` drives four wheels through open diffs, FWD unchanged and parity-checked), a 7-speed box for ~345 km/h, lowered, wings and slicks; measured 0-100 in 3.0 s, 0-300 in 16 s, 346 km/h. The auto gearbox thresholds now scale with the limiter and `CarSpec.shift_hold` stops a flat-torque engine hunting between gears. Livery constants for AF Corse's yellow no. 83 (the 2025 Le Mans winner, Kubica/Hanson/Ye): `Hypercar.PAINT`, `Hypercar.NUMBER`. Test `test_hypercar.gd`. **Still to build:** (a) a `CarMods` list and a MODIFIERS page in the open-world pause menu (planned: L2 Rainbow Paint, L3 Monster Truck (big wheels), L4 Moon Gravity, L5 Ice Rink, L6 Drift King, L7 Tiny Seicento, L8 Bullet Time, L9 Fan Magnet (double fans), L10 Hypercar Seicento), stored in the open-world save, only for the open world and never for campaign stages; (b) putting the hypercar and its livery on the player's car in the open world; (c) the **final race**: a campaign stage 10 locked until fan level 10, hypercar field, on a lap that covers the whole open-world map in one clever loop (needs a track built from the road network, see `tools/build_street_tracks.py` and `build_open_world.py`; the race passes `models: {car_model: Hypercar.model()}` so every car uses it). Open questions: traffic cars as monster trucks too; whether the final race is raced on the open-world roads or as a baked track. **Also done (2026-10-28):** (b) the hypercar in every mode: a CAR picker in the race set-up's driver row (stock or Hypercar Seicento, locked until fan level 10, saved as `car_class` in race_settings.cfg) puts the whole field in the hypercar with the yellow no. 83 livery and a re-planned strategy in quick race, time trial, rally, championship and campaign; the open-world pause menu has a CAR button saved in `WorldProgress.car_class`. `Strategy.calibrate()` keeps the stock calibration in `track.cal` and any other car's in `track.cal_alt` (it used to reuse the stock one, so the hypercar player never finished). A **dev menu** on § + 1 (`scripts/ui/dev_menu.gd`, entries from `game._dev_entries()`): fans +10k/100k/1M, unlock everything (`FanLevels.dev_unlock`), open-world teleports, time of day, park a traffic car ahead, respawn; in races weather, repair, fill tank, finish now. A lone § tap still toggles the dev HUD. Test `test_dev_menu.gd`. Unverified: whether the § key reaches Godot as QUOTELEFT or SECTION on the ISO Mac keyboard (both are accepted). **(a) done (2026-10-29, headless):** `CarMods` (`scripts/world/car_mods.gd`) and a MODIFIERS page on the open-world pause menu (Esc goes back), saved as `WorldProgress.mods`: Rainbow Paint, Monster Truck (visual: 2.2x wheels, lifted body), Moon Gravity (1.62 m/s²), Ice Rink (30% grip), Drift King (new `Physics.Env.rear_grip` 0.72, 1.0 elsewhere so parity holds, drift assist 1.0), Tiny Seicento (visual half scale), Bullet Time (0.4x simulation in jumps and drifts; skills score in simulation time), Fan Magnet (double banked chains). Test `test_car_mods.gd`. Second opinions (t3.chat, Muse Wonder and GPT-6.1 Sol, 2026-10-29): both pick a **baked circuit** for the final race (prototype the route on the road graph, then bake and hand-tune: wider town corners, props cleared, crossings locked), 12-17 km, 2 laps, both S1 carriageways and their U-turn loops as the long straights, a technical town sector, no repeated roads; both say Monster Truck and Tiny need real physics or a cosmetic label, Ice Rink overlaps Drift King, Fan Magnet is dull (suggested swaps: Traffic Chaos or Bumper World for Ice Rink, a rocket boost or stunt challenges for Fan Magnet); monster traffic as a separate toggle (Sol) or only NPC Seicentos (Muse); they disagree on cutting fans for Drift King (Muse 0.6x, Sol only if testing shows farming). **User's answers (2026-10-29) and what was built (2026-10-30, headless):** Drift King chains bank 60%; Fan Magnet is replaced by **Nitrous** (L9: hold Shift / pad L3, 1.7x engine output, a 4 s bottle refilled by skill points, gauge under the speedometer, `FreeCar.power_mul`); **Monster Truck turns everything into one**: every traffic car stands on giant wheels (`Traffic.set_monster`), and the player's truck grips like tarmac on any surface, climbs 1.8 m steps and shrugs off traffic (the train and parked cars stay stock). (c) **The Goliath** ("like Forza Horizon's Goliath"): campaign stage 10, one 27.0 km lap of the whole map (town, 4 km of S1, the northern villages and Bór ponds, the east side, back along ul. Łęcka), no road used twice, 182 side roads barred; 12 Hypercar Seicentos, the player on pole (the campaign rule: a win against a non-Easy field starts from pole), dusk; opens at the top fan level whatever the stages before (`Campaign.is_unlocked(idx, fans)`, `fan_lock`), beacon at the Fest stadium; also in the quick-race track list. Planned by `tools/plan_goliath.py` (waypoints routed on the open world's road graph), baked by `build_street_tracks.py`, which now takes a `nodes` list and a `local` source (the open world's OSM and elevation caches, no downloads). The rail AI's speed profile was the stock car's (a 216 km/h cap, stock grip): `Track.profile_for()` now builds one for the hypercar (its grip, downforce, 100 m/s) and `Race` brakes rail cars to match; stock races are untouched (parity bit-identical). Measured headless (`tests/_goliath_probe.gd`): hypercar field 703-774 s, top 326 km/h; stock field 1034-1072 s. Test `test_goliath.gd`. Not seen on screen: the track's look (27 km of surroundings, 11,483 buildings), frame time, the monster traffic, the nitro gauge. **Modifiers in every mode (user, 2026-10-30):** still unlocked by fan level and switched in one place (the open-world save), now also on the race set-up's Advanced page (a MODIFIERS fold) and used on the player's car in every race, time trial, rally and campaign stage (`Race.set_mods`, `Race._apply_mods`: ice, moon gravity on slopes, Drift King, Nitrous refilling over 25 s without skill chains, monster grip off the road; HUD bottle); Bullet Time slows the race while the player slides (`game._bullet_rate`); in the race world Monster Truck puts every car on giant wheels and Tiny/Rainbow change the player's car. Bots are unaffected, so Ice Rink makes a race much harder and Nitrous easier. Parity bit-identical (no modifiers in tests).
6. **Purpose for fans:** fans currently do nothing; give them a use (unlock events, cars or cosmetics). **Question for user:** what should fans buy or unlock?
7. **Discoverable POIs:** speed traps and other points of interest are not marked beforehand; show them on the map/minimap (discovered vs unknown) and explain them.
8a. **Graphics presets (done 2026-10-28, headless, not seen on screen):** `godot/scripts/data/graphics_presets.gd` defines Low / Medium / High (= the old defaults) / Ultra; Options has a GRAPHICS PRESET picker (Custom when a single setting is changed by hand) that sets the world's level, FSR 1 or native, anti-aliasing, ambient occlusion, shadows and reflections, and the open world follows it (shadow distance and cascades, SSAO). The `volumetric_fog` flag is in the table for the golden-hour work but nothing reads it yet. Test: `test_options.gd`. Open: look at the picker in a window, open-world draw distances per preset, auto-pick a preset on first run.
8. **Graphics mood pass (user, 2026-10-28; parked until after the budget mode ends, Fri 2026-10-30 08:00):** make the game look like two user-supplied reference images (AI stills, so aim for ~70-80%): (a) circuit at night in rain: fix night/rain lighting (blue night, warm sodium lamps, visible road edges), wet-road shader with stretched light streaks and reflections, brighter lamps with bloom halos, rain mist, lit start gantry/crowd; (b) open world at golden hour: low warm sun with long shadows and sun flare/god rays, warm grade, sunlit haze, dense foliage and conifers, fenced gardens, tall grass/flower verges, wet-looking sunlit tarmac, motion blur, speed streaks. Also "more stuff like this": more roadside life and detail (parked cars, hedges, flowers, lamp posts, signs). Needs windowed tuning screenshots.

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

## Thread assignments (2026-10-26)

What each T3 thread was given, and where it stands. One checkout (`main`), shared; the review thread commits.

| Thread | Given | Status |
|---|---|---|
| Improve Graphics to Match Racing Games | Open-world flaws from the user's screenshots: car floating on ponds, bridges ending in walls, roofs floating over walls, level-crossing booms; then street fences, gardens and foliage (Codex subagent) and a train to close the crossings | Done and committed in `f8483c4`: cars sink in ponds and respawn, bridge ramps rebaked (58 roads), walls rise to measured roofs, booms hinge and block cars, EN57 shuttles the main line with a station stop and closes 4 crossings, 4 false crossings under rail bridges removed, fences along both sides of residential streets with gates |
| Add Open-World Brzeszcze Campaign Map | Andrzej II block inside the headframe; then an open-world performance pass | Shaft fix in `ce1c862`. Performance: small props are chunked into 128 m MultiMesh cells with draw distances (fences 280 m, hedges 320, garden beds 240, parked cars 400, shelters 450, signals 500, lamps 900), committed in `f8483c4`. Frame-rate gain not yet measured in a window |
| Improve Model Accuracy and Detail | "Make the models more accurate and more detailed", then "it looks so bad, work harder": the Seicento car | Body, bumpers, lamps, tyres rebuilt from reference photos in `build_seicento.py`, `seicento.glb` rebuilt; this unfinished pass went into `f8483c4`. Stopped at the rate-limit reserve. Open: steeper tail, tail lamps raised, rear plate hidden by the bumper, jagged lens edges at the bumper, decal positions in Godot (door number, bonnet, windscreen strip, sills) must be re-measured, tests not run on the new model |
| Graphics Thread Ending Behavior | When the graphics thread ends: commit and push everything, build new `.app` and `.exe`, publish them as a GitHub release, make the repository public | Running: committed `f8483c4`; release and visibility change in progress |
| Review Finished Threads | Review and commit the other threads' work; fix the crash-out reset, lost-top-gear stutter, E key in town, README; WRC content off `main` | Fixes in `4ca9578`. WRC 3DS stages live uncommitted on branch `wrc-stages` (`../Seicento-wrc`), never on `main` (copyrighted). A three-model council review of `4ca9578` was interrupted and has no scores yet |

Still open from earlier threads: the UI second pass (duplicate open-world banners, faint street name, autopilot chip overlapping at 4:3); WRC bugs on its branch (wrong country flags, rally arches by track key in ordinary races, Sardegna gravel in the tarmac event).

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
