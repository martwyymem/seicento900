# The Master Directives & Task Bible (TASKS.md)

> **MANDATORY INSTRUCTION FOR ALL AI AGENTS & MODELS**
> Read **and continuously update** this file throughout every task. It is the single source of truth for the project's shipped baseline, active work, open roadmap, and non-negotiable design rules:
> - **On task start / scope change:** add or update the work under `## Active Now`.
> - **On every milestone:** check off completed items, add newly discovered follow-ups or playtest checks, and record new invariants.
> - **On every commit / release:** update this file in the same commit so it never lags behind `HEAD` (move shipped work into `## Shipped Baseline`).
> - **With parallel subagents:** the coordinator updates `TASKS.md` for shared-checkout subagents to avoid collisions; standalone/worktree agents update it directly.
>
> Completed historical logs up to **v0.5.2-hotfix3** (`ddf5c44`) were pruned on 2026-11-22; git history remains the archive.

---

## Shipped Baseline (as of v0.5.7, 2026-11-23)

Project motto (2026-11-23): **Faster, better, harder, stronger.**

- **`0.5.7`:** difficulty & assists profile (7-step rival ladder relative to each event's design, fan multiplier x0.8-x1.5 plus assist bonuses; separate ABS/TC/stability/steering/braking aids with presets, auto/manual shifting, racing line full/braking/off; fuel use off, tyre wear off, damage off/cosmetic/full, auto-recover); dev menu only in debug builds; exports ~135 MB smaller (lossy loading photos, BC6H skies, no extension_api.json); per-frame HUD/beacon/light savings.
- **`0.5.6`:** route-finder freeze fixed (0.5.5 could hang ~1 in 6 open-world loads); faster cold/warm open-world loads (parallel buildings, threaded map load, festival cache, faster terrain/streets); night race / rain drift / fog sprint live events; 14-stage + 11-mission campaign with save migration; car GLBs 5-6 MB; rear plates on one panel; playtest fixes; test runner fails on script errors. Post-0.5.6 on `main` (`f87b605`): dev menu (§+1) only in debug builds (`OS.is_debug_build()`), `extension_api.json` (7 MB) left out of exports, lossy loading JPGs + VRAM-compressed sky HDRs (~139 MB off the export), per-frame HUD `set_stats`/`_layout` caching (~0.13 ms/frame), beacon label and festival light caching.

Everything from the original Pillars 1–9, Phases 0–4 core roadmap, and `0.5.3`–`0.5.5` is **built and shipped**:
- **21 circuits & street tracks + 5 point-to-point rally stages (26 tracks total):** 11 circuits (GP, Nordschleife, Monaco, Indy, Le Mans, Monza, Silverstone, Spa, Suzuka, Zandvoort, Fiat Track), 8 real-OSM city/street loops (Tokyo C1 + Hamarikyu Spiral, Bielsko-Biała, Kraków with tram rails & Barbakan, Oświęcim, Wilamowice with church, Brzeszcze Kopalnia, Pszczyna with castle park & wisent herd, Bór), Goliath (27 km), S1 Sprint (9.6 km), plus 5 Brzeszcze-area rally stages (Mały Bór, Kolonia Stawowa, Babudy–Góra, Rajsko–Wilczkowice, Lipowiec–Kobylec) with measured lap counts.
- **9 playable cars:** Stock Seicento 900, Hypercar Seicento (AF Corse #83, AWD, Fan L10 — with brake-by-wire, rear EBD/CBC, braking yaw-moment stability, and calibrated Goliath keyboard braking in `0.5.3`), and all 7 campaign mission reward cars — VW Golf IV (`golf4`), Dacia Logan (`logan`), Volvo V50 2.4i (`v50`), Hyundai i20 (`i20`), Dacia Sandero (`sandero`), Ford Focus Mk3.5 (`focus`), and Opel Zafira B (`zafira`) — with Blender models, split detachable bonnets (`0.5.4`), real-car physics specs, factory paint palettes, Garage turntable UI, story cast & journal, measured `LiveEvents` pace/drag tables, and dry golden-hour loading cover stills.
- **Open-world Brzeszcze campaign hub:** Non-square play area (Brzeszcze, Jawiszowice, Wola, Rajsko, east Góra, S1 U-turn loops), 13 underpasses, building passages with overhead lintels, bridge/embankment/building/lake collision matching drawn geometry, dense maize & wheat fields, cycling traffic lights, EN57 train & level crossings, real-model Polish traffic & mixed rival fields, GUGiK aerial orthophoto satnav map with directional car pointer, player waypoints with 3D purple beacon, 9 speed traps & 27 discoverable landmarks, 11 map-only campaign missions, dynamic Forza-style live events (weather-grip scaled), 10 fan levels & modifiers (`CarMods` incl. Nitrous & Monster Truck across all modes), and seeded free-roam dynamic weather (rain, dawn fog, rare hail, optional snow).
- **Modes, visuals, HUD & driving feel:** Quick Race, Rally, Time Trial (car-specific records & ghosts), customizable Championship, Campaign; Dynamic weather on roads/walls/trees/props + falling weather in open world; 6 retro post-process styles; Gran Turismo-style rear-view mirror, Camera & Screen Effects (bloom, lens flare, rear mirror, speed FOV, radial speed blur), and drift overhaul (billowing tyre smoke, darker skid trails, camera swing/roll, drift panel with angle/score/chain multiplier, player-only drift assist keeping AI/parity unchanged) (`0.5.4`); per-car racing-line braking zones, street-track 100/200/300 m braking boards, zoomed race minimap & earlier `BRAKE`/corner callouts (`0.5.3`); Neon HUD/menus/garage/loading with HUD motion, dynamic aspect ratio, HUD safe-zone width & Hor+ cameras, non-overlapping HUD stacking & pop-in fans counter; single-draw race minimap, batched road blockages, parallel/cached open-world builds (~0.9 s warm / ~7.2 s cold in debug, ~6 s in a release build); NixOS flake + SSE3 + OpenGL Compatibility support; per-suite test watchdog.
- **Damage, festival & track polish (`0.5.5`):** every car's bonnet, doors, bumpers and boot/tailgate hinge, sag and tear off as rigid bodies; wheels bend from 40 km/h and come off at 70 km/h (open world: reset with a new wheel after 3.5 s; races with mechanical damage: retirement "Lost a wheel"; cosmetic damage: bend only); spider-web windscreen cracks, shattering side/rear windows with shards, per-lamp breakage (open-world beam goes out); 14 localised crush shape keys per car plus scraped bare metal at the contact point; repair restores all (`carkit.split_damage_parts`, `tests/_crash_shots.gd`). Brzeszcze dressed as a sports festival: 3-6 row MultiMesh spectator crowds behind barriers along hub approaches and at every event gate (cheer, wave, dodge), bunting and string lights, inflatable SEICENTO FEST arches, merch stalls, sponsor flags, hay bales, night fireworks, crowd ambience (`festival_dressing.gd`); beacon labels fade near gates and out of the top HUD band. Street stages: `"verges": true` routes rail only fast-bend outsides, drops, water, bridges and embankments with open grass verges elsewhere (Bór, rally stages), horizon towns, OSM land-use `urban_ground` paving on six Polish town stages; open-world dead ends no longer run into surveyed buildings, braking boards at road height, satnav aerial import settings tracked in git; README refreshed.
- **Technical follow-ups closed (0.5.0–0.5.6):** satnav aerial `.import` settings tracked in git; open-world geometry sweep (protruding buildings, parking aisle) and street-track polish (Bór and rally stages on open verges, Bór horizon, `urban_ground` paving on six Polish town stages); README refreshed (again on 2026-11-23); per-car circuit hero stills dropped on purpose (races keep each car's cover still); test tooling: `run_tests.gd` fails a suite on any engine/script error (`OS.add_logger`) and `_mesh_fingerprint.gd` also hashes non-mesh state (`LEGACY=1` = old seven-step hashes); **route-finder freeze** (`TownMap.route` looped forever from a loop road, ~1 in 6 open-world loads in 0.5.5; fixed in `4887fc0`, shipped in 0.5.6; `test_open_world.gd` `_loop_routes`); `test_open_world_cache.gd` hang (test path only: `wait_for_stores` now joins via `_join_ahead`); cold open-world load ~10.9 -> ~7.2 s debug / ~6 s release, warm ~0.9 s (remaining debug critical path: Buildings, 2 threads in debug).

---

## Active Now — Next Release (In Flight)

**Council review priority (2026-11-23, five-model review of `f87b605`; order is the council's consensus):**

1. **Security `0.5.7`:** close the `user://` code-execution paths (mesh cache `.res`, ConfigFile `Resource(...)`, `world_assets.gd` `load()`), with a regression test. Nothing else ships before this.
2. **Release gate:** headless CI or a script running the suite, `run_qa.gd`, `_run_race_test.gd`, a boot check and a clean-HEAD export. No same-day point releases without it.
3. **Human playtest:** real gamepad, the 14-stage campaign and the gated live events, by hand, before more balance simulation.
4. **Car blend-shape size:** strip non-panel blend shapes and morph tangents (~139 MB across the car scenes).
5. **Finish the difficulty/accessibility work, then stop Batch 3** until worktrees are drained.

**Hold (do not start):** new cars, circuits, open-world areas, live-event types, festival dressing, per-car hero stills; a big split of `game.gd` while worktrees are live; the WRC branch.

- [ ] Night-rain High/Ultra frame time on the GP circuit: re-measure on an idle machine (windowed; this thread).
- [ ] **Security (review 2026-11-23, council-confirmed at `f87b605`; plan: a security-only `0.5.7`):** two code-execution paths from crafted files dropped into user://: the mesh cache loads `.res` via ResourceLoader (`town_builder.gd:252`; embedded scripts run), and user ConfigFiles accept `Resource("...")` (`game.gd:2499`, `game.gd:3928`, `race_world.gd:283`, `car_catalog.gd:422`, `world_assets.gd:107`). Fixes in progress (`store_var`/`get_var(false)` cache format, shared `load_cfg` helper that rejects Resources + JSON save hardening); needs a regression test that plants a crafted `.res` and `.cfg` and checks both are refused. Also check (unconfirmed): `world_assets.gd` calls `load()` on files under `user://assets` (a planted `.remap`/`.import` could redirect it); load those only via `Image.load_from_file` / `GLTFDocument`.
- [ ] **Optimization follow-ups (the first batch shipped in `f87b605`, see the baseline):** open: festival fireworks cost; car `.scn` blend shapes are dense (~35 of 40 MB per car, 139 MB for the eight imported scenes: 18 shapes on all 33 meshes): keep crush shapes only on body panels / drop tangents (~100 MB export + RAM/VRAM); traffic/train AI at 30-60 Hz with placement once per frame (measure first).
- [ ] **Release gate / CI (council 2026-11-23):** no CI exists and three suites sit outside `run_tests.gd` (`test_race.gd` via `_run_race_test.gd`; `test_open_world_borders.gd` and `test_car_visual_contract.gd` via `run_qa.gd`). Add one script or headless CI job: `--import`, `run_tests.gd`, `run_qa.gd`, `_run_race_test.gd`, a headless boot, and an export from a clean HEAD; no same-day point releases without it.
- [ ] **Playtest before more balancing (council 2026-11-23):** real gamepad, the 14-stage campaign and the gated live events, by hand (see the queue below).
- [x] **Difficulty & accessibility profile (shipped 0.5.7) (user request 2026-11-23):** Forza Horizon-style rival difficulty ladder (~7 steps, relative to each event's authored baseline, fan reward multiplier), assist presets (ABS/braking, steering, traction, stability, shifting, racing line) and accessibility toggles (fuel use off, tyre wear off, damage off/cosmetic/full, failures); global, saved, Quick Race defaults from it; parity race unaffected. Opus worktree delegate in progress.
- [ ] Batch 3 (2026-11-23, worktree delegates of "Complete Next Headless Tasks"): campaign-arc balance sims, event/live-event balance sims, windowed open-world look QA + fixes, better festival spectators, torn-panel edges.
- [x] Cold open-world load optimization (committed; suite + parity green): festival placement cache (warm 1.44 -> 0.91 s), parallel `_wall_edges` + per-chunk `_add_building` (release cold build 9.7 -> 6.0 s; debug capped at 2 threads, ~1 s); the faster cold `TownMap.load_map` shipped in 0.5.6. Taken by the T3 thread "Complete Next Headless Tasks" (2026-11-22). Measured cold 10.9 s / warm 1.6 s; worktree delegates: parallel `_building_meshes` (~6 s single-threaded, the cold critical path), festival placement cache (~0.65 s of every load), faster cold `TownMap.load_map` (~1.2 s).
- [x] Parallel worktree delegates batch 1 (2026-11-22): live events, campaign arc, car GLB size, playtest fixes; committed in `6e44cd5`.
- [x] Batch 2 (2026-11-23, committed in `4887fc0` + the cache-hang fix), worktree delegates of "Complete Next Headless Tasks"): release-export open-world stall, test runner script-error detection + fingerprint faces, rear-plate damage cut (Golf/Focus/Sandero), faster cold Streets/Terrain meshes, windowed QA of `6e44cd5`.

---

## Next Content & Progression

- [x] **Expanded live-event variety (committed in `6e44cd5`):** gated `night_race` (night >= 0.6, stays while >= 0.35), `rain_drift` (wetness >= 0.4 / 0.15, tiers 1.25x) and `fog_sprint` (fog >= 0.3 / 0.1) live events on sprint/drift mechanics; gate shown on card, marker and notices; fans 1.15-1.2x; `test_live_event_gates.gd`. Hail time attack skipped (hail ~5% of days, under a minute).
- [x] **Longer campaign progression arc (committed in `6e44cd5`):** 14 stages + 11 map missions in three acts; the 7 cars unlock after stages 1, 3, 5, 6, 8, 9, 11 (each still from its original mission); new: Kamil's Rematch (Pszczyna night rain), Monza, Nordschleife (fog), Le Mans (night), Sprint przez Rajsko, Drift pod Szybem, Knockout w Rajsku, Zimowy Rajd Brzeszcze (snow rally). Saves carry `"arc": 2`; `Campaign.migrate` remaps old 10-stage saves by stage id without losing cars/missions. Campaign fans now ~390k (was ~252k, ends at fan level 9). Stage list stars only won stages; NEXT STAGE only when open.

---

## Human Playtest & Feel Tuning Queue

Cannot be closed headless; collect feedback during real play sessions:

- [ ] **Open-world/street look:** slightly bare grass band 25-35 m ahead at speed (dense/sparse LOD hand-over); the house passage reads like an open carport; braking-board numbers hard to read beyond 40 m; street-name plate may lag after a teleport; check Bielsko's outskirts still show grass between blocks.
- [x] **Playtest fixes eye-checked (windowed QA 2026-11-23):** street plate right after 6 teleports + a respawn; dents/crush on the quantized GLBs match the old ones (<=0.5 mm, renders <0.02% px differ); gated live events appear/leave with their tag (night card text fixed to "gone when it gets light"); area banner held from ~50 m at gates so gate-entered areas never showed: lettering box fixed to ~1.2 m tall at 6.3 m.
- [ ] **Braking-board numbers at 100 m:** 1.5 m boards read at 60 m (12 px digits) and 40 m, not at 100 m (7 px at 900p). Decide: ~1.5-2x digits or boards nearer the road, or accept (real boards are not readable from 100 m either). Announcement tag can wrap ("NIGHT / ONLY").
- [x] **Rear plate on one panel (2026-11-23):** `carkit.split_damage_parts` keeps the whole rear plate + frame on one detachable part (Golf, Focus, Sandero now on `BootDetails`; others already clean; the build errors on a split plate); `test_car_panel_plates.gd` checks rear plates on all 9 cars. Eye-check: small step (~55 cm wide, a few cm deep) the plate frame box adds to the boot cut edge.
- [ ] **Damage & festival look:** jagged edges on torn-off panels up close; front plate on a dropped bumper; car GLBs now 5.1-6.3 MB (was 8.9-11.4; blend-shape deltas re-sparsified + KHR_mesh_quantization in `carkit.sparsify_glb`; dents/crush eye-checked in the 2026-11-23 windowed QA); area-name banner (e.g. SZCZOTKI) over arch lettering at some gates; blocky low-poly spectators.

- [ ] **Physical gamepad QA:** verify real controller feel, stick latch, `START`/`A`/`B`/`LB`/`RB`, confirm dialogs, and on-screen pad glyphs (only synthetic pad events have been tested).
- [ ] **Driving & physics feel by hand:**
  - Hypercar keyboard braking and steering feel after 0.5.3.
  - Handbrake & drift assist balance (`HB_*`, `DRIFT_*` in `physics.gd`).
  - Gravel & dirt surface handling (`SURF_GRAVEL_ROAD`, `SURF_DIRT`, Pszczyna park gravel lobe; confirm gravel 0–100 penalty isn't too harsh and dirt never beats tarmac).
- [ ] **Event & world balance by hand:**
  - Map mission rival pace and side-contact feel.
  - Drift silver/gold medal tiers, drag rival balance, and sprint gold targets.
  - New campaign arc: Nordschleife/Le Mans single laps in a stock 900 (long, P3/P2), Monza P2 after Tor Fiata, Kamil's Rematch night-rain setts and bridge visibility, town drift tiers on the real map, snow rally pace (`RALLY_PACE.hard` on snow), 8-car Rajsko knockout on narrow lanes, Kolonia off-road at medium, campaign-only fans nearing level 10.
  - Gated live events: rain-drift 1.25x tiers, 1.15-1.2x fan bonus, short rain showers removing rain drifts quickly, night/fog card and beacon readability.
  - Free-roam dynamic weather frequency (showers, dawn fog, rare hail) and wet driving feel.

---

## Design Rules & Invariants (The Bible)

Preserve these rules across all future work:

1. **Dynamic Weather:** Six conditions (`dry`, `wet`, `snow`, `hail`, `fog`, `variable`) affecting tyre friction, visuals, shaders (road, ground, buildings, foliage, canopy, landmarks), particles, and audio across both races and the open world.
2. **Retro Shaders & Readability:** All 6 retro styles (PS1, NFS MW, GTA:SA, NFS Carbon, CMR 2.0, FH1) must keep road edges, racing line, rivals, and horizon readable at speed with highlight shoulders and an **unfiltered** 2D HUD. Never claim effects in Options UI that a style doesn't implement.
3. **Real City Tracks (OSM):** Every city track is a closed loop of real public roads from OpenStreetMap with real buildings only, side-road blockages on joining streets, and no fake circuit furniture (`street_stage = true`). Keep Oświęcim ≥ 730 m from the Auschwitz I fence and never name corners after the memorial.
4. **Campaign, Missions & Progression:**
   - Campaign missions happen **only on the open-world map** (never in the campaign stage list).
   - Unlockable cars are won by beating campaign missions — no shop or currency.
   - Fans are easter eggs for fun (fan levels unlock playful `CarMods`, the Hypercar, and The Goliath at L10), never a currency for cars or events.
   - Keep the campaign difficulty curve fair (stages start in their target grid slot; failed tries ease the field down to Easy).
   - Keep copyrighted WRC 3DS content strictly off `main` (isolated on branch `wrc-stages` / `../Seicento-wrc`; its branch-only flag/arch/surface bugs stay there).
5. **Damage & Repairs:** Mechanical part-by-part damage (`service.gd`) is **on by default in Rally only** (and opt-in via "Mechanical damage" in Quick Race / "Damage & Repairs" in Championship). Circuit races, championships, and campaign stages default to cosmetic-only damage for every car; when mechanical damage is enabled, it applies symmetrically to player and AI. Zero damage must multiply physics by `1.0` (parity invariant).
6. **Menus & Controller:** Controller-first navigation (D-pad/stick, `A`/`B`/`LB`/`RB`/`START`, `◂ value ▸` selectors, visible focus ring, never lose focus). Mode is chosen on the main menu only. Support dynamic aspect ratio, HUD width safe zone, Hor+ cameras, resolution scaling, and Master/Engine/Effects/Co-driver volume sliders.
7. **Open-World Geometry:** What collides must match what is drawn (`TownMap.inside()`, `fence_pieces()`, `building_faces`, `parapet_open()`, `road_halves()`, `rail_section()`). Never use `Geometry2D.is_point_in_polygon` in open-world code.
8. **Testing & Windowed Protocol:**
   - Always validate changes with:
     ```sh
     godot --headless --path godot -s tests/run_tests.gd
     ```
     plus `tests/_run_race_test.gd` (parity race) for race/physics changes and a headless boot check (`godot --headless --path godot --quit-after 60`). Zero failure tolerance; re-baseline parity only for intentional behaviour changes and note it explicitly.
   - Refresh the global class cache (`godot --headless --path godot --import`) whenever adding a `class_name` script.
   - Default to headless runs. Only launch windowed Godot runs when the user has allowed them in the current session, one windowed agent at a time, short runs.
