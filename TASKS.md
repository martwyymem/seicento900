# The Master Directives & Task Bible (TASKS.md)

> **MANDATORY INSTRUCTION FOR ALL AI AGENTS & MODELS**
> Read this file before planning or writing any code. It is the single source of truth for the project's active roadmap, open work, and non-negotiable design rules. Completed historical logs up to **v0.5.2-hotfix3** (`ddf5c44`) were pruned on 2026-11-22; git history remains the archive.

---

## Shipped Baseline (as of v0.5.2-hotfix3, 2026-11-22)

Everything from the original Pillars 1–9 and Phases 0–4 core roadmap is **built and shipped**:
- **21 circuits & street tracks + 5 point-to-point rally stages (26 tracks total):** 11 circuits (GP, Nordschleife, Monaco, Indy, Le Mans, Monza, Silverstone, Spa, Suzuka, Zandvoort, Fiat Track), 8 real-OSM city/street loops (Tokyo C1 + Hamarikyu Spiral, Bielsko-Biała, Kraków with tram rails & Barbakan, Oświęcim, Wilamowice with church, Brzeszcze Kopalnia, Pszczyna with castle park & wisent herd, Bór), Goliath (27 km), S1 Sprint (9.6 km), plus 5 Brzeszcze-area rally stages (Mały Bór, Kolonia Stawowa, Babudy–Góra, Rajsko–Wilczkowice, Lipowiec–Kobylec) with measured lap counts.
- **9 playable cars:** Stock Seicento 900, Hypercar Seicento (AF Corse #83, AWD, Fan L10), and all 7 campaign mission reward cars — VW Golf IV (`golf4`), Dacia Logan (`logan`), Volvo V50 2.4i (`v50`), Hyundai i20 (`i20`), Dacia Sandero (`sandero`), Ford Focus Mk3.5 (`focus`), and Opel Zafira B (`zafira`) — with Blender models, real-car physics specs, factory paint palettes, Garage turntable UI, story cast & journal, measured `LiveEvents` pace/drag tables, and dry golden-hour loading cover stills.
- **Open-world Brzeszcze campaign hub:** Non-square play area (Brzeszcze, Jawiszowice, Wola, Rajsko, east Góra, S1 U-turn loops), 13 underpasses, building passages with overhead lintels, bridge/embankment/building/lake collision matching drawn geometry, dense maize & wheat fields, cycling traffic lights, EN57 train & level crossings, real-model Polish traffic & mixed rival fields, GUGiK aerial orthophoto satnav map with directional car pointer, player waypoints with 3D purple beacon, 9 speed traps & 27 discoverable landmarks, 7 map-only campaign missions, dynamic Forza-style live events (weather-grip scaled), 10 fan levels & modifiers (`CarMods` incl. Nitrous & Monster Truck across all modes), and seeded free-roam dynamic weather (rain, dawn fog, rare hail, optional snow).
- **Modes, visuals & performance:** Quick Race, Rally, Time Trial (car-specific records & ghosts), customizable Championship, Campaign; Dynamic weather on roads/walls/trees/props + falling weather in open world; 6 retro post-process styles; Neon HUD/menus/garage/loading with HUD motion, dynamic aspect ratio, HUD safe-zone width & Hor+ cameras; single-draw race minimap, batched road blockages, parallel/cached open-world builds (~2.4 s warm / ~9.1 s cold); NixOS flake + SSE3 + OpenGL Compatibility support; per-suite test watchdog.

---

## Active Now — 0.5.3 Release (In Flight)

Driven by user feedback on the Hypercar Seicento on keyboard (weak braking, brake-steer spin, zoomed-out minimap, late corner warnings). Tracked in [`HANDOFF.md`](HANDOFF.md) while active:

- [ ] **Hypercar braking & brake-steer stability:** tune rear brake-by-wire (`CarSpec.brake_rear_grip`), ABS slip (`CarSpec.abs_slip`), and post-tap yaw damping so keyboard braking + steering stays stable on narrow street tracks (Goliath) with stronger low/mid-speed deceleration; update `LiveEvents.PACE["hypercar"]` and rail braking to match.
- [ ] **Per-car racing-line braking zones:** repaint the red braking zones from the player's driven car at race start (`race_world.gd`, `tests/test_racing_line.gd` — implemented, pending full suite & verification).
- [ ] **Braking boards on street tracks:** 100/200/300 m corner braking boards on Goliath and street loops (`trackside_furniture.gd` — implemented, pending test & windowed visual check).
- [ ] **Race minimap zoom & early corner warnings:** tighten race minimap zoom for high-speed readability and surface earlier corner / `BRAKE` callouts (`race_hud.gd`, `map_marker.gd`, `pace_notes.gd`, `co_driver.gd`).
- [ ] **Ship 0.5.3:** run full headless suite (`tests/run_tests.gd`) and parity race (`tests/_run_race_test.gd`), commit, bump to `0.5.3`, export Windows `.exe` + macOS `.app` zip from a clean `HEAD` copy, publish GitHub release, and remove `HANDOFF.md`.

---

## Next Up — Technical Follow-ups & Polish

Items surfaced by recent releases (`0.5.0`–`0.5.2-hotfix3`) and remaining loose ends:

- [ ] **Track aerial satnav `.import` settings in git:** `godot/data/world/brzeszcze_map.png.import` (mipmaps + VRAM compression: ~60 MB → ~20 MB VRAM, eliminates zoomed-out road shimmer) is currently ignored by `godot/.gitignore`, so fresh clones and non-Mac builds lose those settings. Un-ignore that file (or configure import defaults) and commit it.
- [ ] **Open-world map geometry & visual sweep:**
  - Clean up the 7 remaining surveyed OSM buildings protruding 0–1.4 m into street end segments and the 1 parking-aisle sample ending inside a shop front.
  - Windowed visual verification in motion (batch when windowed runs are OK): grass dense/sparse LOD hand-over, overhead building-passage lintels/roofs, street-track braking boards, and aerial satnav map zoom/pan.
- [ ] **Street track polish:**
  - Decide guardrails vs open verges on rural street stages (e.g. Bór currently lines both sides of the whole lap with guardrails) and add far-horizon data for Bór.
  - Audit ground shading between urban buildings on non-city street tracks (city themes such as Tokyo use grey paving `CITY_GROUND`; verify other urban Polish stages don't show bright meadow grass between blocks).
  - Re-measure High/Ultra night-rain frame time on the GP circuit on an idle machine (last measured at 24/31 ms before the 0.5.2 minimap batching & LOD fixes).
- [ ] **Refresh `README.md`:** update the stale 2026-11-08 "What's being worked on" section, track/car counts (26 tracks / 9 cars), and controls table (`Space` is handbrake, not brake).
- [ ] **Per-car circuit hero stills (decide):** races currently fall back to each car's open-world cover still; decide whether to render `hero_<track>_<car>.jpg` (`CAR=<key> tests/_loading_shots.gd`) or keep the cover fallback to avoid bloating release size.
- [ ] **Further cold open-world load optimization (optional):** warm loads are ~2.4 s; cold loads (~9.1 s) spend ~2.9 s on street geometry and ~1.6 s on JSON parsing if we want to cut cold startup further.

---

## Next Content & Progression

- [ ] **Expanded live-event variety:** add weather- and time-gated live event kinds on the open-world map (e.g. night-only street races, rain drift zones).
- [ ] **Longer campaign progression arc:** expand the campaign structure beyond the current 10 stages + 7 map missions so all 7 unlockable cars (and future additions) sit on a fuller career curve. Cars stay mission rewards — never bought with fans.

---

## Human Playtest & Feel Tuning Queue

Cannot be closed headless; collect feedback during real play sessions:

- [ ] **Physical gamepad QA:** verify real controller feel, stick latch, `START`/`A`/`B`/`LB`/`RB`, confirm dialogs, and on-screen pad glyphs (only synthetic pad events have been tested).
- [ ] **Driving & physics feel by hand:**
  - Hypercar keyboard braking and steering feel after 0.5.3.
  - Handbrake & drift assist balance (`HB_*`, `DRIFT_*` in `physics.gd`).
  - Gravel & dirt surface handling (`SURF_GRAVEL_ROAD`, `SURF_DIRT`, Pszczyna park gravel lobe; confirm gravel 0–100 penalty isn't too harsh and dirt never beats tarmac).
- [ ] **Event & world balance by hand:**
  - Map mission rival pace and side-contact feel.
  - Drift silver/gold medal tiers, drag rival balance, and sprint gold targets.
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
