# Graphics research (2026-10-28, headless, for later windowed work)

Prepared while the session was headless-only. Nothing here was seen on screen. Items 10 and 11 of Phase 0 and the
"graphics mood pass" (Phase 1, no. 8) start from this. Web search was thin (no Godot-specific wet-road, golden-hour
or facade tutorials turned up), so most of this is read from our own code and data.

## 1. What the baked town data gives us (Brzeszcze, 12,144 buildings)

Measured from `godot/data/world/brzeszcze.json` (`buildings` entries are `[kind, height, storeys, roof, ring, "", extra]`).

| Fact | Numbers |
|---|---|
| Kinds | house 9544, shed 1211, garage 581, commercial 475, flats 171, industrial 86, public 30, farm 24, church 22 |
| Roof shape | gabled 4790, hipped 4575, flat 2578, shed 197, pyramidal 4 |
| Storeys | 1: 4986, 2: 6420, 3: 505, 4+: 230 |
| Real LoD2 roof planes (`rs`) | 8190 of 12144 (67%), from GUGiK |
| Roof colour from the orthophoto (`rc`) | 8509 (70%) |
| Wall colour (`wc`) | **none**: every wall colour is a palette pick (`_palette()` in `town_builder.gd`) |
| Function (`bd.function`) | 6697 detached houses, 2567 outbuildings, 364 garages, 219 shops/services, 200 multi-family, 114 production, 90 stores |

Consequences:
- 79% of the town is a detached house, so house variety matters most. Today a house wall is one of about 8 pastel
  colours (`HOUSE_WALLS`) plus grain noise. Roofs already vary because `rc` is real.
- Wall colour could come from the same orthophoto the baker already samples for `rc` (`tools/gugik_buildings.py`):
  sample the pixels just outside the roof edge, or accept that a top-down photo can't see walls and instead derive
  a plausible plaster colour from roof colour and storeys. Needs a decision.
- `bd.function` already separates houses, outbuildings and shops. Use it for facade type instead of only `kind`.

## 2. How buildings are drawn now

- `shaders/building.gdshader`: one shader for all baked buildings. Vertex colour = wall/roof colour, UV = metres
  along the wall and up from its foot, UV2 = seed and kind. Per-kind patterns (halls: ribbed metal; garages: dark door; roofs:
  tile courses) and a window grid via `windows()`. Night windows glow from a hash.
- `shaders/facade.gdshader`: block-of-flats facades (bays, shutters, floor bands, cornice), instanced variant.
- Both are procedural: no texture other than a noise `grain`. That is why buildings read as "boxes with windows".

Cheap upgrades, all inside these shaders (no new assets), in order of visible effect per effort:
1. **House facade kit:** a door position per building from the seed, a porch/step, a plinth band (darker 0.6 m at the
   foot), window size and frame colour variation by seed, roller shutter boxes, a chimney (geometry, not shader).
2. **Plaster types:** smooth, rough ("baranek"), brick, stone plinth. Pick by seed and function. Use the existing
   `grain` texture at different scales and normal-map strength.
3. **Insulation era look:** many Polish houses and blocks were re-clad with thermal insulation in pastel colours
   (the code already repaints flats warm). Add a second colour band (a darker plinth or a different colour on one
   storey) for part of the flats.
4. **Weathering:** a dirt gradient from the foot, rain streaks under windows and sills, roof-edge stain. Fully procedural.
5. **Per-kind geometry:** dormers, porches, garages attached to the house, fences already exist. Blender
   (`tools/blender/build_town.py`) is the place for repeated props (chimneys, dormers, porches); the baker supplies
   positions.

