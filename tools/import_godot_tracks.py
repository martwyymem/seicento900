"""Import extra smoothed centre lines from TUMFTM/racetrack-database.

The source CSVs are kept in godot/data/tracks/sources so the Godot JSON can be
rebuilt without network access. Distances remain in the source metre frame.
"""
import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRACK_DIR = ROOT / "godot/data/tracks"


def import_track(key: str, title: str, width: float) -> None:
    rows = []
    with (TRACK_DIR / "sources" / f"{key}.csv").open() as source:
        reader = csv.reader(source, skipinitialspace=True)
        next(reader, None)  # # x_m,y_m,w_tr_right_m,w_tr_left_m
        for row in reader:
            rows.append((float(row[0]), float(row[1])))

    # Source points are already smoothed and sampled at a few metres. Find a
    # long straight for the grid/start line rather than inheriting CSV row 0.
    n = len(rows)
    scores = []
    for i in range(n):
        before = rows[(i - 8) % n]
        here = rows[i]
        after = rows[(i + 8) % n]
        a = math.atan2(here[1] - before[1], here[0] - before[0])
        b = math.atan2(after[1] - here[1], after[0] - here[0])
        turn = (b - a + math.pi) % (2 * math.pi) - math.pi
        scores.append(abs(turn))
    # Prefer a low-curvature region that remains straight for roughly 60 m.
    window = 6
    smoothed = [sum(scores[(i + j) % n] for j in range(-window, window + 1)) for i in range(n)]
    start_index = min(range(n), key=lambda i: smoothed[i])

    distances = [math.dist(rows[i], rows[(i + 1) % n]) for i in range(n)]
    length = sum(distances)
    step = length / n
    data = {
        "step": round(step, 4),
        "length": round(length, 2),
        "pts": [round(v, 3) for point in rows for v in point],
        "elev": [0.0] * n,
    }
    (TRACK_DIR / f"{key}.json").write_text(json.dumps(data, separators=(",", ":")) + "\n")

    # The simulator rotates the centreline by start_offset when loading it.
    short = "Suzuka" if key == "suzuka" else "Zandvoort"
    cfg = f'''[gd_resource type="Resource" script_class="TrackDef" format=3]

[ext_resource type="Script" path="res://scripts/data/track_def.gd" id="1"]

[resource]
script = ExtResource("1")
key = "{key}"
display_name = "{title}"
short_name = "{short}"
width = {width}
start_offset = {round(start_index * step, 2)}
pit_entry = -250.0
pit_exit = 260.0
box_start = -180.0
box_spacing = 12.0
runoff = 9.0
runoff_color = Color(0.58, 0.55, 0.46, 1)
runoff_surface = "gravel"
barrier = "armco+fence"
tree_density = 0.72
tree_patch = 0.36
tree_conifer = 0.48
grandstands = true
stands = Vector2(-100, 420)
stand_tiers = 7
'''
    (TRACK_DIR / f"{key}.tres").write_text(cfg)
    print(f"{title}: {length:.0f} m, {n} points, start {start_index * step:.0f} m")


if __name__ == "__main__":
    import_track("suzuka", "Suzuka International Racing Course", 12.0)
    import_track("zandvoort", "Circuit Zandvoort", 10.0)
