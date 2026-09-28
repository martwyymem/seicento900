# Additional circuit geometry

`suzuka.csv` and `zandvoort.csv` are smoothed centreline and track-width data from
[TUMFTM/racetrack-database](https://github.com/TUMFTM/racetrack-database), whose source
coordinates originate from OpenStreetMap and whose widths were estimated from imagery.
The repository is distributed under LGPL-3.0; see its [license](https://github.com/TUMFTM/racetrack-database/blob/master/LICENSE).

Rebuild the Godot track JSON and `.tres` definitions with `python3 tools/import_godot_tracks.py`.
The source has no elevation samples, so both new circuits are currently flat. Their centreline
geometry is sampled at approximately five metre intervals and the importer selects a long straight
for the start line.