Historical context found (so facade types are plausible): Polish single-family houses of the 1970s are the "kostka"
(cube): plain boxes, small windows, a heavy plinth, cheap rough plaster, usually a hipped roof. The 1980s brought
pitched roofs, more complex footprints and more varied finishes. Many socialist-era houses followed catalogue designs
tied to a bank credit programme. Sources:
[Residential architecture in Poland](https://en.wikipedia.org/wiki/Residential_architecture_in_Poland),
[Gronostajska, defining space](https://dpa.arch.pk.edu.pl/wp-content/uploads/03_Definiowanie-przestrzeni-2019-tom-2_BARBARA-E.-GRONOSTAJSKA.pdf),
[modernised twin house, Sadyba](https://www.architekturaibiznes.pl/en/modernized-twin-at-sadyba,37772.html).
The Silesian dissertation on 1945-89 houses (Bródka, Silesian University of Technology) looked relevant but I could only
see its title page.

Prior art for facade shaders worth borrowing from (all CC0 or permissive; check licence before copying):
[Basic Skyscraper Window Lights on Godot Shaders](https://godotshaders.com/?p=5445) (per-cell random on/off windows).
The Godot "Home Builder" plugin builds real window cut-outs as geometry (MIT), a heavier alternative to our shader approach.

## 3. Roads, wet and night (current state)

- `shaders/road.gdshader` (circuits): per-wet `w`, puddles from noise, rain ripple normals, roughness 0.3 wet / 0.1 in puddles.
  Comment in code: "a wet sheen, not a mirror: the sky would wash the whole road out".
- `shaders/town_road.gdshader` (open world): wet darkens to 0.55 and roughness to 0.18, puddles in wheel tracks.
- `race_world.gd` sets screen-space reflections (SSR 48 steps), SSIL only at the top quality, volumetric fog only in
  fog weather (otherwise off: `volumetric_fog_enabled = false` for the quality presets, density 0.0012-0.0035 when on).
- `open_world.gd`: AgX tonemap, SSAO, glow with a 0.95 threshold dropping to 0.7 at night, softlight blend,
  saturation 1.18, a golden-hour factor feeding the sun colour, sky glow and fog light colour. Streetlamps are
  omni lights at 4.0 energy, warm (1.0, 0.8, 0.52), shadows off; headlights are spot lights at 7.0.
- Already there: night window emission, lamp emission multiplier, `lens_flare.gd`, `fx_particles.gd`.

For the two reference images (night rain circuit, golden-hour open world):
- **Streaked wet reflections:** a real fix is to stretch the reflection along the view direction in the road shader
  (sample a blurred, vertically smeared copy of the screen/sky), not to turn SSR up. SSR already exists but only shows what is on
  screen, so lamps off-screen won't streak. A cheap faked streak: for each lamp, an additive vertical quad "reflection"
  below the lamp on the wet road, fading with distance, driven by `wet` and `night`.
- **Warm sodium lamps:** change lamp colour towards (1.0, 0.72, 0.35), raise glow threshold priority, add a tiny halo sprite per lamp
  (billboard) so the bloom does not depend on the global threshold. Turn on lamp shadows only for the nearest 2-4.
- **Rain mist / god rays:** Godot 4 volumetric fog needs the Forward+ renderer (check `project.godot`; our
  race world turns it off for performance). The sun shafts in image (b) need it on with a low density (~0.002-0.004) and a directional
  light with `light_volumetric_fog_energy` raised. Cost is high on the M4 (measure with `tests/_ow_perf_probe.gd`: the open world holds the 120 Hz
  cap now, so there is room). Docs: [Volumetric fog](https://docs.godotengine.org/en/4.2/tutorials/3d/volumetric_fog.html),
  [fog volumes announcement](https://godotengine.org/article/fog-volumes-arrive-in-godot-4).
- **Golden hour:** the data already has a `golden` factor. Missing: longer shadow reach (shadow max distance is 260 m
  and the 4-split cascade may show seams at a low sun), a warm grade (`adjustment` colour correction LUT), sun flare tied to sun direction
  when the sun is in frame, and warm rim on foliage (foliage shader).
- **Motion blur and speed streaks:** Godot 4 has no built-in motion blur; do it in `retro_postprocess.gdshader` or a separate
  radial-blur pass using the car's speed. The HUD is never filtered (rule in TASKS.md Pillar 2).

## 4. Track personality (item 11): where to start

Per-track identity can be data-driven without new tools:
- Surface palette per track (`town_road.gdshader` already has slabs/gravel/tar variants): cobbles for Krakow, wet asphalt for Tokyo, etc.
- Building palette per track area: pass a palette index to `_palette()` from `areas` in the baked data (`place_town`, `place_village`,
  `place_suburb` already exist).
- Landmarks: `LANDMARKS` in `build_surroundings.py` plus `LANDMARK_SIZE`; `build_landmarks.py` for the models (the AGENTS.md pattern).
- Elevation: terrain relief is genuinely low (40 m grid, smoothed, rivers not carved: item 4 in TASKS.md). That limits character
  on the open-world stages until the baker gets a finer grid.

## 5. What needs a window, and what is safe headless

Headless-safe (no GPU needed): palette and facade-type selection logic, baker changes, Blender prop scripts (renders
come from Blender itself), tests on generated data (counts, ranges, name contract: `tests/test_model_contract.gd`).

Needs windowed screenshots: every shader change, lamp/bloom/fog tuning, shadow cascade seams, any colour judgment.
Plan one short windowed session with `tests/_open_world_shots.gd` and `_retro_shots.gd`, `--always-on-top`, `--audio-driver Dummy`
(see memory: windowed probes).

## 6. Suggested order for the windowed phase

1. House facade kit + plaster types (largest visible change, one shader, 79% of buildings).
2. Golden-hour grade, longer shadows and sun flare on the open world.
3. Sodium lamps with halos and wet-road lamp streaks at night.
4. Volumetric fog / god rays (measure cost first).
5. Per-track palettes and landmarks.

## 7. Decisions (user, 2026-10-28) and the first finding

1. **Wall colour from the aerial photo.** Checked headless on 12 random houses cropped from the cached 0.25 m orthophoto
   (`tools/open_world/cache/gugik/orto/`): it is a near-nadir image, so walls are essentially invisible (roofs, shadows, gardens),
   and some crops show trees or paving at the footprint centre, so footprint-to-photo alignment is only good to a few metres.
   A plain "sample the wall" step in `sample_roof_colours()` would give shadow and grass. Workable aerial-based options:
   (a) sample a thin band just outside the footprint and keep only light, unsaturated, non-green pixels (the lit sliver of wall
   where the building leans), fall back to the palette where nothing qualifies; (b) use the roof colour and neighbouring
   buildings as hints (red-brown roof, warm plaster; grey roof, grey or white), and keep a street-block consistent.
   Recommend (a) with (b) as the fallback, tested by counting how many buildings get a plausible colour before using it in game.
2. **Volumetric fog depends on the graphics level:** on only in the high tiers (the quality presets already exist in `race_world.gd`
   `apply_graphics()` and the Options page).
3. **Golden hour first** (open world): grade, long shadows, sun flare, warm foliage rim, then the house facade kit; the night/rain
   circuit comes after.

## 8. Still open

- How should the golden-hour look be capped on low graphics levels (no volumetric fog, no extra cascades)?
