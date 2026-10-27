"""Builds the open-world map of Brzeszcze (Małopolska, Poland) from OpenStreetMap, for the campaign's free roam.

    python3 tools/build_open_world.py [--refetch] [--check PNG]

The whole town inside its administrative boundary (OSM relation 2762332, admin_level 8) plus a margin of
countryside: every public road (drivable), the railway, every building, land use, water, woods, single
trees, street lamps, traffic signals, bus stops and the named places the game turns into landmarks and
event locations.

Writes godot/data/world/brzeszcze.json:

    origin [lat, lon]       projection centre; x is metres east of it, y metres south (Godot X and Z)
    bounds [x0, y0, x1, y1] the drivable area (the town's box plus DRIVE_MARGIN)
    boundary [[x, y] ...]   the town limit (the outer ring of the admin boundary)
    terrain {x0, y0, step, nx, ny, h}   ground height (m above sea level) on a grid, row-major from (x0, y0),
                            smoothed, and with every road's corridor levelled across its width
    roads [{id, n (name), k (class), w (width m), l (lanes), o (oneway), s (surface), b (bridge),
            t (tunnel), p [[x, y] ...]}]
    nodes {id: [x, y]}      road graph junctions; each road also lists "j": the indices of its points that are
                            shared with another road (junctions), and "e": the node ids at those indices
    rail [[[x, y] ...]]     railway lines (standard gauge, sidings and tramways)
    buildings [[kind, height, levels, roof, [x, y ...flat ring]]]  kind: house|flats|industrial|commercial|
                            church|garage|shed|public|farm ; roof: flat|hipped|gabled|pyramidal|dome
    areas [[kind, [x, y ...flat ring], holes?]]  land cover: forest, park, grass, farmland, water, industrial,
                            residential, cemetery, pitch, parking, allotments, scrub, wetland, brownfield
    waterways [[width, [[x, y] ...]]]
    trees [[x, y] ...]      single mapped trees and tree rows
    lamps [[x, y] ...]      street lamps (mapped ones, plus generated ones along lit roads)
    signals [[x, y] ...]    traffic signals
    stops [[x, y, name] ...] bus stops
    places [{name, kind, x, y, tags}]   named amenities, shops, churches, the mine shafts and stations

Also writes godot/data/world/brzeszcze_land.png (ground.gdshader's land map: R paved, G field crop, B bare,
A forest; LAND_RES m per texel from the terrain grid's corner) and brzeszcze_map.png (the HUD's satnav picture
over the same rectangle). --check PNG saves a top-down picture of the baked data.

Raw downloads are cached in tools/open_world/cache so rebuilds run offline. Data © OpenStreetMap
contributors, ODbL. Elevation: EU-DEM 25 m via OpenTopoData.
"""
import json, math, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'open_world', 'cache')
OUT_DIR = os.path.join(HERE, '..', 'godot', 'data', 'world')
OVERPASS = 'https://overpass-api.de/api/interpreter'
TOPO = 'https://api.opentopodata.org/v1/eudem25m'

KEY = 'brzeszcze'
BOUNDARY_REL = 2762332
TOWN_BOX = (49.9638723, 19.1099276, 50.0175934, 19.1816713)  # s, w, n, e of the admin boundary
ORIGIN = ((TOWN_BOX[0] + TOWN_BOX[2]) / 2, (TOWN_BOX[1] + TOWN_BOX[3]) / 2)
FETCH_MARGIN = 450.0  # m of countryside fetched (and ground drawn) round the playable area's bounding box
CONTENT_MARGIN = 240.0  # m beyond the playable edge that still gets buildings, trees, lamps (the fading countryside)
GRID = 40.0  # m, terrain grid spacing

# The playable area, in metres from ORIGIN (x east, y south): not a rectangle. It covers Brzeszcze, Jawiszowice,
# Wola, Rajsko and the eastern part of Góra with the S1 corridor west of town, so that the DW933 road to Góra and Wola
# and the S1 junction all lie inside. Every road that leaves it ends in a barrier, the S1 in a turn-around loop, and a
# belt of trees hides the rest of the edge.
PLAY_POLY = [(-3300, -4100), (-1000, -4200), (600, -3400), (2300, -3300), (4300, -3000), (4500, -700), (3700, 1300),
             (3300, 3000), (2600, 4200), (-900, 4520), (-1150, 4000), (-1420, 3640), (-2150, 3600), (-4300, 3300),
             (-4400, 700), (-4350, -1200), (-4150, -2150), (-3820, -2420)]

KX = 111320 * math.cos(math.radians(ORIGIN[0]))
KY = 110540


def proj(lat, lon):
    return ((lon - ORIGIN[1]) * KX, -(lat - ORIGIN[0]) * KY)


def unproj(x, y):
    return (ORIGIN[0] - y / KY, ORIGIN[1] + x / KX)


def box(margin):
    """(s, w, n, e) of the playable area's bounding box grown by margin metres."""
    xs = [p[0] for p in PLAY_POLY]
    ys = [p[1] for p in PLAY_POLY]
    s, w = unproj(min(xs) - margin, max(ys) + margin)
    n, e = unproj(max(xs) + margin, min(ys) - margin)
    return (s, w, n, e)


# ---------------------------------------------------------------- fetching

def http_post(url, fields, timeout):
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=body, headers={'User-Agent': 'seicento-game/1.0 (open world)'})
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def overpass(ql):
    for attempt in range(6):
        try:
            return http_post(OVERPASS, {'data': ql}, 400)
        except Exception as err:  # rate limit / busy server
            print('  retry', attempt, err, flush=True)
            time.sleep(15 + attempt * 20)
    raise SystemExit('Overpass failed')


def fetch_osm(refetch):
    path = os.path.join(CACHE, KEY + '_osm.json')
    if refetch or not os.path.exists(path):
        s, w, n, e = box(FETCH_MARGIN)
        b = f'({s:.6f},{w:.6f},{n:.6f},{e:.6f})'
        parts = [
            f'way["highway"]{b};',
            f'way["railway"~"^(rail|light_rail|narrow_gauge|tram|siding|abandoned|disused|platform)$"]{b};',
            f'way["building"]{b};', f'relation["building"]{b};', f'way["building:part"]{b};',
            f'way["landuse"]{b};', f'relation["landuse"]{b};',
            f'way["natural"]{b};', f'relation["natural"]{b};',
            f'way["leisure"]{b};', f'relation["leisure"]{b};',
            f'way["waterway"]{b};', f'relation["waterway"]{b};',
            f'way["amenity"]{b};', f'node["amenity"]{b};',
            f'way["man_made"]{b};', f'node["man_made"]{b};',
            f'nwr["shop"]{b};', f'nwr["tourism"]{b};', f'nwr["historic"]{b};', f'nwr["office"]{b};',
            f'node["highway"~"^(street_lamp|traffic_signals|bus_stop|crossing|stop|give_way)$"]{b};',
            f'node["public_transport"]{b};', f'node["railway"~"^(level_crossing|station|halt|crossing)$"]{b};',
            f'node["natural"="tree"]{b};', f'way["barrier"~"^(hedge|wall|fence)$"]{b};',
            f'node["place"]{b};',
            f'relation({BOUNDARY_REL});',
        ]
        ql = '[out:json][timeout:300];(' + ''.join(parts) + ');out body geom;'
        print('fetching OSM', b, flush=True)
        data = overpass(ql)
        os.makedirs(CACHE, exist_ok=True)
        json.dump(data, open(path, 'w'), separators=(',', ':'))
        print(f'  {len(data["elements"])} elements, {os.path.getsize(path) // 1024} KB', flush=True)
    return json.load(open(path))


def grid_frame():
    """(x0, y0, nx, ny) of the terrain grid: the fetched box, snapped to GRID."""
    s, w, n, e = box(FETCH_MARGIN)
    x0, y0 = proj(n, w)
    x1, y1 = proj(s, e)
    x0, y0 = math.floor(x0 / GRID) * GRID, math.floor(y0 / GRID) * GRID
    nx = int(math.ceil((x1 - x0) / GRID)) + 1
    ny = int(math.ceil((y1 - y0) / GRID)) + 1
    return x0, y0, nx, ny


