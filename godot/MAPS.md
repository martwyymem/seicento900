# Circuit realism roadmap

Before this work, all eleven circuits shared the same scenery: a flat green plain, scattered trees, and the same
stands, pits and gantry at the start line, with no landmarks. This file lists the updates that make each circuit
look like the real place, in the order they are being done. Tick an item when it is in the game.

Check the results with `tests/_scenery_shot.gd` (views: `high`, `aerial`, `stands`, `lap<N>`, `at<S>`):

```sh
cd godot && TRACK=spa VIEWS=high,lap1,lap3 godot --path . -s tests/_scenery_shot.gd
```

## 1. Ground truth (every circuit)

- [x] **True-scale elevation.** The renderer drew heights at 25 % (`ALTITUDE_SCALE`). At full scale you can see
      Eau Rouge/Raidillon, the Nordschleife's 290 m of climb, Monaco's hill to Casino Square and Suzuka's crossover.
      The physics ignores elevation, so lap times and the parity tests don't change.
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
- [ ] Tyre walls with belt covers at the corners where the barrier is tyres.

## 3. Landmarks (per circuit, Blender)

- [ ] Monaco: Casino de Monte-Carlo, yachts in the harbour, the Fairmont hotel over the tunnel, the swimming pool.
- [ ] Indianapolis: the Pagoda, the scoring pylon, the Yard of Bricks, grandstands round the oval.
- [ ] Le Mans: the Dunlop bridge.
- [ ] Suzuka: the Ferris wheel in the park behind the main straight.
- [ ] Monza: the old banking (sopraelevata) and the podium over the pit straight.
- [ ] Nürburgring (GP and Nordschleife): Nürburg castle on its hill.
- [ ] Spa: the Raidillon grandstand.
- [ ] Silverstone: the Wing pit building.
- [ ] Zandvoort: dunes and sand, the banked Hugenholtz and Arie Luyendyk turns.
- [ ] Fiat Track (Tychy): the Fiat Auto Poland plant halls.

## 4. Per-circuit look

- [ ] Kerb styles and colours, run-off types (painted asphalt run-off at Silverstone), barrier colours.
