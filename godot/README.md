# Seicento 900 Cup — Godot port (work in progress)

Godot 4.7, GDScript. The JS game in the repo root stays as the reference until this version matches it.

## Layout

- `data/` — tunable resources you edit in the Inspector: `seicento.tres` (car), `tyres/*.tres` (compounds),
  `tracks/*.json` (generated centrelines + elevation; rebuild with `python3 tools/build_tracks.py`).
- `scripts/data/` — resource classes (`CarSpec`, `TyreCompound`).
- `scripts/sim/` — simulation, ported from `js/` (`CarModel` ← car.js, `Tyres`).
- `tests/` — headless parity tests against the JS version.

Coordinates: the JS/2D x (east) and y (south) map to Godot X and Z; Y is up.

## Tests

```sh
node tools/parity/car_ref.js                           # refresh JS reference values (from repo root)
godot --headless --path godot -s tests/run_tests.gd    # compare
```