def fetch_elevation(refetch):
    """EU-DEM heights on the grid. Nodes already fetched (the cache is keyed by position, so a grown grid reuses
    them) are kept; only the missing ones are requested, 100 per call."""
    path = os.path.join(CACHE, KEY + '_elevation.json')
    x0, y0, nx, ny = grid_frame()
    known = {}
    for src in (path, os.path.join(CACHE, KEY + '_elevation_old.json')):
        if os.path.exists(src) and not refetch:
            og = json.load(open(src))
            for j in range(og['ny']):
                for i in range(og['nx']):
                    known[(round(og['x0'] + i * og['step']), round(og['y0'] + j * og['step']))] = og['h'][j * og['nx'] + i]
    nodes = [(round(x0 + i * GRID), round(y0 + j * GRID)) for j in range(ny) for i in range(nx)]
    missing = [k for k in nodes if k not in known]
    print(f'elevation {nx}x{ny} = {len(nodes)} points, {len(missing)} to fetch', flush=True)
    os.makedirs(CACHE, exist_ok=True)

    def save():
        json.dump({'x0': x0, 'y0': y0, 'step': GRID, 'nx': nx, 'ny': ny, 'h': [round(known.get(k, 0.0), 2) for k in nodes]},
                  open(path, 'w'))
    for c in range(0, len(missing), 100):
        chunk = missing[c:c + 100]
        for attempt in range(8):
            try:
                res = http_post(TOPO, {'locations': '|'.join('%.6f,%.6f' % unproj(x, y) for x, y in chunk)}, 60)
                if res.get('status') == 'OK':
                    break
            except Exception as err:
                print('  retry', attempt, err, flush=True)
            time.sleep(3 + attempt * 4)
        else:
            raise SystemExit('elevation API failed')
        for k, r in zip(chunk, res['results']):
            known[k] = r['elevation'] if r['elevation'] is not None else 0.0
        if (c // 100) % 20 == 19:
            print(f'  {c + 100}/{len(missing)}', flush=True)
        time.sleep(1.05)
    save()
    return json.load(open(path))


# ---------------------------------------------------------------- building

sys.path.insert(0, HERE)
import build_surroundings as bs  # noqa: E402  (ring joining, simplification, OSM numbers)

DRIVABLE = {
    # class: (default width m, lanes, paved)
    'motorway': (8.0, 2, True), 'motorway_link': (5.0, 1, True), 'trunk': (8.0, 2, True), 'trunk_link': (5.0, 1, True),
    'primary': (7.5, 2, True), 'primary_link': (5.0, 1, True), 'secondary': (7.2, 2, True),
    'secondary_link': (5.0, 1, True), 'tertiary': (6.4, 2, True), 'tertiary_link': (5.0, 1, True),
    'unclassified': (5.4, 2, True), 'residential': (5.4, 2, True), 'living_street': (4.5, 1, True),
    'pedestrian': (5.0, 1, True), 'service': (4.0, 1, True), 'track': (3.0, 1, False), 'road': (5.0, 2, True),
}
UNPAVED = {'unpaved', 'gravel', 'dirt', 'ground', 'grass', 'sand', 'compacted', 'fine_gravel', 'earth', 'mud', 'pebblestone'}
CLASS_ID = {k: i for i, k in enumerate(DRIVABLE)}
RAMP_GRADE = 0.06  # embankment ramps up to a road bridge
RAIL_RAMP_GRADE = 0.02
UNDERPASS_Z = 5.4  # m: a railway over a road underpass has its deck this high (4.5 m of headroom under the slab)
CLEARANCE_ROAD = 6.0  # deck height of a bridge with a road or railway under it
CLEARANCE_WATER = 2.2
AREA_KINDS = [
    # (kind, [(key, value) ...]) in drawing order: later kinds cover earlier ones
    ('farmland', [('landuse', 'farmland'), ('landuse', 'orchard'), ('landuse', 'plant_nursery'), ('landuse', 'farmyard')]),
    ('meadow', [('landuse', 'meadow'), ('natural', 'grassland'), ('landuse', 'grass'), ('landuse', 'village_green'),
                ('landuse', 'greenfield'), ('landuse', 'recreation_ground')]),
    ('residential', [('landuse', 'residential')]),
    ('industrial', [('landuse', 'industrial'), ('landuse', 'railway'), ('landuse', 'garages'), ('landuse', 'commercial'),
                    ('landuse', 'retail'), ('man_made', 'wastewater_plant'), ('landuse', 'landfill')]),
    ('brownfield', [('landuse', 'brownfield'), ('landuse', 'construction'), ('landuse', 'quarry'), ('natural', 'sand'),
                    ('natural', 'bare_rock')]),
    ('scrub', [('natural', 'scrub'), ('natural', 'heath')]),
    ('wetland', [('natural', 'wetland')]),
    ('allotments', [('landuse', 'allotments')]),
    ('cemetery', [('landuse', 'cemetery'), ('landuse', 'religious')]),
    ('park', [('leisure', 'park'), ('leisure', 'garden'), ('leisure', 'playground'), ('leisure', 'nature_reserve')]),
    ('forest', [('landuse', 'forest'), ('natural', 'wood')]),
    ('pitch', [('leisure', 'pitch'), ('leisure', 'stadium'), ('leisure', 'track'), ('leisure', 'sports_centre')]),
    ('parking', [('amenity', 'parking')]),
    ('water', [('natural', 'water'), ('landuse', 'basin'), ('landuse', 'reservoir'), ('waterway', 'riverbank')]),
]


class Proj:
    """build_surroundings' projection interface: called on an OSM {lat, lon}."""
    def __call__(self, p):
        return proj(p['lat'], p['lon'])


P = Proj()


def r1(v):
    return round(v, 1)


def seg_len(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def densify(pts, step):
    """Adds points so no segment is longer than step (the roads follow the terrain between OSM nodes)."""
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.ceil(math.dist(a, b) / step)))
        for k in range(1, n + 1):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def smooth_grid(g, passes):
    """Box-blurs the height grid (EU-DEM carries tree and roof noise in town)."""
    nx, ny, h = g['nx'], g['ny'], list(g['h'])
    for _ in range(passes):
        out = h[:]
        for j in range(ny):
            for i in range(nx):
                acc, wt = 0.0, 0.0
                for dj in (-1, 0, 1):
                    for di in (-1, 0, 1):
                        a, b = i + di, j + dj
                        if 0 <= a < nx and 0 <= b < ny:
                            w = 4.0 if di == 0 and dj == 0 else (2.0 if di == 0 or dj == 0 else 1.0)
                            acc += h[b * nx + a] * w
                            wt += w
                out[j * nx + i] = acc / wt
        h = out
    return h


def point_in_ring(x, y, ring):
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def seg_cross(a, b, c, d):
    """Whether segments ab and cd cross (proper intersection)."""
    def orient(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0)


class SegGrid:
    """A spatial hash of polyline segments, for "what is near here" during the build."""
    def __init__(self, cell=40.0):
        self.cell, self.cells = cell, {}

    def add(self, a, b, item):
        c = self.cell
        x0, x1 = sorted((a[0], b[0]))
        y0, y1 = sorted((a[1], b[1]))
        for i in range(int(math.floor(x0 / c)), int(math.floor(x1 / c)) + 1):
            for j in range(int(math.floor(y0 / c)), int(math.floor(y1 / c)) + 1):
                self.cells.setdefault((i, j), []).append((a, b, item))

    def near(self, x, y, r):
        c = self.cell
        seen = []
        for i in range(int(math.floor((x - r) / c)), int(math.floor((x + r) / c)) + 1):
            for j in range(int(math.floor((y - r) / c)), int(math.floor((y + r) / c)) + 1):
                seen.extend(self.cells.get((i, j), ()))
        return seen


def dist_seg(px, py, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((px - a[0]) * dx + (py - a[1]) * dy) / l2))
    return math.hypot(px - a[0] - dx * t, py - a[1] - dy * t)


def poly_dist(x, y, poly):
    """Distance from (x, y) to the polygon's outline."""
    return min(dist_seg(x, y, a, b) for a, b in zip(poly, poly[1:] + poly[:1]))


def in_zone(x, y, margin=0.0):
    """Inside the playable polygon, or within margin metres of it."""
    if point_in_ring(x, y, PLAY_POLY):
        return True
    return margin > 0 and poly_dist(x, y, PLAY_POLY) <= margin


def edge_hit(a, b, poly):
    """The point where segment a->b (a inside, b outside the polygon) leaves it: the crossing nearest a."""
    best = None
    ax, ay = a
    dx, dy = b[0] - ax, b[1] - ay
    for c, d in zip(poly, poly[1:] + poly[:1]):
        ex, ey = d[0] - c[0], d[1] - c[1]
        den = dx * ey - dy * ex
        if abs(den) < 1e-9:
            continue
        t = ((c[0] - ax) * ey - (c[1] - ay) * ex) / den
        u = ((c[0] - ax) * dy - (c[1] - ay) * dx) / den
        if 0 <= t <= 1 and 0 <= u <= 1 and (best is None or t < best):
            best = t
    best = 0.5 if best is None else best
    return (ax + dx * best, ay + dy * best)


_FAKE_IDS = [0]


def fake_id():
    _FAKE_IDS[0] -= 1
    return _FAKE_IDS[0]


def clip_to_play(ids, pts):
    """Cuts a polyline at the playable polygon. Returns [(ids, pts, cut_start, cut_end)] for the parts inside; a cut
    end sits exactly on the polygon's edge and carries a fresh id (so it isn't a junction)."""
    inside = [point_in_ring(x, y, PLAY_POLY) for x, y in pts]
    if all(inside):
        return [(ids, pts, False, False)]
    out, cur_i, cur_p, cs = [], [], [], False
    for k in range(len(pts)):
        if inside[k]:
            if not cur_p and k > 0:
                cur_i, cur_p, cs = [fake_id()], [edge_hit(pts[k], pts[k - 1], PLAY_POLY)], True
            cur_i.append(ids[k])
            cur_p.append(pts[k])
        elif cur_p:
            cur_i.append(fake_id())
            cur_p.append(edge_hit(pts[k - 1], pts[k], PLAY_POLY))
            out.append((cur_i, cur_p, cs, True))
            cur_i, cur_p, cs = [], [], False
    if cur_p:
        out.append((cur_i, cur_p, cs, False))
    return [o for o in out if len(o[1]) >= 2 and seg_len(o[1]) > 25.0]


def trim_end(ids, pts, length, from_end):
    """Drops the last (or first) length metres of a polyline; returns (ids, pts) with a fresh vertex at the cut."""
    if not from_end:
        i2, p2 = trim_end(ids[::-1], pts[::-1], length, True)
        return i2[::-1], p2[::-1]
    length = min(length, seg_len(pts) * 0.5)
    run, k = 0.0, len(pts) - 1
    while k > 1 and run + math.dist(pts[k], pts[k - 1]) < length:
        run += math.dist(pts[k], pts[k - 1])
        k -= 1
    a, b = pts[k - 1], pts[k]
    t = (length - run) / max(math.dist(a, b), 1e-6)
    cut = (b[0] + (a[0] - b[0]) * t, b[1] + (a[1] - b[1]) * t)
    return ids[:k] + [fake_id()], pts[:k] + [cut]


def u_turn(e_pt, e_dir, s_pt, s_dir, reach):
    """A cubic Bezier from e_pt (leaving along unit e_dir) to s_pt (arriving along unit s_dir) that bulges forward."""
    p0, p3 = e_pt, s_pt
    p1 = (p0[0] + e_dir[0] * reach, p0[1] + e_dir[1] * reach)
    p2 = (p3[0] - s_dir[0] * reach, p3[1] - s_dir[1] * reach)
    pts = []
    for i in range(0, 13):
        t = i / 12
        m = 1 - t
        pts.append((m ** 3 * p0[0] + 3 * m * m * t * p1[0] + 3 * m * t * t * p2[0] + t ** 3 * p3[0],
                    m ** 3 * p0[1] + 3 * m * m * t * p1[1] + 3 * m * t * t * p2[1] + t ** 3 * p3[1]))
    return pts


def rand01(x, y, salt):
    v = math.sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
    return v - math.floor(v)


