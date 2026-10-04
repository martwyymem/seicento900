# Circuit realism roadmap

Before this work, all eleven circuits shared the same scenery: a flat green plain, scattered trees, and the same
stands, pits and gantry at the start line, with no landmarks. This file lists the updates that make each circuit
look like the real place, in the order they are being done. Tick an item when it is in the game.

Check the results with `tests/_scenery_shot.gd` (views: `high`, `aerial`, `stands`, `lap<N>`, `at<S>`, `wall<S>`, `kerb`):

```sh
cd godot && TRACK=spa VIEWS=high,lap1,lap3 godot --path . -s tests/_scenery_shot.gd
```

## 1. Ground truth (every circuit)

- [x] **True-scale elevation.** The renderer drew heights at 25 % (`ALTITUDE_SCALE`). At full scale you can see
      Eau Rouge/Raidillon, the Nordschleife's 290 m of climb, Monaco's hill to Casino Square and Suzuka's crossover.
      The physics ignores elevation, so lap times and the parity tests don't change.
- [x] **Road supports.** Where the ground falls away from the road edge (a hillside, a viaduct, a hairpin above its lower
      leg) `_build_road_supports` builds a retaining wall (city circuits) or a steep bank of the ground's own material down
      to the terrain, so the tarmac never hangs in the air. A road far below no longer drags the ground under the one above
      it down with it (`height_cap` in `_build_terrain` only counts roads within the clear distance). `tests/_gap_probe.gd`
      lists how far the ground lies below the road at each circuit. Landmarks stand on the upper ground of their footprint
      with a stone terrace down to the lowest (the Casino spans 25 m of slope).
- [x] **Suzuka's crossover bridge**: a concrete deck with parapets where the figure of eight crosses itself.
      True-scale elevation puts it 7.5 m up.
- [x] **Real surroundings from OpenStreetMap.** `tools/fetch_surroundings.py` fetches the area and
      `tools/build_surroundings.py` bakes `data/tracks/<key>_env.json` and `<key>_land.png`, which
      `scripts/ui/surroundings.gd` draws:
      - woods: trees one by one near the circuit and a canopy further out
      - every mapped building, with walls, windows and roofs in the country's colours
        (real buildings replace Monaco's random blocks)
      - lakes and rivers
      - hedgerows, rows of trees and single trees
      - roads, car parks, fields, sand and forest floor painted onto the ground
- [x] **Trees built in Blender** (`tools/blender/build_trees.py` → `models/trees.glb`): spruce, Scots pine,
      broadleaf, birch, Lombardy poplar, cypress, stone pine and palm, mixed per country.

## 2. Trackside furniture (every circuit, Blender pieces)

`tools/blender/build_furniture.py` → `models/furniture.glb`, placed by `scripts/ui/trackside_furniture.gd`.

- [x] Marshal posts along the lap, on the outside of the coming bend, each with a marshal and a flag.
- [x] Braking boards (300/200/100) before every corner that ends a straight.
- [x] Advertising hoardings on the barriers round the outside of the corners.
- [x] Footbridges and road bridges wherever OpenStreetMap maps a bridge over the circuit.
- [x] Grandstands from OpenStreetMap: every mapped `building=grandstand` is built from the stand pieces on its
      real footprint, facing the track (45 at Monza, 25 at Indianapolis, 22 at Silverstone, ...).
- [x] Paddock behind the pits: the teams' transporters in their colours.
- [x] Tyre walls with belt covers on the outside of every real bend where the barrier is tyres (Silverstone,
      Monza, Spa, GP, Fiat): `TyreWall` and `TyreWallBelt` pieces, 4 m each, a front stack of 3 tyres and a rear stack
      of 4, with a conveyor-belt cap and three bolted straps in black, white, red or blue by stretch. The plain
      barrier is left out under them, and the sponsor boards stand on top.

## 3. Landmarks (per circuit, Blender)

`tools/blender/build_landmarks.py` → `models/landmarks.glb`. `tools/build_surroundings.py` finds each landmark in
the OpenStreetMap data (`LANDMARKS` table, and rules for Ferris wheels and castle towers) and writes it to the
env file's `"landmarks"` (`[model, x, y, length, width, angle, height]`); `surroundings.gd` stretches the model
to that footprint, stands it on the ground and turns its front to the nearest track. Swimming pools go to `"pools"`.

- [x] Monaco: Casino de Monte-Carlo on its real footprint, yachts in the harbour, the Fairmont hotel over the
      tunnel (mapped building), 80+ swimming pools.
- [x] Indianapolis: the Pagoda, the scoring pylon, the Yard of Bricks at the line, grandstands round the oval
      (mapped).
- [x] Le Mans: the Dunlop bridge, as a tyre arch scaled to the run-off.
- [x] Suzuka: the Ferris wheel in the park behind the main straight.
- [x] Monza: the podium over the pit straight.
- [x] Monza: the old banking (Sopraelevata), rebuilt from its mapped centreline as a concrete slab climbing to
      the outside of each bend, with an earth bank behind it, lifted where it crosses the road course (scenery only).
- [x] Nürburgring (GP and Nordschleife): Nürburg castle on its hill (keep, towers and curtain walls).
- [x] Spa: grandstands near Raidillon (mapped stands, 8 round the circuit).
- [x] Silverstone: the Wing pit building.
- [x] Zandvoort: dunes and sand from the land map, banked Hugenholtz and Arie Luyendyk turns
      (`bank_zones` in the track definition: 18 degrees).
- [x] Fiat Track (Tychy): the Fiat Auto Poland plant halls (mapped industrial buildings).

## 4. Per-circuit look

All of it is set per circuit in `data/tracks/<key>.tres` (`TrackDef`):

- [x] **Kerbs:** `kerb_style` (red/white, yellow/black, blue/white, green/white or none), `kerb_width`, `kerb_stripe`
      (stripe length) and `kerb_height`. Monza's are wide and tall, Monaco's and the Nordschleife's narrow and low,
      the Fiat Track's yellow and black, Indianapolis has none. The kerbs were drawn facing the wrong way before and
      didn't show at all.
- [x] **Run-off:** `runoff_paved` and `runoff_paved_color` lay tarmac along the track edge inside a gravel or grass
      run-off, widest on the outside of each bend and narrowing on the inside and the straights (Silverstone 7 m,
      GP 8 m, Monza and Spa 5 m, Suzuka 2.5 m, ...).
- [x] **Barriers:** `barrier_color` paints the barrier (Monaco's lighter armco, Indianapolis's white SAFER wall), and
      tracks with `barrier = "tyres"` now have armco between their tyre walls instead of a dark slab.
