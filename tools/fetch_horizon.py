"""Fetches the land round each circuit out to 40 km, for the distant terrain that race_world.gd draws behind the
scene (the hills and mountains on the horizon). Heights come from the public AWS Terrain Tiles
(Terrarium encoding, https://registry.opendata.aws/terrain-tiles/) at zoom 10, about 100 m per pixel in
Europe. The tiles are cached in tools/.tiles/, so later builds run offline.

  godot/data/tracks/<key>_far.json   {"xs": [...], "zs": [...]: the grid's column and row positions in track
                                     metres (x east, z south), close together near the circuit and further
                                     apart outwards; "h": heights in metres row by row (z then x), rounded;
                                     "sea": row-by-row 0/1, 1 where the cell is open sea}

    python3 tools/fetch_horizon.py [key ...]
"""
import io, json, math, os, sys, time, urllib.request

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import build_tracks as bt  # noqa: E402

HERE = os.path.dirname(__file__)
TILES = os.path.join(HERE, '.tiles')
GODOT_TRACKS = os.path.join(HERE, '..', 'godot', 'data', 'tracks')
URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'
ZOOM = 10
REACH = 40000.0  # metres from the circuit's terrain grid
INNER_STEP = 120.0  # grid spacing over the circuit's own terrain and just beyond it
INNER_MARGIN = 2000.0
GROWTH = 1.13  # each spacing outwards this much wider than the last

_tiles = {}

def tile(tx, ty):
    """Returns the decoded Terrarium height tile (tx, ty) at ZOOM, downloading it into TILES on first use."""
    key = (tx, ty)
    if key not in _tiles:
        path = os.path.join(TILES, f'{ZOOM}_{tx}_{ty}.png')
        if not os.path.exists(path):
            os.makedirs(TILES, exist_ok=True)
            for attempt in range(5):
                try:
                    req = urllib.request.Request(URL.format(z=ZOOM, x=tx, y=ty), headers={'User-Agent': 'seicento-game/1.0'})
                    data = urllib.request.urlopen(req, timeout=60).read()
                    break
                except Exception as e:
                    print('  retry', attempt, e)
                    time.sleep(2 + attempt * 2)
            else:
                raise SystemExit('tile download failed')
            open(path, 'wb').write(data)
        img = Image.open(path).convert('RGB')
        _tiles[key] = img.load()
    return _tiles[key]

def height_at(lat, lon):
    """Bilinear height in metres from the Terrarium tiles (r * 256 + g + b / 256 - 32768)."""
    n = 2 ** ZOOM
    fx = (lon + 180.0) / 360.0 * n * 256 - 0.5
    lr = math.radians(lat)
    fy = (1.0 - math.log(math.tan(lr) + 1.0 / math.cos(lr)) / math.pi) / 2.0 * n * 256 - 0.5
    x0, y0 = math.floor(fx), math.floor(fy)
    u, v = fx - x0, fy - y0

    def px(x, y):
        r, g, b = tile(x // 256, y // 256)[x % 256, y % 256]
        return r * 256 + g + b / 256 - 32768

    return (px(x0, y0) * (1 - u) * (1 - v) + px(x0 + 1, y0) * u * (1 - v)
            + px(x0, y0 + 1) * (1 - u) * v + px(x0 + 1, y0 + 1) * u * v)

def axis(lo, hi):
    """Positions from lo - REACH to hi + REACH: INNER_STEP apart over [lo, hi], wider and wider outside."""
    inner = [lo + i * INNER_STEP for i in range(int((hi - lo) / INNER_STEP) + 2)]
    out_hi, out_lo = [], []
    step = INNER_STEP
    p = inner[-1]
    while p < hi + REACH:
        step *= GROWTH
        p += step
        out_hi.append(p)
    p = inner[0]
    step = INNER_STEP
    while p > lo - REACH:
        step *= GROWTH
        p -= step
        out_lo.append(p)
    return [round(v, 1) for v in out_lo[::-1] + inner + out_hi]

def open_sea(h, nx, nz):
    """Cells at or below sea level joined to the grid's edge through others like them: the sea, not polders."""
    sea = [0] * (nx * nz)
    stack = [i for i in range(nx * nz) if (i % nx in (0, nx - 1) or i // nx in (0, nz - 1)) and h[i] <= 0.0]
    for i in stack:
        sea[i] = 1
    while stack:
        i = stack.pop()
        x, z = i % nx, i // nx
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, zz = x + dx, z + dz
            if 0 <= xx < nx and 0 <= zz < nz:
                j = zz * nx + xx
                if not sea[j] and h[j] <= 0.0:
                    sea[j] = 1
                    stack.append(j)
    return sea

def build(key, dem):
    """Builds <key>_far.json: a height grid, fine near the circuit and widening outwards, out to REACH."""
    g = dem['grid']
    P = bt.proj_for(key)
    x0, z0 = g['x0'], g['y0']
    x1, z1 = x0 + (g['nx'] - 1) * g['step'], z0 + (g['ny'] - 1) * g['step']
    xs = axis(x0 - INNER_MARGIN, x1 + INNER_MARGIN)
    zs = axis(z0 - INNER_MARGIN, z1 + INNER_MARGIN)
    print(key, len(xs), 'x', len(zs), flush=True)
    h = []
    for z in zs:
        for x in xs:
            lat, lon = P.inv(x, z)
            h.append(height_at(lat, lon))
    sea = open_sea(h, len(xs), len(zs))
    out = {'xs': xs, 'zs': zs, 'h': [round(max(v, 0.0)) for v in h], 'sea': sea}
    json.dump(out, open(os.path.join(GODOT_TRACKS, key + '_far.json'), 'w'), separators=(',', ':'))

def main():
    """Builds the distant terrain for every track (or those named on the command line)."""
    elevation = json.load(open(os.path.join(HERE, 'elevation.json')))
    only = sys.argv[1:]
    for key in bt.TRACKS:
        if only and key not in only:
            continue
        build(key, elevation[key])
    print('done')

if __name__ == '__main__':
    main()