def building_spec(tags, ring):
    """(kind, wall height m, levels, roof shape) of a building from its tags and footprint."""
    a = bs.area(ring + [ring[0]] if ring[0] != ring[-1] else ring)
    b = tags.get('building', 'yes')
    lv = bs.number(tags.get('building:levels'))
    h = bs.number(tags.get('height'))
    roof = tags.get('roof:shape')
    kind = 'house'
    if b in ('apartments', 'residential', 'dormitory'):
        kind = 'flats' if a > 160 else 'house'
    elif b in ('industrial', 'warehouse', 'manufacture', 'hangar', 'service', 'transformer_tower', 'silo'):
        kind = 'industrial'
    elif b in ('retail', 'commercial', 'supermarket', 'office', 'kiosk', 'hotel'):
        kind = 'commercial'
    elif b in ('church', 'chapel', 'cathedral'):
        kind = 'church'
    elif b in ('garage', 'garages', 'carport'):
        kind = 'garage'
    elif b in ('shed', 'outbuilding', 'roof', 'greenhouse', 'hut', 'cabin', 'construction'):
        kind = 'shed'
    elif b in ('school', 'kindergarten', 'public', 'fire_station', 'hospital', 'civic', 'government', 'train_station',
               'sports_hall', 'university', 'college'):
        kind = 'public'
    elif b in ('barn', 'farm_auxiliary', 'cowshed', 'stable', 'farm'):
        kind = 'farm'
    elif b == 'yes':
        kind = 'shed' if a < 30 else ('house' if a < 260 else ('commercial' if a < 1500 else 'industrial'))
    if kind == 'house' and a < 30:
        kind = 'shed'
    if h is None:
        if lv is not None:
            h = lv * 2.9 + (0.6 if kind in ('flats', 'public', 'commercial') else 0.3)
        else:
            h = {'house': 5.6, 'flats': 13.0 if a < 900 else 15.0, 'industrial': 10.0 if a < 3000 else 13.0,
                 'commercial': 5.5 if a < 600 else 7.5, 'church': 16.0, 'garage': 2.7, 'shed': 2.8, 'public': 9.0,
                 'farm': 5.0}[kind]
            if kind == 'house' and a > 160:
                h = 6.4
    else:
        h = max(2.5, h)
    if lv is None:
        lv = max(1, int(round(h / 2.9)))
    if roof not in ('flat', 'hipped', 'gabled', 'pyramidal', 'dome', 'skillion'):
        roof = None
    if roof is None:
        if kind in ('house', 'farm'):
            roof = 'hipped' if rand01(ring[0][0], ring[0][1], 3.0) < 0.62 else 'gabled'
        elif kind == 'church':
            roof = 'gabled'
        elif kind == 'public':
            roof = 'hipped' if a < 900 else 'flat'
        else:
            roof = 'flat'
    if roof == 'skillion':
        roof = 'flat'
    return kind, round(h, 1), lv, roof


