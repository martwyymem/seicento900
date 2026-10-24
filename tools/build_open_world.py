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
FETCH_MARGIN = 700.0  # m of countryside fetched round the town's box
DRIVE_MARGIN = 450.0  # m of it that can be driven
GRID = 40.0  # m, terrain grid spacing

KX = 111320 * math.cos(math.radians(ORIGIN[0]))
KY = 110540


def proj(lat, lon):
    return ((lon - ORIGIN[1]) * KX, -(lat - ORIGIN[0]) * KY)


def unproj(x, y):
    return (ORIGIN[0] - y / KY, ORIGIN[1] + x / KX)


def box(margin):
    """(s, w, n, e) of the town's box grown by margin metres."""
    s, w, n, e = TOWN_BOX
    return (s - margin / KY, w - margin / KX, n + margin / KY, e + margin / KX)


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
    path = os.path.join(CACHE, KEY + '_elevation.json')
    x0, y0, nx, ny = grid_frame()
    have = json.load(open(path)) if os.path.exists(path) and not refetch else {}
    if have.get('nx') == nx and have.get('ny') == ny and len(have.get('h', [])) == nx * ny:
        return have
    pts = [unproj(x0 + i * GRID, y0 + j * GRID) for j in range(ny) for i in range(nx)]
    h = have.get('h', []) if have.get('nx') == nx and have.get('ny') == ny else []
    print(f'fetching elevation {nx}x{ny} = {len(pts)} points ({len(h)} cached)', flush=True)
    os.makedirs(CACHE, exist_ok=True)
    while len(h) < len(pts):
        chunk = pts[len(h):len(h) + 100]
        for attempt in range(8):
            try:
                res = http_post(TOPO, {'locations': '|'.join(f'{a:.6f},{b:.6f}' for a, b in chunk)}, 60)
                if res.get('status') == 'OK':
                    break
            except Exception as err:
                print('  retry', attempt, err, flush=True)
            time.sleep(3 + attempt * 4)
        else:
            raise SystemExit('elevation API failed')
        h += [r['elevation'] if r['elevation'] is not None else 0.0 for r in res['results']]
        if len(h) % 2000 < 100:
            print(f'  {len(h)}/{len(pts)}', flush=True)
            json.dump({'x0': x0, 'y0': y0, 'step': GRID, 'nx': nx, 'ny': ny, 'h': h}, open(path, 'w'))
        time.sleep(1.05)
    out = {'x0': x0, 'y0': y0, 'step': GRID, 'nx': nx, 'ny': ny, 'h': [round(v, 2) for v in h]}
    json.dump(out, open(path, 'w'))
    return out


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

    s_, w_, n_, e_ = box(DRIVE_MARGIN)
    bx0, by0 = proj(n_, w_)
    bx1, by1 = proj(s_, e_)
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
        for nid in ids:
            use[nid] = use.get(nid, 0) + 1
        roads.append((e, k, t, ids, pts))
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

    # ---- railways
    rails = []
    for e in els:
        t = e.get('tags', {})
        if e['type'] != 'way' or t.get('railway') not in ('rail', 'narrow_gauge', 'light_rail', 'tram'):
            continue
        pts = densify(bs.simplify([P(p) for p in e['geometry']], 0.3), 10.0)
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

    def relax(lines, grade, junction_of):
        """Spreads each line's deck heights along the network as ramps: z(p) >= z(q) - grade * dist(p, q)."""
        # nodes: (line, idx); links along each line, and between lines at shared OSM nodes
        z = [[0.0] * len(l['p']) for l in lines]
        for li, l in enumerate(lines):
            if l.get('deck', 0.0) > 0.0:
                z[li] = [l['deck']] * len(l['p'])
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
            for nid_l, idx in junction_of(lines[li]):
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
    n_raised = sum(1 for zz in zr if max(zz) > 0.3)
    print(n_raised, 'roads raised on bridges or ramps;', sum(1 for zz in zl if max(zz) > 0.3), 'railway lines raised')

    # ---- buildings
    buildings = []
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
            if not (fx0 <= cx <= fx1 and fy0 <= cy <= fy1):
                continue
            kind, h, lv, roof = building_spec(t, ring)
            flat = []
            for p in ring:
                flat += [r1(p[0]), r1(p[1])]
            entry = [kind, h, lv, roof, flat]
            if t.get('name') and kind in ('church', 'public', 'commercial'):
                entry.append(t['name'])
            buildings.append(entry)
            for a, b in zip(ring, ring[1:] + ring[:1]):
                bgrid.add(a, b, len(buildings) - 1)
    print(len(buildings), 'buildings')

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
        if not (fx0 <= x <= fx1 and fy0 <= y <= fy1):
            continue
        rec = {'k': kind, 'x': r1(x), 'y': r1(y), 'name': name or ''}
        hgt = bs.number(t.get('height'))
        if hgt:
            rec['h'] = hgt
        places.append(rec)
    print(len(places), 'places,', len(lamps), 'mapped lamps,', len(signals), 'signals,', len(stops), 'bus stops')

    # ---- road segment hash (for placing things clear of the roads)
    rgrid = SegGrid(30.0)
    for i, r in enumerate(out_roads):
        for a, b in zip(r['p'], r['p'][1:]):
            rgrid.add(a, b, i)

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
                if rand01(gx, gy, salt + 2) < prob and point_in_ring(x, y, ring) and \
                        not any(point_in_ring(x, y, h) for h in holes) and road_clear(x, y, 2.0) and \
                        building_clear(x, y, 3.0) and not inside_building(x, y):
                    trees.append((x, y, kind_code))
                    made += 1
                gy += 1
            gx += 1
        return made

    n_wood = 0
    for _, _, kind, ring, holes, extra, oid in areas:
        if kind == 'forest':
            code = {'n': 2, 'b': 3, 'm': 4}[extra.get('lt', 'm')]
            n_wood += fill_trees(ring, holes, 7.5, 0.92, code, oid % 997)
        elif kind == 'park' or kind == 'cemetery':
            fill_trees(ring, holes, 13.0, 0.55, 5, oid % 991)
        elif kind == 'residential':
            fill_trees(ring, holes, 17.0, 0.42, 6, oid % 983)
        elif kind in ('scrub', 'wetland'):
            fill_trees(ring, holes, 11.0, 0.4, 7, oid % 977)
        elif kind == 'allotments':
            fill_trees(ring, holes, 10.0, 0.5, 8, oid % 971)
    print(len(trees), 'trees (', n_wood, 'in woods )')

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

    def exit_spot(side, kinds, name=None, near=None):
        """Where a road (of one of kinds, named name if given) leaves the drivable box on side (N/E/S/W): a
        spot 70 m back inside along it, heading out. near (a coordinate along that side) picks between several."""
        best = None
        for r in out_roads:
            if r['kn'] not in kinds or (name and r['n'] != name):
                continue
            pts = r['p']
            ins = [bx0 < x < bx1 and by0 < y < by1 for x, y in pts]
            for i in range(len(pts) - 1):
                if ins[i] == ins[i + 1]:
                    continue
                k = i if ins[i] else i + 1  # last point inside
                q = pts[k]
                sd = min((q[0] - bx0, 'W'), (bx1 - q[0], 'E'), (q[1] - by0, 'N'), (by1 - q[1], 'S'))[1]
                if sd != side:
                    continue
                along = q[1] if side in 'WE' else q[0]
                score = abs(along - near) if near is not None else 0.0
                if best is None or score < best[0]:
                    best = (score, r, k, -1 if ins[i] else 1)  # step back inside
        if not best:
            return None
        _, r, k, back = best
        pts = r['p']
        j, run = k, 0.0
        while 0 <= j + back < len(pts) and run < 70.0:
            run += math.dist(pts[j], pts[j + back])
            j += back
        p, q = pts[j], pts[k]
        h = math.atan2(q[1] - p[1], q[0] - p[0]) if math.dist(p, q) > 1 else 0.0
        return [r1(p[0]), r1(p[1]), round(h, 3), r['n'] or r['ref']]

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
    for key, side, kinds, name, near in (('exit_pszczyna', 'W', major, 'Pszczyńska', 2000.0),
                                         ('exit_oswiecim', 'E', major, 'Pszczyńska', -1800.0),
                                         ('exit_bielsko', 'S', major, 'Bielska', None),
                                         ('exit_kety', 'E', major, 'Łęcka', None),
                                         ('exit_wilamowice', 'S', ('motorway',), None, -1600.0),
                                         ('exit_tychy', 'W', ('motorway',), None, -1100.0)):
        sp = exit_spot(side, kinds, name, near)
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
        'terrain': {'x0': tx0, 'y0': ty0, 'step': tstep, 'nx': tnx, 'ny': tny, 'h': [round(v, 2) for v in hs]},
        'roads': roads_out,
        'nodes': {str(k): list(v) for k, v in node_xy.items()},
        'rail': rails_out,
        'buildings': buildings,
        'areas': [[kind, flat_pts(ring), [flat_pts(h) for h in holes], extra] for _, _, kind, ring, holes, extra, _ in areas],
        'waterways': [[wd, flat_pts(pts)] for wd, pts in waterways],
        'trees': [v for x, y, c in trees for v in (r1(x), r1(y), c)],
        'lamps': flat_pts(lamps),
        'signals': flat_pts(signals),
        'stops': [[r1(x), r1(y), n] for x, y, n in stops],
        'places': places,
        'spots': spots,
        'credits': 'Map data © OpenStreetMap contributors (ODbL). Elevation: EU-DEM via OpenTopoData.',
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