def building_measurements():
    """Load the compact, offline GUGiK extract and index measured buildings by local footprint."""
    path = os.path.join(CACHE, KEY + '_gugik.json')
    if not os.path.exists(path):
        return {}
    data = json.load(open(path, encoding='utf-8'))
    # Centre-based bins keep conflation cheap while the final candidate check uses footprint bounds.
    index = {}
    def add(layer, rec):
        ring = rec.get('ring', [])
        if len(ring) < 3:
            return
        cx = sum(p[0] for p in ring) / len(ring)
        cy = sum(p[1] for p in ring) / len(ring)
        index.setdefault((int(cx // 32), int(cy // 32)), []).append((layer, rec, cx, cy, _ring_bounds(ring)))
    for rec in data.get('lod2', []): add('lod2', rec)
    for rec in data.get('lod1', []): add('lod1', rec)
    for rec in data.get('bdot', []): add('bdot', rec)
    colours = {}
    orto = data.get('orto', {})
    for x, y, r, g, b in orto.get('cols', []):
        colours[(round(x / 8), round(y / 8))] = '#%02x%02x%02x' % (r, g, b)
    print('GUGiK measurements indexed:', {k: sum(1 for v in index.values() for x in v if x[0] == k)
                                          for k in ('lod2', 'lod1', 'bdot')},
          'roof colours:', len(colours), flush=True)
    return {'index': index, 'colours': colours, 'matched': set()}


def _ring_bounds(ring):
    return (min(p[0] for p in ring), min(p[1] for p in ring), max(p[0] for p in ring), max(p[1] for p in ring))


def _ring_area_abs(ring):
    return abs(sum(ring[i][0] * ring[(i + 1) % len(ring)][1] - ring[(i + 1) % len(ring)][0] * ring[i][1]
                   for i in range(len(ring))) * 0.5)


def _inside_ring(x, y, ring):
    inside = False
    j = len(ring) - 1
    for i, (xi, yi) in enumerate(ring):
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _intersection_area_sampled(a, b, bounds):
    """Approximate polygon intersection with 1 m cell-centre samples for robust non-convex footprints."""
    x0, y0, x1, y1 = bounds
    step = 1.0
    hits = 0
    for iy in range(int(math.ceil(y0 / step)), int(math.floor(y1 / step))):
        y = (iy + 0.5) * step
        for ix in range(int(math.ceil(x0 / step)), int(math.floor(x1 / step))):
            x = (ix + 0.5) * step
            if _inside_ring(x, y, a) and _inside_ring(x, y, b):
                hits += 1
    return float(hits) * step * step


def conflate_building(ring, osm_id, osm_type, measurements):
    """Return append-only record metadata: measured heights/roof geometry/colour and source ids."""
    if not measurements:
        return {'id': ('r' if osm_type == 'relation' else 'w') + str(osm_id)}
    index = measurements['index']
    bounds = _ring_bounds(ring)
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    candidates = []
    for ix in range(int(cx // 32) - 1, int(cx // 32) + 2):
        for iy in range(int(cy // 32) - 1, int(cy // 32) + 2):
            candidates.extend(index.get((ix, iy), []))
    def score(item):
        layer, rec, mx, my, mb = item
        if abs(cx - mx) > 24 or abs(cy - my) > 24:
            return -1.0
        ix0, iy0 = max(bounds[0], mb[0]), max(bounds[1], mb[1])
        ix1, iy1 = min(bounds[2], mb[2]), min(bounds[3], mb[3])
        inter = _intersection_area_sampled(ring, rec['ring'], (ix0, iy0, ix1, iy1))
        aa = max(1.0, _ring_area_abs(ring))
        ab = max(1.0, _ring_area_abs(rec['ring']))
        iou = inter / max(1.0, aa + ab - inter)
        # Prioritize real footprint overlap; centroid proximity resolves attached/outbuilding duplicates.
        return iou - math.hypot(cx - mx, cy - my) / 500.0
    ranked = sorted(((score(c), c) for c in candidates), key=lambda x: x[0], reverse=True)
    chosen = {}
    for layer in ('lod2', 'lod1', 'bdot'):
        hit = next((item for value, item in ranked if item[0] == layer and value > 0.12), None)
        if hit:
            chosen[layer] = hit[1]
    extra = {'id': ('r' if osm_type == 'relation' else 'w') + str(osm_id)}
    l2, l1, bd = chosen.get('lod2'), chosen.get('lod1'), chosen.get('bdot')
    if l2:
        extra['src'] = 'GUGiK LoD2 2017'
        if l2.get('roofs'):
            extra['rs'] = l2['roofs']
        rt = int(l2.get('rt', 0))
        extra['roof_code'] = rt
        # GUGiK's roofType uses CityGML's code list.
        roof_types = {1000: 'flat', 1010: 'shed', 1020: 'shed', 1030: 'gabled', 1040: 'hipped',
                      1050: 'half_hipped', 1060: 'mansard', 1070: 'pyramidal', 1080: 'dome',
                      1090: 'dome', 1100: 'shed', 1120: 'pyramidal'}
        if rt in roof_types:
            extra['roof'] = roof_types[rt]
    if l1:
        total_h = float(l1.get('h', 0))
        extra['eh'] = round(total_h * 0.72, 1)
        extra['rh'] = round(total_h, 1)
        extra['src'] = (extra.get('src', '') + ' + ' if extra.get('src') else '') + 'GUGiK LoD1 2024'
    if l2 and l2.get('roofs'):
        zvals = [float(face[i + 2]) for face in l2['roofs'] for i in range(0, len(face) - 2, 3)]
        if zvals:
            extra['eh'] = round(min(zvals), 1)
            extra['rh'] = round(max(zvals), 1)
    if bd:
        extra['bd'] = {'function': bd.get('pf', ''), 'storeys': bd.get('lk')}
        if not extra.get('eh') and bd.get('lk'):
            try: extra['eh'] = round(float(bd['lk']) * 2.9, 1)
            except (TypeError, ValueError): pass
        if not extra.get('src'): extra['src'] = 'GUGiK BDOT10k'
    colour = measurements['colours'].get((round(cx / 8), round(cy / 8)))
    if colour:
        extra['rc'] = colour
        extra['src'] = (extra.get('src', '') + ' + ' if extra.get('src') else '') + 'GUGiK orthophoto'
    for layer, record in chosen.items():
        if record.get('id'):
            measurements['matched'].add((layer, str(record['id'])))
    return extra


def build(check_png=None):
    data = fetch_osm(False)
    elev = fetch_elevation(False)
    els = data['elements']
    nodes_tags = {e['id']: e for e in els if e['type'] == 'node'}

    # ---- terrain
    hs = smooth_grid(elev, 2)
    tx0, ty0, tstep, tnx, tny = elev['x0'], elev['y0'], elev['step'], elev['nx'], elev['ny']

    def ground(x, y):
        fx = min(max((x - tx0) / tstep, 0.0), tnx - 1.001)
        fy = min(max((y - ty0) / tstep, 0.0), tny - 1.001)
        i, j = int(fx), int(fy)
        u, v = fx - i, fy - j
        a = hs[j * tnx + i]
        b = hs[j * tnx + i + 1]
        c = hs[(j + 1) * tnx + i]
        d = hs[(j + 1) * tnx + i + 1]
        return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v

    bx0, by0 = min(p[0] for p in PLAY_POLY), min(p[1] for p in PLAY_POLY)
    bx1, by1 = max(p[0] for p in PLAY_POLY), max(p[1] for p in PLAY_POLY)
    fs_, fw_, fn_, fe_ = box(FETCH_MARGIN)
    fx0, fy0 = proj(fn_, fw_)
    fx1, fy1 = proj(fs_, fe_)

    # ---- town limit
    boundary = []
    for e in els:
        if e['type'] == 'relation' and e['id'] == BOUNDARY_REL:
            outer, _ = bs.rings_of(e, P)
            if outer:
                boundary = max(outer, key=lambda r: bs.area(r))
    print('boundary', len(boundary), 'points')

    # ---- roads
    use = {}
    roads = []
    for e in els:
        t = e.get('tags', {})
        k = t.get('highway')
        if e['type'] != 'way' or k not in DRIVABLE or t.get('area') == 'yes':
            continue
        if t.get('access') in ('no',) and k == 'service':
            continue
        if k == 'service' and t.get('service') in ('driveway',) and seg_len([P(p) for p in e['geometry']]) < 25:
            continue
        ids = e.get('nodes', [])
        pts = [P(p) for p in e['geometry']]
        if len(pts) < 2 or len(ids) != len(pts):
            continue
        for pi, pp, cs, ce in clip_to_play(ids, pts):
            roads.append([e, k, t, pi, pp, cs, ce])
    # ends that leave the playable polygon become barriers (closures); the S1's carriageways turn round instead
    closures = []
    s1_out, s1_in = [], []
    for r in roads:
        e, k, t, pi, pp, cs, ce = r
        if k == 'motorway' and (cs or ce):
            (s1_out if ce else s1_in).append(r)
    for ro in s1_out:
        # the inbound carriageway whose start is nearest this outbound end
        cands = [ri for ri in s1_in if math.dist(ri[4][0], ro[4][-1]) < 90]
        if not cands:
            continue
        ri = min(cands, key=lambda c: math.dist(c[4][0], ro[4][-1]))
        ro[3], ro[4] = trim_end(ro[3], ro[4], 70.0, True)
        ri[3], ri[4] = trim_end(ri[3], ri[4], 70.0, False)
        ro[6], ri[5] = False, False
        a, b = ro[4][-2], ro[4][-1]
        d1 = math.dist(a, b) or 1.0
        ed = ((b[0] - a[0]) / d1, (b[1] - a[1]) / d1)
        a, b = ri[4][0], ri[4][1]
        d2 = math.dist(a, b) or 1.0
        sd = ((b[0] - a[0]) / d2, (b[1] - a[1]) / d2)
        loop = u_turn(ro[4][-1], ed, ri[4][0], sd, 48.0)
        loop_ids = [ro[3][-1]] + [fake_id() for _ in loop[1:-1]] + [ri[3][0]]
        roads.append([{'id': 9000000000 + len(roads), 'tags': {}}, 'motorway_link', {'highway': 'motorway_link', 'name': 'S1'},
                      loop_ids, loop, False, False])
        apex = max(loop, key=lambda q: (q[0] - ro[4][-1][0]) * ed[0] + (q[1] - ro[4][-1][1]) * ed[1])
        closures.append({'x': apex[0] + ed[0] * 14.0, 'y': apex[1] + ed[1] * 14.0, 'h': math.atan2(ed[1], ed[0]),
                         'w': 26.0, 'kind': 'motorway', 'name': 'S1', 'road': ro[0]['id'], 'turn': True})
    for e, k, t, ids, pts, cs, ce in roads:
        for nid in ids:
            use[nid] = use.get(nid, 0) + 1
    # a road that ends at (or within a few metres of) the polygon's edge is closed with a barrier across it
    for e, k, t, ids, pts, cs, ce in roads:
        if k == 'motorway':
            continue
        for end_id, pts_ in ((ids[0], pts), (ids[-1], pts[::-1])):
            q, nxt = pts_[0], pts_[1]
            if use[end_id] != 1 or poly_dist(q[0], q[1], PLAY_POLY) > 40.0:
                continue
            run, j = 0.0, 0  # the barrier stands a few metres inside
            while j < len(pts_) - 1 and run < 4.0:
                run += math.dist(pts_[j], pts_[j + 1])
                j += 1
            b0 = pts_[j]
            if any(math.dist(b0, (c['x'], c['y'])) < 12.0 for c in closures):
                continue
            closures.append({'x': b0[0], 'y': b0[1], 'h': math.atan2(q[1] - nxt[1], q[0] - nxt[0]), 'w': 0.0, 'kind': k,
                             'name': t.get('name', '') or t.get('ref', ''), 'road': e['id'], 'turn': False})
    roads = [tuple(r[:5]) for r in roads]
    # junctions: nodes on two or more roads (or twice on one), plus road ends
    junction = {nid for nid, c in use.items() if c >= 2}
    out_roads = []
    node_xy = {}
    for e, k, t, ids, pts in roads:
        w0, lanes0, paved = DRIVABLE[k]
        width = bs.number(t.get('width'))
        lanes = int(bs.number(t.get('lanes')) or lanes0)
        if width is None or width < 2.5 or width > 20:
            width = w0
            if t.get('lanes') and k not in ('service', 'track'):
                width = max(w0, lanes * (3.5 if k.startswith('motorway') else 3.1) + 0.6)
        if k == 'service' and t.get('service') == 'parking_aisle':
            width = 5.0
        if k == 'service' and t.get('service') == 'driveway':
            width = 3.0
        surface = t.get('surface', '')
        unpaved = surface in UNPAVED or (k == 'track' and surface not in ('asphalt', 'concrete', 'paved', 'concrete:plates'))
        sid = 2 if unpaved else (1 if surface in ('paving_stones', 'sett', 'cobblestone', 'concrete:plates') else 0)
        oneway = t.get('oneway') in ('yes', '1', 'true') or k in ('motorway', 'motorway_link') or t.get('junction') == 'roundabout'
        # keep the junction nodes, simplify the rest, then densify for the terrain
        keep = [0] + [i for i, nid in enumerate(ids) if nid in junction and 0 < i < len(ids) - 1] + [len(ids) - 1]
        dense, marks = [], []
        for a, b in zip(keep, keep[1:]):
            part = bs.simplify(pts[a:b + 1], 0.25)
            part = densify(part, 6.0)
            if dense:
                part = part[1:]
            start = len(dense)
            dense.extend(part)
            if not marks:
                marks.append((0, ids[a]))
            marks.append((len(dense) - 1, ids[b]))
        for idx, nid in marks:
            node_xy[nid] = (r1(dense[idx][0]), r1(dense[idx][1]))
        out_roads.append({'id': e['id'], 'n': t.get('name', '') or t.get('ref', ''), 'ref': t.get('ref', ''),
                          'k': CLASS_ID[k], 'kn': k, 'w': round(width, 1), 'l': lanes, 'o': 1 if oneway else 0, 's': sid,
                          'b': 1 if t.get('bridge') in ('yes', 'viaduct') else 0,
                          'tn': 1 if t.get('tunnel') in ('yes',) else 0,
                          'lit': 1 if t.get('lit') == 'yes' else 0,
                          'rb': 1 if t.get('junction') == 'roundabout' else 0,
                          'p': dense, 'e': marks,
                          'maxspeed': bs.number(t.get('maxspeed')) or 0})
    print(len(out_roads), 'roads,', len(node_xy), 'graph nodes')
    width_of = {}
    for r in out_roads:
        width_of[r['id']] = max(width_of.get(r['id'], 0.0), r['w'])
    for c in closures:
        if not c['turn']:
            c['w'] = round(width_of.get(c['road'], 5.0) + 3.0, 1)
    print(len(closures), 'closures:', [(c['name'] or c['kind'], round(c['x']), round(c['y'])) for c in closures])

    # ---- railways
    rails = []
    for e in els:
        t = e.get('tags', {})
        if e['type'] != 'way' or t.get('railway') not in ('rail', 'narrow_gauge', 'light_rail', 'tram'):
            continue
        pts = densify(bs.simplify([P(p) for p in e['geometry']], 0.3), 10.0)
        pts = [q for q in pts if in_zone(q[0], q[1], 50.0)]  # lines run into the tree belt and stop
        if len(pts) >= 2:
            rails.append({'p': pts, 'b': 1 if t.get('bridge') in ('yes', 'viaduct') else 0,
                          'g': 1 if t.get('railway') == 'narrow_gauge' else 0,
                          'sd': 1 if t.get('service') in ('siding', 'yard', 'spur') else 0, 'ids': e.get('nodes', [])})
    print(len(rails), 'railway lines')

    # ---- water lines (for bridge clearance) and waterways
    waterways = []
    for e in els:
        t = e.get('tags', {})
        if e['type'] == 'way' and t.get('waterway') in ('river', 'stream', 'canal', 'ditch', 'drain'):
            pts = bs.simplify([P(p) for p in e['geometry']], 0.5)
            wd = bs.number(t.get('width')) or {'river': 14.0, 'canal': 6.0, 'stream': 2.5, 'ditch': 1.2, 'drain': 1.2}[t['waterway']]
            if t.get('tunnel') in ('culvert', 'yes'):
                continue
            waterways.append((wd, pts))

    # ---- bridge decks and their ramps (a z offset over the ground per road point)
    under = SegGrid(30.0)
    for i, r in enumerate(out_roads):
        if not r['b']:
            for a, b in zip(r['p'], r['p'][1:]):
                under.add(a, b, ('road', i))
    for i, r in enumerate(rails):
        if not r['b']:
            for a, b in zip(r['p'], r['p'][1:]):
                under.add(a, b, ('rail', i))
    for wd, pts in waterways:
        for a, b in zip(pts, pts[1:]):
            under.add(a, b, ('water', wd))

    def deck_height(pts, own, is_rail):
        best = 0.0
        for a, b in zip(pts, pts[1:]):
            mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            for c, d, item in under.near(mx, my, math.dist(a, b) / 2 + 2):
                if item == own:
                    continue
                if seg_cross(a, b, c, d):
                    if item[0] in ('road', 'rail'):
                        best = max(best, CLEARANCE_ROAD + (1.0 if is_rail else 0.0))
                    else:
                        best = max(best, CLEARANCE_WATER if item[1] > 3 else 1.0)
        return best

    def relax(lines, grade, junction_of, seeds=()):
        """Spreads each line's deck heights along the network as ramps: z(p) >= z(q) - grade * dist(p, q)."""
        # nodes: (line, idx); links along each line, and between lines at shared OSM nodes
        z = [[0.0] * len(l['p']) for l in lines]
        for li, l in enumerate(lines):
            if l.get('deck', 0.0) > 0.0:
                z[li] = [l['deck']] * len(l['p'])
        for li, idx, v in seeds:
            z[li][idx] = max(z[li][idx], v)
        shared = {}
        for li, l in enumerate(lines):
            for idx, nid in junction_of(l):
                shared.setdefault(nid, []).append((li, idx))
        import heapq
        heap = [(-z[li][i], li, i) for li in range(len(lines)) for i in range(len(lines[li]['p'])) if z[li][i] > 0]
        heapq.heapify(heap)
        while heap:
            nz, li, i = heapq.heappop(heap)
            nz = -nz
            if nz < z[li][i] - 1e-6:
                continue
            p = lines[li]['p']
            nbrs = []
            if i > 0:
                nbrs.append((li, i - 1, math.dist(p[i], p[i - 1])))
            if i < len(p) - 1:
                nbrs.append((li, i + 1, math.dist(p[i], p[i + 1])))
            for idx, nid_l in junction_of(lines[li]):
                if idx == i:
                    for lj, j in shared.get(nid_l, ()):
                        if (lj, j) != (li, i):
                            nbrs.append((lj, j, 0.0))
            for lj, j, dd in nbrs:
                cand = nz - grade * dd
                if cand > z[lj][j] + 1e-3:
                    z[lj][j] = cand
                    heapq.heappush(heap, (-cand, lj, j))
        return z

    for i, r in enumerate(out_roads):
        r['deck'] = deck_height(r['p'], ('road', i), False) if r['b'] and seg_len(r['p']) > 8 else 0.0
    for i, r in enumerate(rails):
        r['deck'] = deck_height(r['p'], ('rail', i), True) if r['b'] else 0.0
    zr = relax(out_roads, RAMP_GRADE, lambda l: l['e'])
    # railway lines meet at their ends; join them by position (the densified points lost the node ids)
    for r in rails:
        r['e'] = [(idx, (round(r['p'][idx][0]), round(r['p'][idx][1]))) for idx in (0, len(r['p']) - 1)]
    zl = relax(rails, RAIL_RAMP_GRADE, lambda l: l['e'])
    # ---- underpasses: a street under a railway that stands on a bridge or an embankment (or any "tunnel=yes" street
    # crossing a railway) goes through it. The railway's deck is lifted to UNDERPASS_Z there; TownBuilder cuts the
    # embankment along the street and builds the lined bore with its portals.
    def cross_pt(a, b, c, d):
        r = (b[0] - a[0], b[1] - a[1])
        s2 = (d[0] - c[0], d[1] - c[1])
        den = r[0] * s2[1] - r[1] * s2[0]
        t = ((c[0] - a[0]) * s2[1] - (c[1] - a[1]) * s2[0]) / den
        return (a[0] + r[0] * t, a[1] + r[1] * t)

    road_grid = SegGrid(30.0)
    for i, r in enumerate(out_roads):
        if not r['b']:
            for a, b in zip(r['p'], r['p'][1:]):
                road_grid.add(a, b, i)

    def find_underpasses(zl):
        found = {}
        for li, l in enumerate(rails):
            if l['sd'] and not l['b']:
                continue
            for i, (a, b) in enumerate(zip(l['p'], l['p'][1:])):
                zz = max(zl[li][i], zl[li][i + 1])
                mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
                for c, d, ri in road_grid.near(mx, my, math.dist(a, b) / 2 + 2):
                    r = out_roads[ri]
                    if not (zz >= 0.8 or r['tn']) or not seg_cross(a, b, c, d):
                        continue
                    if max(zr[ri]) > 1.0 and not r['tn']:
                        continue  # a raised road: it is a bridge or a ramp of its own
                    x, y = cross_pt(a, b, c, d)
                    dl = math.dist(a, b) or 1.0
                    dr = math.dist(c, d) or 1.0
                    found[(li, i, ri)] = (x, y, (b[0] - a[0]) / dl, (b[1] - a[1]) / dl, ri, (d[0] - c[0]) / dr, (d[1] - c[1]) / dr)
        return found

    under = find_underpasses(zl)
    seeds = [(li, k, UNDERPASS_Z) for (li, i, ri) in under for k in (i, i + 1) if rails[li]['b'] == 0 and zl[li][k] < UNDERPASS_Z]
    if seeds:
        zl = relax(rails, RAIL_RAMP_GRADE, lambda l: l['e'], seeds)
        under = find_underpasses(zl)
    tunnels = []
    for (li, i, ri), (x, y, ux, uy, _, vx, vy) in sorted(under.items()):
        zc = min(zl[li][i], zl[li][i + 1])
        if zc < UNDERPASS_Z - 0.01 and not rails[li]['b']:
            continue
        if any(t['road'] == out_roads[ri]['id'] and math.dist((x, y), t['c']) < 14.0 for t in tunnels):
            continue  # the second track of a double line
        r = out_roads[ri]
        tunnels.append({'c': [r1(x), r1(y)], 'u': [round(ux, 3), round(uy, 3)], 'v': [round(vx, 3), round(vy, 3)],
                        'w': r['w'], 'z': round(zc, 2), 'road': r['id'], 'tn': r['tn'], 'rail': li})
    print(len(tunnels), 'underpasses through railway embankments:', [(t['road'], t['z']) for t in tunnels])
    n_raised = sum(1 for zz in zr if max(zz) > 0.3)
    print(n_raised, 'roads raised on bridges or ramps;', sum(1 for zz in zl if max(zz) > 0.3), 'railway lines raised')

    # ---- buildings
    buildings = []
    measurements = building_measurements()
    landmark_path = os.path.join(HERE, 'open_world', 'landmarks.json')
    landmark_defs = json.load(open(landmark_path, encoding='utf-8')) if os.path.exists(landmark_path) else []
    bgrid = SegGrid(40.0)
    for e in els:
        t = e.get('tags', {})
        if t.get('building', 'no') in ('no', 'roof'):
            continue
        outer, _ = bs.rings_of(e, P)
        for ring in outer:
            ring = bs.simplify(ring, 0.3)
            if len(ring) < 4 or bs.area(ring) < 6.0:
                continue
            ring = ring[:-1]
            cx = sum(p[0] for p in ring) / len(ring)
            cy = sum(p[1] for p in ring) / len(ring)
            if not in_zone(cx, cy, CONTENT_MARGIN):
                continue
            kind, h, lv, roof = building_spec(t, ring)
            extra = conflate_building(ring, e['id'], e['type'], measurements)
            if extra.get('eh'):
                # The LoD1 value is a measured roof height; use a conservative wall/eave estimate
                # unless LoD2 supplied the actual eave planes.
                h = round(float(extra['eh']), 1)
            if extra.get('roof'):
                roof = extra['roof']
            if extra.get('bd', {}).get('storeys'):
                try: lv = max(1, int(round(float(extra['bd']['storeys']))))
                except (TypeError, ValueError): pass
            flat = []
            for p in ring:
                flat += [r1(p[0]), r1(p[1])]
            entry = [kind, h, lv, roof, flat]
            if t.get('name') and kind in ('church', 'public', 'commercial'):
                entry.append(t['name'])
            if len(entry) == 5:
                entry.append('')
            # Landmark authors can append "lm" and "lmh" without changing the collision ring at index 4.
            match = next((x for x in landmark_defs if str(x.get('osm_id')) == str(e['id']) and
                          x.get('osm_type', 'way') == e['type']), None)
            if match:
                extra['lm'] = match['model']
                extra['lmh'] = extra.get('rh', h)
            entry.append(extra)
            buildings.append(entry)
            for a, b in zip(ring, ring[1:] + ring[:1]):
                bgrid.add(a, b, len(buildings) - 1)
    print(len(buildings), 'buildings')
    if measurements:
        print('GUGiK conflation:', sum(1 for b in buildings if len(b) > 6 and any(k in b[6] for k in ('eh', 'rs', 'bd'))),
              'buildings with measured height/roof/storeys; orthophoto roof colours:',
              sum(1 for b in buildings if len(b) > 6 and 'rc' in b[6]), flush=True)

    # ---- land cover areas
    areas = []
    kind_of = {}
    for kind, pairs in AREA_KINDS:
        for kv in pairs:
            kind_of[kv] = kind
    order = [k for k, _ in AREA_KINDS]
    for e in els:
        t = e.get('tags', {})
        if e['type'] == 'node' or 'building' in t:
            continue
        kind = None
        for kv, kd in kind_of.items():
            if t.get(kv[0]) == kv[1]:
                if kind is None or order.index(kd) > order.index(kind):
                    kind = kd
        if not kind:
            continue
        outer, inner = bs.rings_of(e, P)
        for ring in outer:
            ring = bs.simplify(ring, 0.6)
            if len(ring) < 4:
                continue
            holes = [bs.simplify(h, 0.6) for h in inner if point_in_ring(h[0][0], h[0][1], ring)]
            a = bs.area(ring) - sum(bs.area(h) for h in holes)
            if a < 20:
                continue
            extra = {}
            if kind == 'forest':
                lt = t.get('leaf_type', '')
                extra['lt'] = 'n' if lt == 'needleleaved' else ('b' if lt == 'broadleaved' else 'm')
            if t.get('name'):
                extra['name'] = t['name']
            areas.append((order.index(kind), -a, kind, ring, holes, extra, e['id']))
    areas.sort(key=lambda x: (x[0], x[1]))
    print(len(areas), 'areas')

    # ---- point features
    trees = []
    lamps = []
    signals = []
    stops = []
    places = []
    for e in els:
        t = e.get('tags', {})
        if e['type'] == 'node':
            x, y = proj(e['lat'], e['lon'])
            hw = t.get('highway')
            if t.get('natural') == 'tree':
                trees.append((x, y, 0))
            elif hw == 'street_lamp':
                lamps.append((x, y))
            elif hw == 'traffic_signals':
                signals.append((x, y))
            elif hw == 'bus_stop' or t.get('public_transport') == 'platform' and t.get('bus') == 'yes':
                stops.append((x, y, t.get('name', '')))
        if e['type'] == 'way' and t.get('natural') == 'tree_row':
            for p in densify([P(q) for q in e['geometry']], 7.0):
                trees.append((p[0], p[1], 1))
        name = t.get('name')
        kind = None
        if t.get('man_made') == 'mineshaft':
            kind = 'mineshaft'
        elif t.get('man_made') in ('chimney', 'water_tower', 'tower'):
            kind = t['man_made']
        elif t.get('railway') in ('station', 'halt', 'stop') and e['type'] == 'node':
            kind = 'station'
        elif t.get('amenity') == 'fuel':
            kind = 'fuel'
        elif t.get('amenity') == 'place_of_worship':
            kind = 'church'
        elif t.get('leisure') == 'stadium':
            kind = 'stadium'
        elif t.get('shop') in ('supermarket', 'car_repair', 'car_parts', 'bakery', 'convenience', 'doityourself'):
            kind = 'shop'
        elif t.get('amenity') in ('restaurant', 'fast_food', 'pub', 'bar', 'cinema', 'police', 'fire_station',
                                  'post_office', 'marketplace', 'townhall', 'school'):
            kind = t['amenity']
        elif t.get('tourism') in ('museum', 'hotel', 'attraction'):
            kind = t['tourism']
        elif t.get('historic') in ('monument', 'memorial'):
            kind = 'monument'
        elif t.get('place') in ('town', 'village', 'neighbourhood', 'hamlet', 'suburb', 'locality') and e['type'] == 'node':
            kind = 'place_' + t['place']
        if not kind:
            continue
        if e['type'] == 'node':
            x, y = proj(e['lat'], e['lon'])
        else:
            g = [P(q) for q in e.get('geometry', []) if q]
            if not g:
                continue
            x, y = sum(p[0] for p in g) / len(g), sum(p[1] for p in g) / len(g)
        if not in_zone(x, y, CONTENT_MARGIN):
            continue
        rec = {'k': kind, 'x': r1(x), 'y': r1(y), 'name': name or ''}
        hgt = bs.number(t.get('height'))
        if hgt:
            rec['h'] = hgt
        places.append(rec)
    trees = [t for t in trees if in_zone(t[0], t[1], CONTENT_MARGIN)]
    lamps = [q for q in lamps if in_zone(q[0], q[1], CONTENT_MARGIN)]
    signals = [q for q in signals if in_zone(q[0], q[1], CONTENT_MARGIN)]
    stops = [q for q in stops if in_zone(q[0], q[1], CONTENT_MARGIN)]
    print(len(places), 'places,', len(lamps), 'mapped lamps,', len(signals), 'signals,', len(stops), 'bus stops')

    # ---- road segment hash (for placing things clear of the roads)
    rgrid = SegGrid(30.0)
    for i, r in enumerate(out_roads):
        for a, b in zip(r['p'], r['p'][1:]):
            rgrid.add(a, b, i)

    railgrid = SegGrid(30.0)
    for ri, rail in enumerate(rails):
        for a, b in zip(rail['p'], rail['p'][1:]):
            railgrid.add(a, b, ri)

    def road_clear(x, y, extra):
        for a, b, i in rgrid.near(x, y, 14.0 + extra):
            if dist_seg(x, y, a, b) < out_roads[i]['w'] / 2 + extra:
                return False
        return True

    def building_clear(x, y, extra):
        for a, b, i in bgrid.near(x, y, extra + 1):
            if dist_seg(x, y, a, b) < extra:
                return False
        return True

    def inside_building(x, y):
        cands = {i for _, _, i in bgrid.near(x, y, 1.0)}
        for i in cands:
            fl = buildings[i][4]
            ring = [(fl[k], fl[k + 1]) for k in range(0, len(fl), 2)]
            if point_in_ring(x, y, ring):
                return True
        return False

    # ---- mapped and generated plot fences
    # Records are independent short segments: [ax, ay, bx, by, style]. Keeping the
    # opening explicit makes these cheap to instance and lets the car collide with them.
    fences = []
    for e in els:
        t = e.get('tags', {})
        if e['type'] != 'way' or t.get('barrier') not in ('fence', 'wall', 'hedge'):
            continue
        pts = [P(q) for q in e.get('geometry', []) if q]
        style = {'fence': 0, 'wall': 1, 'hedge': 2}[t['barrier']]
        for a, b in zip(pts, pts[1:]):
            if math.dist(a, b) < 0.5:
                continue
            clear = True
            for f in (0.1, 0.35, 0.65, 0.9):
                sx, sy = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
                if not road_clear(sx, sy, 0.6) or not building_clear(sx, sy, 0.5) or \
                        any(dist_seg(sx, sy, ra, rb) < 2.2 for ra, rb, _ in railgrid.near(sx, sy, 5.0)):
                    clear = False
                    break
            if clear:
                fences.append((a[0], a[1], b[0], b[1], style))

    # Detached houses stand in fenced plots: a fence along the street in front of them (a gate opposite each
    # house) and fences between neighbouring plots running back from it. Walking each residential street's
    # sides finds the frontages, so the fences follow the real street lines rather than the house outlines.
    hcells = {}
    house_centres = []
    for b in buildings:
        if b[0] != 'house':
            continue
        ring = [(b[4][k], b[4][k + 1]) for k in range(0, len(b[4]), 2)]
        cx, cy = sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring)
        hi = len(house_centres)
        house_centres.append((cx, cy, ring))
        hcells.setdefault((int(cx // 30), int(cy // 30)), []).append(hi)

    def houses_near(x, y, r):
        for gx in range(int((x - r) // 30), int((x + r) // 30) + 1):
            for gy in range(int((y - r) // 30), int((y + r) // 30) + 1):
                yield from hcells.get((gx, gy), ())

    def fence_clear(p, q, road_extra=1.0):
        for f in (0.15, 0.5, 0.85):
            sx, sy = p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f
            if not road_clear(sx, sy, road_extra) or not building_clear(sx, sy, 0.6):
                return False
            if any(dist_seg(sx, sy, ra, rb) < 2.4 for ra, rb, _ in railgrid.near(sx, sy, 5.0)):
                return False
        return True

    generated = 0
    STEP, SETBACK, GATE, DEPTH = 2.5, 2.2, 1.8, 32.0
    for r in out_roads:
        if r['kn'] not in ('residential', 'living_street', 'unclassified', 'tertiary') or r['b']:
            continue
        pts = r['p']
        off = r['w'] / 2 + SETBACK
        for side in (-1.0, 1.0):
            prev = None  # (edge point, owner)
            last_side = None  # where the last side fence left the street
            ptx = pty = None
            for i in range(len(pts) - 1):
                a, b = pts[i], pts[i + 1]
                seg = math.dist(a, b)
                if seg < 0.3:
                    continue
                tx, ty = (b[0] - a[0]) / seg, (b[1] - a[1]) / seg
                # on a bend the plots fan out: no side fences there
                bend = ptx is not None and tx * ptx + ty * pty < 0.94
                ptx, pty = tx, ty
                nx, ny = -ty * side, tx * side
                k = 0.0
                while k < seg:
                    c = (a[0] + tx * k, a[1] + ty * k)
                    e = (c[0] + nx * off, c[1] + ny * off)
                    k += STEP
                    # the house whose plot this stretch of frontage belongs to
                    owner, best = None, 1e9
                    for hi in houses_near(e[0], e[1], 30.0):
                        hx, hy, _ = house_centres[hi]
                        back = (hx - e[0]) * nx + (hy - e[1]) * ny
                        along = (hx - e[0]) * tx + (hy - e[1]) * ty
                        if 2.0 < back < 30.0 and abs(along) < 13.0:
                            score = abs(along) + back * 0.35
                            if score < best:
                                owner, best = hi, score
                    if owner is None:
                        prev = None
                        continue
                    hx, hy, _ = house_centres[owner]
                    style = int(abs(hx * 13 + hy * 7)) % 5
                    gate = abs((hx - e[0]) * tx + (hy - e[1]) * ty) < GATE
                    if prev is not None and not gate and math.dist(prev[0], e) < STEP * 1.6 and fence_clear(prev[0], e):
                        fences.append((r1(prev[0][0]), r1(prev[0][1]), r1(e[0]), r1(e[1]), style))
                        generated += 1
                    if prev is not None and prev[1] != owner and not bend and \
                            (last_side is None or math.dist(last_side, e) > 6.0):
                        last_side = e
                        # a boundary between two plots: a side fence back from the street
                        p0 = e
                        d = 0.0
                        while d < DEPTH:
                            q = (p0[0] + nx * STEP, p0[1] + ny * STEP)
                            if not fence_clear(p0, q):
                                break
                            fences.append((r1(p0[0]), r1(p0[1]), r1(q[0]), r1(q[1]), style))
                            generated += 1
                            p0 = q
                            d += STEP
                    prev = None if gate else (e, owner)  # the gate leaves a gap in the frontage
    # a vegetable bed behind some houses
    garden_beds = []
    for hx, hy, ring in house_centres:
        seed = int(abs(hx * 13 + hy * 7))
        if seed % 3:
            continue
        for tries in range(3):
            gx = hx + (rand01(hx, hy, 41 + tries) - 0.5) * 24.0
            gy = hy + (rand01(hx, hy, 42 + tries) - 0.5) * 24.0
            if road_clear(gx, gy, 3.0) and building_clear(gx, gy, 2.5) and not inside_building(gx, gy):
                garden_beds.append((r1(gx), r1(gy), round(rand01(hx, hy, 43) * math.pi, 2), 2.8 + rand01(hx, hy, 44) * 2.0, 0.9 + rand01(hx, hy, 45) * 0.6))
                break

    # Narrow soil beds in mapped allotments (ROD) make the shared plots read distinctly.
    for _, _, kind, ring, holes, _, oid in areas:
        if kind != 'allotments':
            continue
        x0, x1 = min(p[0] for p in ring), max(p[0] for p in ring)
        y0, y1 = min(p[1] for p in ring), max(p[1] for p in ring)
        gx = math.floor(x0 / 8.0)
        while gx * 8.0 < x1:
            gy = math.floor(y0 / 8.0)
            while gy * 8.0 < y1:
                x = (gx + 0.5 + rand01(gx, gy, oid % 983)) * 8.0
                y = (gy + 0.5 + rand01(gx, gy, oid % 977)) * 8.0
                if point_in_ring(x, y, ring) and not any(point_in_ring(x, y, h) for h in holes) and \
                        road_clear(x, y, 1.0) and building_clear(x, y, 1.5):
                    garden_beds.append((x, y, rand01(gx, gy, oid % 971) * math.pi, 2.2, 0.75))
                gy += 1
            gx += 1

    # ---- generated trees: woods, parks and gardens
    def fill_trees(ring, holes, cell, prob, kind_code, salt):
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        made = 0
        gx = math.floor(min(xs) / cell)
        while gx * cell <= max(xs):
            gy = math.floor(min(ys) / cell)
            while gy * cell <= max(ys):
                x = (gx + 0.15 + 0.7 * rand01(gx, gy, salt)) * cell
                y = (gy + 0.15 + 0.7 * rand01(gx, gy, salt + 1)) * cell
                if rand01(gx, gy, salt + 2) < prob and point_in_ring(x, y, ring) and in_zone(x, y, CONTENT_MARGIN) and \
                        not any(point_in_ring(x, y, h) for h in holes) and road_clear(x, y, 2.0) and \
                        building_clear(x, y, 3.0) and not inside_building(x, y):
                    trees.append((x, y, kind_code))
                    made += 1
                gy += 1
            gx += 1
        return made

    for c in closures:
        nx_, ny_ = -math.sin(c['h']), math.cos(c['h'])
        hw = c['w'] / 2
        fences.append((r1(c['x'] - nx_ * hw), r1(c['y'] - ny_ * hw), r1(c['x'] + nx_ * hw), r1(c['y'] + ny_ * hw), 4))
    n_wood = 0
    for _, _, kind, ring, holes, extra, oid in areas:
        if kind == 'forest':
            code = {'n': 2, 'b': 3, 'm': 4}[extra.get('lt', 'm')]
            n_wood += fill_trees(ring, holes, 7.5, 0.92, code, oid % 997)
        elif kind == 'park' or kind == 'cemetery':
            fill_trees(ring, holes, 13.0, 0.55, 5, oid % 991)
        elif kind == 'residential':
            fill_trees(ring, holes, 13.0, 0.52, 6, oid % 983)
        elif kind in ('scrub', 'wetland'):
            fill_trees(ring, holes, 11.0, 0.4, 7, oid % 977)
        elif kind == 'allotments':
            fill_trees(ring, holes, 7.0, 0.62, 8, oid % 971)
    # the edge of the world: three rows of trees just outside the playable polygon (and a row just inside), broken
    # only where a road leaves (its barrier stands there) or a building is in the way
    ponds = [(min(q[0] for q in ring), min(q[1] for q in ring), max(q[0] for q in ring), max(q[1] for q in ring), ring)
             for _, _, kind, ring, holes, _, _ in areas if kind == 'water']

    def in_water(x, y):
        return any(x0 <= x <= x1 and y0 <= y <= y1 and point_in_ring(x, y, ring) for x0, y0, x1, y1, ring in ponds)
    belt = 0
    for a, b in zip(PLAY_POLY, PLAY_POLY[1:] + PLAY_POLY[:1]):
        ln = math.dist(a, b)
        ux, uy = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        for row, off in enumerate((-2.0, 3.0, 8.0, 15.0, 24.0)):
            n = int(ln / 4.5)
            for i in range(n):
                j = rand01(i, row, a[0] + a[1])
                t = (i + 0.5 + 0.8 * (j - 0.5)) / n
                nx_, ny_ = uy, -ux  # a normal; flipped to point outward below
                x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                if point_in_ring(x + nx_ * 3.0, y + ny_ * 3.0, PLAY_POLY):
                    nx_, ny_ = -nx_, -ny_
                o = off + (rand01(i, row, 5.0) - 0.5) * 4.0
                x, y = x + nx_ * o, y + ny_ * o
                if road_clear(x, y, 3.0) and building_clear(x, y, 3.0) and not inside_building(x, y) and not in_water(x, y) and \
                        not any(math.dist((x, y), (c['x'], c['y'])) < c['w'] / 2 + 16 for c in closures):
                    trees.append((x, y, (2, 3, 4)[int(rand01(i, row, 9.0) * 3) % 3]))
                    belt += 1
    print(belt, 'edge trees')
    print(len(trees), 'trees (', n_wood, 'in woods );', len(fences), 'fence segments (', generated, 'generated )')

    # ---- generated street lamps along town roads
    def in_town(x, y):
        return not boundary or point_in_ring(x, y, boundary)

    built_up = [(ring, holes) for _, _, kind, ring, holes, _, _ in areas if kind in ('residential', 'industrial')]
    lamp_grid = set((int(x // 10), int(y // 10)) for x, y in lamps)
    for r in out_roads:
        if r['kn'] not in ('primary', 'secondary', 'tertiary', 'residential', 'unclassified', 'living_street') and not r['lit']:
            continue
        if r['b']:
            continue
        pts = r['p']
        spacing = 30.0 if r['kn'] in ('primary', 'secondary', 'tertiary') else 36.0
        acc = spacing * 0.5
        side = 1 if (r['id'] % 2) else -1
        for a, b in zip(pts, pts[1:]):
            ln = math.dist(a, b)
            if ln < 1e-6:
                continue
            tx_, ty_ = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
            s0 = 0.0
            while acc <= ln - s0 + 1e-9:
                s0 += acc
                acc = spacing
                x = a[0] + tx_ * s0
                y = a[1] + ty_ * s0
                off = r['w'] / 2 + 1.3
                lx, ly = x - ty_ * off * side, y + tx_ * off * side
                key = (int(lx // 10), int(ly // 10))
                if key in lamp_grid:
                    continue
                if not any(point_in_ring(lx, ly, ring) for ring, _ in built_up) and not r['lit']:
                    continue
                if road_clear(lx, ly, 0.6) and building_clear(lx, ly, 1.0):
                    lamps.append((lx, ly))
                    lamp_grid.add(key)
            acc -= (ln - s0)
    print(len(lamps), 'lamps')

    # ---- named spots: where the campaign's events stand
    def road_named(name, near=None):
        best = None
        for r in out_roads:
            if r['n'] != name:
                continue
            for p in r['p']:
                d = math.dist(p, near) if near else 0.0
                if best is None or d < best[0]:
                    best = (d, r, p)
        return best

    def heading_at(r, p):
        pts = r['p']
        i = min(range(len(pts)), key=lambda k: math.dist(pts[k], p))
        a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
        return math.atan2(b[1] - a[1], b[0] - a[0])

    def exit_spot(side, kinds, name=None, near=None, pick=None):
        """Where a road (of one of kinds, named name if given) ends at the playable edge on side (N/E/S/W by its
        outward heading): a spot 70 m back along it, heading out. near (a coordinate along that side) picks between
        several; pick (a key function) overrides that."""
        best = None
        for c in closures:
            if c['kind'] not in kinds or (name and c['name'] != name):
                continue
            sd = ('E' if math.cos(c['h']) > 0 else 'W') if abs(math.cos(c['h'])) >= abs(math.sin(c['h'])) else \
                ('S' if math.sin(c['h']) > 0 else 'N')
            if side and sd != side:
                continue
            along = c['y'] if sd in 'WE' else c['x']
            score = pick(c) if pick else (abs(along - near) if near is not None else 0.0)
            if best is None or score < best[0]:
                best = (score, c)
        if not best:
            return None
        c = best[1]
        cand = [r for r in out_roads if r['id'] == c['road']]
        pts = None
        for r in cand:
            for pts_ in (r['p'], r['p'][::-1]):
                if math.dist(pts_[-1], (c['x'], c['y'])) < (120 if c['turn'] else 150) and \
                        (pts is None or math.dist(pts_[-1], (c['x'], c['y'])) < math.dist(pts[-1], (c['x'], c['y']))):
                    pts = pts_
        if not pts:
            return None
        j, run = len(pts) - 1, 0.0
        while j > 0 and run < 70.0:
            run += math.dist(pts[j], pts[j - 1])
            j -= 1
        p, q = pts[j], pts[-1]
        h = math.atan2(q[1] - p[1], q[0] - p[0]) if math.dist(p, q) > 1 else 0.0
        r_ = cand[0]
        return [r1(p[0]), r1(p[1]), round(h, 3), c['name'] or r_['ref']]

    spots = {}
    shafts = [pl for pl in places if pl['k'] == 'mineshaft' and 'Andrzej' in pl['name']]
    andrzej = next((pl for pl in shafts if pl['name'].endswith(' I')), shafts[0] if shafts else None)
    if andrzej:
        hit = road_named('Kościuszki', (andrzej['x'], andrzej['y'])) or road_named('Dworcowa', (andrzej['x'], andrzej['y']))
        if hit:
            _, r, p = hit
            spots['industrial_sprint'] = [r1(p[0]), r1(p[1]), round(heading_at(r, p), 3), r['n']]
    bor = road_named('Bór', proj(50.0097, 19.1537))
    if bor:
        _, r, p = bor
        spots['bor_stage'] = [r1(p[0]), r1(p[1]), round(heading_at(r, p), 3), r['n']]
    major = ('secondary', 'primary', 'tertiary', 'trunk')
    for key, side, kinds, name, near, *pk in (('exit_pszczyna', 'W', major, 'Pszczyńska', 2000.0),
                                         ('exit_oswiecim', None, major, '44', None, lambda c: c['y'] if c['x'] > 4200 else 1e9),
                                         ('exit_bielsko', None, major, 'Bielska', None, lambda c: -c['y']),
                                         ('exit_kety', None, major, 'Łęcka', None, lambda c: -c['x']),
                                         ('exit_wilamowice', None, ('motorway',), None, None, lambda c: -c['y']),
                                         ('exit_tychy', None, ('motorway',), None, None, lambda c: c['y'])):
        sp = exit_spot(side, kinds, name, near, pk[0] if pk else None)
        if sp:
            spots[key] = sp
    station = next((pl for pl in places if pl['k'] == 'station' and pl['name'] == 'Brzeszcze Jawiszowice'), None)
    if station:
        hit = None
        for r in out_roads:
            if r['kn'] in ('residential', 'service', 'unclassified', 'tertiary', 'secondary'):
                for p in r['p']:
                    d = math.dist(p, (station['x'], station['y']))
                    if hit is None or d < hit[0]:
                        hit = (d, r, p)
        if hit:
            _, r, p = hit
            spots['station'] = [r1(p[0]), r1(p[1]), round(heading_at(r, p), 3), r['n'] or 'Dworzec']
    stadium = next((pl for pl in places if pl['k'] == 'stadium' and 'Górnik' in pl['name']), None)
    if stadium:
        spots['festival'] = [stadium['x'], stadium['y'], 0.0, stadium['name']]
    print('spots', spots)

    # ---- write
    def flat_pts(pts):
        out = []
        for p in pts:
            out += [r1(p[0]), r1(p[1])]
        return out

    roads_out = []
    for r, z in zip(out_roads, zr):
        rec = {'id': r['id'], 'n': r['n'], 'k': r['kn'], 'w': r['w'], 'l': r['l'], 'o': r['o'], 's': r['s'],
               'b': r['b'], 'p': flat_pts(r['p']), 'e': [[i, nid] for i, nid in r['e']]}
        if max(z) > 0.05:
            rec['z'] = [round(v, 2) for v in z]
        if r['rb']:
            rec['rb'] = 1
        if r['maxspeed']:
            rec['v'] = r['maxspeed']
        if r['tn']:
            rec['tn'] = 1
        roads_out.append(rec)
    rails_out = []
    for r, z in zip(rails, zl):
        rec = {'p': flat_pts(r['p']), 'g': r['g'], 'sd': r['sd'], 'b': r['b']}
        if max(z) > 0.05:
            rec['z'] = [round(v, 2) for v in z]
        rails_out.append(rec)
    out = {
        'name': 'Brzeszcze', 'origin': [ORIGIN[0], ORIGIN[1]],
        'bounds': [r1(bx0), r1(by0), r1(bx1), r1(by1)],
        'extent': [r1(fx0), r1(fy0), r1(fx1), r1(fy1)],
        'boundary': flat_pts(bs.simplify(boundary, 2.0)) if boundary else [],
        'play': flat_pts(PLAY_POLY),
        'closures': [[r1(c['x']), r1(c['y']), round(c['h'], 3), c['w'], 1 if c['turn'] else 0] for c in closures],
        'terrain': {'x0': tx0, 'y0': ty0, 'step': tstep, 'nx': tnx, 'ny': tny, 'h': [round(v, 2) for v in hs]},
        'roads': roads_out,
        'nodes': {str(k): list(v) for k, v in node_xy.items()},
        'rail': rails_out,
        'tunnels': tunnels,
        'buildings': buildings,
        'areas': [[kind, flat_pts(ring), [flat_pts(h) for h in holes], extra] for _, _, kind, ring, holes, extra, _ in areas],
        'waterways': [[wd, flat_pts(pts)] for wd, pts in waterways],
        'trees': [v for x, y, c in trees for v in (r1(x), r1(y), c)],
        'fences': [[r1(x), r1(y), r1(xx), r1(yy), style] for x, y, xx, yy, style in fences],
        'garden_beds': [[r1(x), r1(y), round(a, 3), l, w] for x, y, a, l, w in garden_beds],
        'lamps': flat_pts(lamps),
        'signals': flat_pts(signals),
        'stops': [[r1(x), r1(y), n] for x, y, n in stops],
        'places': places,
        'spots': spots,
        'credits': 'Map/building footprints © OpenStreetMap contributors (ODbL). Building heights, roof geometry and BDOT10k attributes: Główny Urząd Geodezji i Kartografii (GUGiK), Modele 3D budynków LoD1 2024 / LoD2 2017 and BDOT10k; optional roof colours use PZGiK orthophoto when included in the extract. PZGiK data made available under Prawo geodezyjne i kartograficzne art. 40a ust. 2. Elevation: EU-DEM via OpenTopoData.',
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, KEY + '.json')
    json.dump(out, open(path, 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
    print('wrote', path, os.path.getsize(path) // 1024, 'KB')
    land_map(out, areas, out_roads, rails)
    hud_map(out)
    if check_png:
        check(out, check_png)


LAND_RES = 2.5  # m per texel


def land_map(out, areas, roads, rails):
    """godot/data/world/brzeszcze_land.png over the terrain grid, in ground.gdshader's land-map layout: R paved
    or yard, G field crop (0 = none, 0.35-1 picks a crop), B bare earth and sand, A forest floor."""
    from PIL import Image, ImageDraw, ImageFilter
    t = out['terrain']
    x0, y0 = t['x0'], t['y0']
    w, h = (t['nx'] - 1) * t['step'], (t['ny'] - 1) * t['step']
    tw, th = int(math.ceil(w / LAND_RES)), int(math.ceil(h / LAND_RES))
    chans = [Image.new('L', (tw, th), 0) for _ in range(4)]
    draws = [ImageDraw.Draw(c) for c in chans]

    def px(p):
        return ((p[0] - x0) / LAND_RES, (p[1] - y0) / LAND_RES)

    paint = {'forest': [(3, 255)], 'farmland': [(1, None)], 'industrial': [(0, 200)], 'parking': [(0, 235)],
             'brownfield': [(2, 230)], 'pitch': [], 'residential': [(0, 25)], 'allotments': [(1, 90), (3, 60)],
             'scrub': [(3, 110)], 'wetland': [(3, 70), (2, 40)], 'cemetery': [(0, 70)], 'park': [], 'meadow': [],
             'water': [(3, 90), (2, 120)]}
    for _, _, kind, ring, holes, extra, oid in areas:
        for ch, v in paint.get(kind, []):
            if v is None:
                v = int(255 * (0.35 + 0.65 * ((oid * 2654435761) % 1000) / 999.0))
            # areas drawn later clear the other channels where they cover them
            for other in range(4):
                if other != ch:
                    draws[other].polygon([px(p) for p in ring], fill=0)
            draws[ch].polygon([px(p) for p in ring], fill=v)
            for hl in holes:
                draws[ch].polygon([px(p) for p in hl], fill=0)
        if kind in ('meadow', 'park', 'pitch'):
            for other in range(4):
                draws[other].polygon([px(p) for p in ring], fill=0)
    # gravel shoulders and verges along the roads, ballast along the railway
    for r in roads:
        wpx = max(1, int(round((r['w'] + 2.2) / LAND_RES)))
        ch = 2 if r['s'] == 2 else 0
        draws[ch].line([px(p) for p in r['p']], fill=150 if ch == 0 else 200, width=wpx, joint='curve')
        for other in (1, 3):
            draws[other].line([px(p) for p in r['p']], fill=0, width=wpx, joint='curve')
    for r in rails:
        draws[2].line([px(p) for p in r['p']], fill=210, width=max(1, int(round(6.0 / LAND_RES))), joint='curve')
        for other in (1, 3):
            draws[other].line([px(p) for p in r['p']], fill=0, width=max(1, int(round(6.0 / LAND_RES))), joint='curve')
    chans = [c.filter(ImageFilter.GaussianBlur(0.8)) for c in chans]
    img = Image.merge('RGBA', chans)
    path = os.path.join(OUT_DIR, KEY + '_land.png')
    img.save(path, optimize=True)
    out_meta = {'x0': x0, 'y0': y0, 'w': tw * LAND_RES, 'h': th * LAND_RES}
    print('wrote', path, tw, 'x', th, out_meta)


def hud_map(out):
    """godot/data/world/brzeszcze_map.png: the satnav picture for the minimap and the map screen, over the same
    rectangle and resolution as the land map (LAND_RES from the terrain grid's corner)."""
    from PIL import Image, ImageDraw
    t = out['terrain']
    x0, y0 = t['x0'], t['y0']
    w, h = (t['nx'] - 1) * t['step'], (t['ny'] - 1) * t['step']
    ss = 2
    tw, th = int(math.ceil(w / LAND_RES)), int(math.ceil(h / LAND_RES))
    img = Image.new('RGBA', (tw * ss, th * ss), (30, 38, 34, 255))
    d = ImageDraw.Draw(img)

    def px(fl):
        return [((fl[i] - x0) / LAND_RES * ss, (fl[i + 1] - y0) / LAND_RES * ss) for i in range(0, len(fl), 2)]

    fills = {'forest': (36, 62, 40), 'park': (44, 70, 46), 'farmland': (48, 52, 40), 'meadow': (40, 50, 40),
             'residential': (46, 46, 52), 'industrial': (54, 50, 58), 'water': (40, 92, 140), 'cemetery': (44, 58, 46),
             'pitch': (52, 80, 52), 'parking': (60, 60, 64), 'allotments': (46, 60, 42), 'brownfield': (64, 58, 48)}
    for kind, ring, holes, _ in out['areas']:
        if kind in fills and len(ring) >= 6:
            d.polygon(px(ring), fill=fills[kind])
            for hl in holes:
                if len(hl) >= 6:
                    d.polygon(px(hl), fill=(30, 38, 34))
    for ww, pts in out['waterways']:
        d.line(px(pts), fill=(40, 92, 140), width=max(1, int(ww / LAND_RES * ss)))
    for b in out['buildings']:
        if len(b[4]) >= 6:
            d.polygon(px(b[4]), fill=(88, 86, 96))
    for r in out['rail']:
        d.line(px(r['p']), fill=(120, 110, 100), width=2)
    order = {'track': 0, 'service': 1, 'living_street': 2, 'pedestrian': 2, 'residential': 3, 'unclassified': 3,
             'tertiary': 4, 'tertiary_link': 4, 'secondary': 5, 'secondary_link': 5, 'primary': 6, 'motorway_link': 6,
             'motorway': 7}
    colour = {0: (110, 100, 80), 1: (150, 150, 155), 2: (175, 175, 180), 3: (215, 215, 220), 4: (245, 225, 160),
              5: (255, 190, 90), 6: (255, 160, 70), 7: (255, 120, 60)}
    for r in sorted(out['roads'], key=lambda r: order.get(r['k'], 1)):
        rank = order.get(r['k'], 1)
        wpx = max(2, int(round((r['w'] + 2.0) / LAND_RES * ss)))
        d.line(px(r['p']), fill=colour[rank], width=wpx, joint='curve')
    # outside the playable area the satnav picture is dimmed: that is where the world ends
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).polygon(px(out['play']), fill=255)
    dark = Image.new('RGBA', img.size, (14, 18, 16, 255))
    img = Image.composite(img, Image.blend(img, dark, 0.62), mask)
    d = ImageDraw.Draw(img)
    d.line(px(out['play'] + out['play'][:2]), fill=(255, 150, 60, 255), width=3 * ss)
    for c in out['closures']:
        d.ellipse([px([c[0], c[1]])[0][0] - 5 * ss, px([c[0], c[1]])[0][1] - 5 * ss, px([c[0], c[1]])[0][0] + 5 * ss,
                   px([c[0], c[1]])[0][1] + 5 * ss], fill=(210, 40, 40, 255))
    img = img.resize((tw, th), Image.LANCZOS)
    path = os.path.join(OUT_DIR, KEY + '_map.png')
    img.save(path, optimize=True)
    print('wrote', path, tw, 'x', th)


def check(out, png):
    """A top-down picture of the baked map, to eyeball the data."""
    from PIL import Image, ImageDraw
    x0, y0, x1, y1 = out['extent']
    sc = 0.5  # px per m
    img = Image.new('RGB', (int((x1 - x0) * sc), int((y1 - y0) * sc)), (196, 214, 160))
    d = ImageDraw.Draw(img)

    def px(fl):
        return [((fl[i] - x0) * sc, (fl[i + 1] - y0) * sc) for i in range(0, len(fl), 2)]

    col = {'forest': (90, 140, 80), 'water': (110, 160, 210), 'farmland': (220, 210, 150), 'residential': (215, 210, 200),
           'industrial': (200, 190, 200), 'park': (160, 200, 130), 'meadow': (190, 215, 150), 'parking': (180, 180, 180)}
    for kind, ring, holes, _ in out['areas']:
        if len(ring) >= 6:
            d.polygon(px(ring), fill=col.get(kind, (200, 210, 170)))
    for b in out['buildings']:
        d.polygon(px(b[4]), fill=(150, 90, 80))
    for r in out['rail']:
        d.line(px(r['p']), fill=(60, 60, 60), width=2)
    for r in out['roads']:
        c = (255, 255, 255) if 'z' not in r else (255, 120, 0)
        d.line(px(r['p']), fill=c, width=max(1, int(r['w'] * sc)))
    if out['boundary']:
        d.line(px(out['boundary'] + out['boundary'][:2]), fill=(200, 0, 200), width=2)
    d.line(px(out['play'] + out['play'][:2]), fill=(255, 0, 0), width=3)
    bx0, by0, bx1, by1 = out['bounds']
    d.rectangle(((bx0 - x0) * sc, (by0 - y0) * sc, (bx1 - x0) * sc, (by1 - y0) * sc), outline=(255, 0, 0), width=2)
    for k, s in out['spots'].items():
        x, y = (s[0] - x0) * sc, (s[1] - y0) * sc
        d.ellipse((x - 8, y - 8, x + 8, y + 8), fill=(255, 0, 0))
        d.text((x + 10, y - 6), k, fill=(0, 0, 0))
    img.save(png)
    print('wrote', png)


if __name__ == '__main__':
    refetch = '--refetch' in sys.argv
    if refetch or '--fetch-only' in sys.argv:
        fetch_osm(refetch)
        fetch_elevation(refetch)
    if '--fetch-only' not in sys.argv:
        png = sys.argv[sys.argv.index('--check') + 1] if '--check' in sys.argv else None
        build(png)
