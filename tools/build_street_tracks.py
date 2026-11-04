"""Builds a street stage (a closed loop of real public roads) from OpenStreetMap, one route file per track:

    tools/street_routes/<key>.json      the route: the OSM way ids in loop order, where the start line is, the
                                        corner names (anchored to OSM nodes), and the TrackDef settings
    python3 tools/build_street_tracks.py <key> [...] [--refetch] [--check PNG] [--trams (only bake the tram rails)]

Writes, like build_tracks.py + build_surroundings.py do for the circuits:

    godot/data/tracks/<key>.json        centreline (2 m samples), elevation, terrain grid, street names
    godot/data/tracks/<key>.tres        the TrackDef (settings from the route file, corners)
    godot/data/tracks/<key>_env.json    the real surroundings (build_surroundings.py) plus "tram_rails" (OSM railway=tram on the
                                        carriageway, runs of [s, d, ...]; visual only) and "road_blockages":
                                        [[x, y, angle, width]] a barrier across every side road where it meets
                                        the route (angle: the barrier's direction, radians from +x towards +y)
    godot/data/tracks/<key>_land.png    the land map (build_surroundings.py)
    godot/data/tracks/<key>_far.json    the land out to 40 km on the horizon (fetch_horizon.py, fetch_landcover.py)

Raw downloads are cached so rebuilds run offline: the route ways and their level crossings in
tools/street_routes/cache/<key>_route.json, the elevations (OpenTopoData) in .../<key>_elevation.json, and the
surroundings (Overpass, fetch_surroundings.py's query over the terrain grid) in tools/osm_env/<key>.json.
--refetch downloads them again.

Route file keys: key, origin [lat, lon] (projection centre), dem (OpenTopoData dataset), grid (terrain grid
spacing, m), margin (terrain grid reach beyond the route, m), ways [way ids in driving order; consecutive ways
must share a node, and the last joins the first], start {"node": id, "before": m} (the start line, m before
the route reaches that node), corner_radius (m, the junction fillets), corners [{"at": s} or
{"node": id, "before"/"after": m}, "name"], blockage_types (highway values that get a barrier),
blockage_skip_service (service=* values left open, e.g. driveways), trackdef {TrackDef property: value}.
Optional: nodes [OSM node ids in driving order] gives the driven line node by node (a long route that uses one way
twice, or a roundabout, can't be told apart by ways alone); local "<open world key>" takes the ways, elevation and
surroundings from the open world's caches (tools/open_world/cache/<key>_*.json) instead of downloading them.
An elevated or sunken road (Tokyo's C1): dem "gsi" takes the ground from Japan's GSI 5 m elevation tiles (cached in
tools/.tiles/gsi/); levels {bridge {layer: m}, tunnel {layer: m}, cutting, bridge_min, tunnel_cover, grade, smooth,
clearance} puts the road over or under that ground by its ways' OSM bridge/tunnel/cutting tags (road_levels) and writes
the tunnels as "tunnels" [[first sample, last sample]]; spiral {node, after, turns, radius, side, entry_level,
exit_level, name} splices in a helix that isn't on the map (splice_spiral); building_reach (m) keeps only the
buildings and trees that close to the route; dense_city (true) makes plain mid-sized buildings flat-roofed blocks of
3-9 storeys instead of houses (a city centre that OSM maps without heights); surface_spans [[from m, to m, 'gravel' |
'dirt']] (from the start line) draws those stretches unpaved (Track.loose, the road shader; the grip stays the race's);
extra_landmarks places props OSM has no tag for (extra_landmarks(): Pszczyna's wisent enclosure).

Data © OpenStreetMap contributors, ODbL. Elevation: EU-DEM via OpenTopoData; in Japan, GSI elevation tiles (国土地理院).
"""
import json, math, os, sys, time, urllib.error, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import build_tracks as bt  # noqa: E402  (projection, resampling, smoothing)
import fetch_surroundings as fs  # noqa: E402
import build_surroundings as bs  # noqa: E402
import fetch_elevation as fe  # noqa: E402
import fetch_horizon as fh  # noqa: E402
import fetch_landcover as fl  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROUTES = os.path.join(HERE, 'street_routes')
CACHE = os.path.join(ROUTES, 'cache')
GODOT_TRACKS = os.path.join(HERE, '..', 'godot', 'data', 'tracks')
STEP = 2.0


def overpass(ql):
    """Runs an Overpass query, retrying when the server is busy."""
    body = urllib.parse.urlencode({'data': ql}).encode()
    for attempt in range(6):
        try:
            req = urllib.request.Request(fs.API, data=body, headers={'User-Agent': 'seicento-game/1.0 (street stages)'})
            return json.load(urllib.request.urlopen(req, timeout=300))
        except Exception as err:  # rate limit / busy server
            print('  retry', attempt, err, flush=True)
            time.sleep(10 + attempt * 20)
    raise SystemExit('Overpass failed')


def local_osm(cfg):
    """The open world's cached OSM download (build_open_world.py), for a route file with "local"."""
    return json.load(open(os.path.join(HERE, 'open_world', 'cache', cfg['local'] + '_osm.json')))


def route_data(cfg, refetch):
    """The route's ways (tags, nodes, geometry) and the level crossings on them, cached."""
    path = os.path.join(CACHE, cfg['key'] + '_route.json')
    if cfg.get('local') and (refetch or not os.path.exists(path)):
        els = local_osm(cfg)['elements']
        ids = set(cfg['ways'])
        ways = [e for e in els if e['type'] == 'way' and e['id'] in ids]
        on_route = {n for w in ways for n in w['nodes']}
        xings = [e for e in els if e['type'] == 'node' and e['id'] in on_route
                 and e.get('tags', {}).get('railway') in ('level_crossing', 'crossing')]
        os.makedirs(CACHE, exist_ok=True)
        json.dump({'elements': ways + xings}, open(path, 'w'), separators=(',', ':'))
    if refetch or not os.path.exists(path):
        ids = ','.join(str(i) for i in cfg['ways'])
        data = overpass(f'[out:json][timeout:120];way(id:{ids})->.r;.r out body geom;'
                        'node(w.r)["railway"~"^(level_crossing|crossing)$"];out body;')
        os.makedirs(CACHE, exist_ok=True)
        json.dump(data, open(path, 'w'), separators=(',', ':'))
    return json.load(open(path))


def chain(cfg, data, P):
    """The loop as projected points with, per point, its OSM node id (None between nodes) and street name.
    Each way contributes the stretch between the node it shares with the previous way and the one it shares
    with the next, in the direction of travel."""
    ways = {e['id']: e for e in data['elements'] if e['type'] == 'way'}
    if 'nodes' in cfg:
        return chain_nodes(cfg, ways, P)
    ids = cfg['ways']
    missing = [i for i in ids if i not in ways]
    assert not missing, f'ways not in the OSM data: {missing}'
    pts, nodes, names = [], [], []
    wtags = cfg['_wtags'] = []  # each point's way tags, for a route file with "levels"
    for k, wid in enumerate(ids):
        w = ways[wid]
        prev_w, next_w = ways[ids[k - 1]], ways[ids[(k + 1) % len(ids)]]
        a = [n for n in w['nodes'] if n in set(prev_w['nodes'])]
        b = [n for n in w['nodes'] if n in set(next_w['nodes'])]
        assert a and b, f'way {wid} does not share a node with its neighbours in the route'
        ia, ib = w['nodes'].index(a[0]), w['nodes'].index(b[0])
        idx = range(ia, ib + 1) if ib >= ia else range(ia, ib - 1, -1)
        name = w['tags'].get('name')
        for j in list(idx)[:-1]:  # the last node is the next way's first
            pts.append(P(w['geometry'][j]))
            nodes.append(w['nodes'][j])
            names.append(name)
            wtags.append(w['tags'])
    return pts, nodes, names


def chain_nodes(cfg, ways, P):
    """chain() for a route file that lists its nodes: each step runs along a route way joining the two nodes."""
    where = {}  # node -> [(way, index)]
    for w in ways.values():
        for j, n in enumerate(w['nodes']):
            where.setdefault(n, []).append((w, j))
    seq = cfg['nodes']
    pts, nodes, names = [], [], []
    surfs = cfg['_surfs'] = []  # each point's road surface (surface_of), for a route file with "surfaces"
    bridge = cfg['_bridge'] = []  # whether each point's way is a bridge, for a route file with "bridges"
    wtags = cfg['_wtags'] = []
    for k, n in enumerate(seq):
        m = seq[(k + 1) % len(seq)]
        hit = next(((w, j) for w, j in where[n] if (j + 1 < len(w['nodes']) and w['nodes'][j + 1] == m)
                    or (j > 0 and w['nodes'][j - 1] == m)), None)
        assert hit, f'nodes {n} and {m} are not neighbours on any route way'
        w, j = hit
        pts.append(P(w['geometry'][j]))
        nodes.append(n)
        names.append(w['tags'].get('name'))
        surfs.append(surface_of(w['tags'].get('highway'), w['tags']))
        bridge.append(w['tags'].get('bridge') not in (None, 'no'))
        wtags.append(w['tags'])
    return pts, nodes, names


def surface_of(h, t):
    """'gravel', 'dirt' or 'paved': how the open world drives the road (build_open_world.UNPAVED, LOOSE_GRAVEL)."""
    import build_open_world as bw
    s = t.get('surface', '')
    unpaved = s in bw.UNPAVED or (h == 'track' and s not in ('asphalt', 'concrete', 'paved', 'concrete:plates'))
    if not unpaved:
        return 'paved'
    return 'gravel' if s in bw.LOOSE_GRAVEL else 'dirt'


def local_elevation(cfg, P, rs, step, margin):
    """(profile, terrain grid) sampled from the open world's elevation grid, for a route file with "local"."""
    import build_open_world as bw
    g = json.load(open(os.path.join(HERE, 'open_world', 'cache', cfg['local'] + '_elevation.json')))
    def h(x, y):
        lat, lon = P.inv(x, y)
        u, v = bw.proj(lat, lon)
        fx = min(max((u - g['x0']) / g['step'], 0.0), g['nx'] - 1.001)
        fy = min(max((v - g['y0']) / g['step'], 0.0), g['ny'] - 1.001)
        i, j = int(fx), int(fy)
        a, b = fx - i, fy - j
        hh = g['h']
        q = lambda ii, jj: hh[jj * g['nx'] + ii]
        return (q(i, j) * (1 - a) + q(i + 1, j) * a) * (1 - b) + (q(i, j + 1) * (1 - a) + q(i + 1, j + 1) * a) * b
    xs, ys = [p[0] for p in rs], [p[1] for p in rs]
    x0, y0 = min(xs) - margin, min(ys) - margin
    nx = int((max(xs) + margin - x0) / step) + 1
    ny = int((max(ys) + margin - y0) / step) + 1
    return [h(x, y) for x, y in rs], (x0, y0, nx, ny, [h(x0 + i * step, y0 + j * step) for j in range(ny) for i in range(nx)])


def point_segment(p, a, b):
    """Distance from p to the segment a-b."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy or 1e-9
    f = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return math.dist(p, (a[0] + dx * f, a[1] + dy * f))


def fillet(pts, radius):
    """Rounds every vertex of a closed polyline with a circular arc of `radius` (smaller where the segments
    either side are too short to fit it), sampled about every metre."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        a = (p1[0] - p0[0], p1[1] - p0[1])
        b = (p2[0] - p1[0], p2[1] - p1[1])
        la, lb = math.hypot(*a), math.hypot(*b)
        ua, ub = (a[0] / la, a[1] / la), (b[0] / lb, b[1] / lb)
        turn = math.atan2(ua[0] * ub[1] - ua[1] * ub[0], ua[0] * ub[0] + ua[1] * ub[1])
        if abs(turn) < 1e-3:
            out.append(p1)
            continue
        t = min(radius * math.tan(abs(turn) / 2), 0.5 * la, 0.5 * lb)
        r = t / math.tan(abs(turn) / 2)
        start = (p1[0] - ua[0] * t, p1[1] - ua[1] * t)
        sg = 1 if turn > 0 else -1
        centre = (start[0] - ua[1] * r * sg, start[1] + ua[0] * r * sg)
        a0 = math.atan2(start[1] - centre[1], start[0] - centre[0])
        k = max(2, int(abs(turn) * r))
        for q in range(k + 1):
            ang = a0 + turn * q / k
            out.append((centre[0] + r * math.cos(ang), centre[1] + r * math.sin(ang)))
    return out


def project(pts, q):
    """(index of the segment, distance along the loop, distance off) of the point on the loop nearest q."""
    best = None
    acc = 0.0
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dy * dy or 1e-9
        f = max(0.0, min(1.0, ((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / l2))
        c = (a[0] + dx * f, a[1] + dy * f)
        d = math.dist(c, q)
        if best is None or d < best[2]:
            best = (i, acc + f * math.sqrt(l2), d)
        acc += math.sqrt(l2)
    return best


GSI_TILES = os.path.join(HERE, '.tiles', 'gsi')
_gsi = {}


def gsi_tile(src, z, x, y):
    """One GSI elevation tile (Geospatial Information Authority of Japan, https://maps.gsi.go.jp/development/
    ichiran.html, PNG encoding) as a 256 x 256 list of heights (None where it has no data), cached on disk."""
    key = (src, z, x, y)
    if key not in _gsi:
        from PIL import Image
        path = os.path.join(GSI_TILES, src, str(z), str(x), f'{y}.png')
        if not os.path.exists(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            url = f'https://cyberjapandata.gsi.go.jp/xyz/{src}/{z}/{x}/{y}.png'
            try:
                body = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'seicento-game/1.0'}),
                                              timeout=60).read()
            except urllib.error.HTTPError as err:  # outside the dataset: an empty tile
                if err.code != 404:
                    raise
                body = b''
            open(path, 'wb').write(body)
            time.sleep(0.2)
        if os.path.getsize(path) == 0:
            _gsi[key] = None
        else:
            im = Image.open(path).convert('RGB')
            px = im.load()
            hs = []
            for j in range(256):
                for i in range(256):
                    r, g, b = px[i, j]
                    v = (r << 16) | (g << 8) | b
                    hs.append(None if v == 1 << 23 else (v if v < 1 << 23 else v - (1 << 24)) * 0.01)
            _gsi[key] = hs
    return _gsi[key]


def gsi_height(lat, lon):
    """Ground height (m) from GSI's 5 m DEM (laser survey, the bare ground without buildings), else its 10 m one,
    else 0 (the sea)."""
    for src, z in (('dem5a_png', 15), ('dem_png', 14)):
        n = 2 ** z
        fx = (lon + 180) / 360 * n
        fy = (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n
        t = gsi_tile(src, z, int(fx), int(fy))
        if t is None:
            continue
        h = t[int((fy % 1) * 256) * 256 + int((fx % 1) * 256)]
        if h is not None:
            return h
    return 0.0


def elevation(cfg, pts, refetch):
    """Centreline heights (every 20 m) and the terrain grid round the route from OpenTopoData, cached."""
    path = os.path.join(CACHE, cfg['key'] + '_elevation.json')
    # (the profile runs from the start node, so a moved start line or changed route needs a new one)
    route_key = [cfg['start'], cfg['ways']] + ([cfg['spiral']] if cfg.get('spiral') else [])
    stale = os.path.exists(path) and json.load(open(path)).get('route', route_key) != route_key
    if refetch or stale or not os.path.exists(path):
        P = bt.proj_for(cfg['key'])
        rs, _, total = bt.resample(pts, [None] * len(pts), 20.0)
        step, margin = cfg['grid'], cfg['margin']
        if cfg.get('local'):
            line, (x0, y0, nx, ny, grid) = local_elevation(cfg, P, rs, step, margin)
        elif cfg['dem'] == 'gsi':  # Japan: GSI's tiles instead of OpenTopoData
            line = [gsi_height(*P.inv(x, y)) for x, y in rs]
            xs, ys = [p[0] for p in rs], [p[1] for p in rs]
            x0, y0 = min(xs) - margin, min(ys) - margin
            nx = int((max(xs) + margin - x0) / step) + 1
            ny = int((max(ys) + margin - y0) / step) + 1
            print(f'  terrain grid {nx} x {ny} (GSI)', flush=True)
            grid = [gsi_height(*P.inv(x0 + i * step, y0 + j * step)) for j in range(ny) for i in range(nx)]
        else:
            line = fe.query([P.inv(x, y) for x, y in rs], cfg['dem'])
            xs, ys = [p[0] for p in rs], [p[1] for p in rs]
            x0, y0 = min(xs) - margin, min(ys) - margin
            nx = int((max(xs) + margin - x0) / step) + 1
            ny = int((max(ys) + margin - y0) / step) + 1
            print(f'  terrain grid {nx} x {ny}', flush=True)
            grid = fe.query([P.inv(x0 + i * step, y0 + j * step) for j in range(ny) for i in range(nx)], cfg['dem'])
        os.makedirs(CACHE, exist_ok=True)
        json.dump({'route': route_key, 'line_step': total / len(rs), 'line': [round(h, 2) for h in line],
                   'grid': {'x0': x0, 'y0': y0, 'step': step, 'nx': nx, 'ny': ny, 'h': [round(h, 1) for h in grid]}},
                  open(path, 'w'))
    return json.load(open(path))


def splice_spiral(cfg, raw, nodes, names):
    """Splices a helix into the raw chain (route file "spiral": {"node": id, "after": m, "turns", "radius", "side": 1 or
    -1, "name", "exit_level"}): at the point `after` m past the node the road leaves its line, circles `turns` times
    round a centre `radius` m to one side (side 1: towards the game's +d normal, -1 the other way) and rejoins
    the line where it left it, heading the same way. The heights (road_levels) stack the rings over one another.
    Not a real road: OSM has no spiral on the route, the route file says where one is wanted."""
    sp = cfg['spiral']
    i = nodes.index(sp['node'])
    go = sp.get('after', 0.0)
    m = len(raw)
    while True:  # the segment `after` m on
        a, b = raw[i % m], raw[(i + 1) % m]
        seg = math.dist(a, b)
        if go < seg - 1.0:
            break
        go -= seg
        i += 1
    u = ((b[0] - a[0]) / seg, (b[1] - a[1]) / seg)
    A = (a[0] + u[0] * go, a[1] + u[1] * go)
    side, R, turns = sp.get('side', 1), sp['radius'], sp['turns']
    nrm = (-u[1], u[0])  # the game's +d normal (Track.NX, NY)
    C = (A[0] + side * R * nrm[0], A[1] + side * R * nrm[1])
    t0 = math.atan2(A[1] - C[1], A[0] - C[0])
    k = int(2 * math.pi * turns * R / 2.0)  # a point every 2 m
    ring = ([A] if go > 0.5 else []) + [(C[0] + R * math.cos(t0 + side * 2 * math.pi * turns * q / k),
                   C[1] + R * math.sin(t0 + side * 2 * math.pi * turns * q / k)) for q in range(1, k)]
    at = i % m + 1
    raw[at:at] = ring
    nodes[at:at] = [None] * len(ring)
    names[at:at] = [sp.get('name')] * len(ring)
    for key_ in ('_surfs', '_bridge', '_wtags'):
        if key_ in cfg:
            fill = {'_surfs': 'paved', '_bridge': True, '_wtags': {'_spiral': 'yes'}}[key_]
            cfg[key_][at:at] = [fill] * len(ring)
    cfg['_spiral_centre'] = C
    print(f'  spiral: {turns} turns of radius {R} m round ({C[0]:.0f}, {C[1]:.0f}), {len(ring) * 2} m')


def centreline(cfg, data, P):
    """The driven line: the chained OSM ways from the start line, junctions filleted, smoothed and resampled
    to STEP. Returns (points, street name per point, s of each route node on the line)."""
    raw, nodes, names = chain(cfg, data, P)
    if cfg.get('spiral'):
        splice_spiral(cfg, raw, nodes, names)
    # start line: `before` metres before the route reaches the start node
    k = nodes.index(cfg['start']['node'])
    raw, nodes, names = bt.rotate(raw, k), bt.rotate(nodes, k), bt.rotate(names, k)
    pts = fillet(raw, cfg['corner_radius'])
    pts, _, _ = bt.resample(pts, [None] * len(pts), 1.0)
    pts = bt.smooth(pts, 6)  # ease the curvature into each arc
    pts, _, total = bt.resample(pts, [None] * len(pts), STEP)
    # the node positions along the new line (s from the start node, so the start shift applies below)
    node_s = {}
    for p, nid in zip(raw, nodes):
        node_s.setdefault(nid, project(pts, p)[1])
    shift = round((total - cfg['start']['before']) / (total / len(pts)))
    pts = bt.rotate(pts, shift)
    step = total / len(pts)
    start_s = shift * step
    node_s = {nid: (s - start_s) % total for nid, s in node_s.items()}
    name_at = []
    per_way = cfg.get('surfaces') or cfg.get('bridges') or cfg.get('levels')
    for key_ in ('_surfs', '_bridge', '_wtags'):
        if per_way and key_ in cfg:
            cfg[key_] = bt.rotate(cfg[key_], k)
    cfg['_way_at'] = []  # per sample: the index of the raw segment (so of the way) it lies on
    m = len(raw)
    seg_d = lambda j, p: point_segment(p, raw[j % m], raw[(j + 1) % m])
    cur = None
    for p in pts:  # street name per sample, from the nearest raw OSM point
        i = min(range(len(raw)), key=lambda j: (raw[j][0] - p[0]) ** 2 + (raw[j][1] - p[1]) ** 2)
        name_at.append(names[i])
        if per_way:
            # walk the raw chain with the samples (a global nearest point can jump to the other level of a crossing)
            if cur is None:
                cur = min(range(m), key=lambda j: seg_d(j, p))
            else:
                cur = min(range(cur, cur + 6), key=lambda j: seg_d(j, p))
            cfg['_way_at'].append(cur % m)
    return pts, name_at, node_s, total, raw


BRIDGE_CLEARANCE = 6.0  # m of deck over the road below (build_open_world.CLEARANCE_ROAD)
BRIDGE_RAMP = 140.0  # m of approach either side of the crossing


def lift_bridges(cfg, pts, elev, step):
    """Where the loop passes under itself (a junction's overbridge), raise the upper road, the samples on an OSM
    bridge way, to BRIDGE_CLEARANCE over the lower one, eased in over BRIDGE_RAMP m (the game draws the deck where
    the loop crosses itself 4 m or more apart in height)."""
    n = len(pts)
    half = cfg['trackdef'].get('width', 6.5) / 2
    apart = int(200 / step)
    done = []
    for i in range(n):
        if not cfg['_bridge'][cfg['_way_at'][i]]:
            continue
        for j in range(n):
            if min(abs(i - j), n - abs(i - j)) < apart or math.dist(pts[i], pts[j]) > half:
                continue
            if cfg['_bridge'][cfg['_way_at'][j]] or any(min(abs(i - a), n - abs(i - a)) < apart for a, _ in done):
                continue
            done.append((i, j))
    span = int(BRIDGE_RAMP / step)
    for up, low in done:
        need = BRIDGE_CLEARANCE - (elev[up] - elev[low])
        if need > 0:
            for k in range(-span, span + 1):
                elev[(up + k) % n] += need * (0.5 + 0.5 * math.cos(math.pi * k / span))
        print(f'  bridge at {up * step:.0f} m over {low * step:.0f} m: deck raised {max(need, 0):.1f} m')


def road_levels(cfg, pts, ground, step):
    """Heights of an elevated or sunken road (route file "levels"). Each sample wants to sit over the ground by its OSM
    way's kind: a bridge's deck `levels.bridge[layer]` m up, a tunnel `levels.tunnel[layer]` and a cutting
    `levels.cutting` m down, the rest on it. OSM layers only order the roads at a crossing, so those are wishes; what
    must hold is a deck at least `levels.bridge_min` m over the street and a bore at least `levels.tunnel_cover` m
    under it (both easing to nothing at the abutments and portals), and a cutting below street level. The road takes
    the closest profile to the wishes that never climbs or dives steeper than `levels.grade`, inside those bounds.
    A spliced spiral runs evenly from `spiral.entry_level` to `spiral.exit_level` over the ground.
    Returns (heights, tunnel spans [[first sample, last sample]]).
    """
    lv = cfg['levels']
    n = len(pts)
    g = bt.smooth_loop(ground, lv.get('ground_smooth', 60.0) / step)
    big = 1e9
    kind = [''] * n
    off = [0.0] * n
    for i in range(n):
        t = cfg['_wtags'][cfg['_way_at'][i]]
        layer = t.get('layer', '0')
        if t.get('_spiral'):
            kind[i] = 'spiral'
        elif t.get('tunnel') not in (None, 'no'):
            kind[i], off[i] = 'tunnel', lv['tunnel'].get(layer, lv['tunnel']['-1'])
        elif t.get('bridge') not in (None, 'no'):
            kind[i], off[i] = 'bridge', lv['bridge'].get(layer, lv['bridge']['1'])
        elif t.get('cutting') not in (None, 'no'):
            kind[i], off[i] = 'cutting', lv['cutting']
        else:
            kind[i] = 'ground'
    # how far each sample is from the ends of its run of one kind (abutments, portals)
    to_end = [0.0] * n
    for i in range(n):
        if kind[i] != kind[i - 1]:
            j = i
            while kind[(j + 1) % n] == kind[i] and (j + 1) % n != i:
                j += 1
            run = (j - i) % n + 1
            for k in range(run):
                to_end[(i + k) % n] = min(k, run - 1 - k) * step
    lo, hi, target = [-big] * n, [big] * n, [g[i] + off[i] for i in range(n)]
    for i in range(n):
        if kind[i] == 'bridge':
            lo[i] = g[i] + lv.get('bridge_min', 5.5) * min(1.0, to_end[i] / 40.0)
        elif kind[i] == 'tunnel':
            hi[i] = g[i] - lv.get('tunnel_cover', 8.0) * min(1.0, to_end[i] / 60.0)
        elif kind[i] == 'cutting':
            hi[i] = g[i] - 1.5 * min(1.0, to_end[i] / 20.0)
    spiral = [i for i in range(n) if kind[i] == 'spiral']
    if spiral:
        a, b = spiral[0], spiral[-1]
        assert b - a + 1 == len(spiral), 'the spiral must not straddle the start line'
        sp = cfg['spiral']
        top, bot = g[a] + sp['entry_level'], g[a] + sp['exit_level']  # (one ground: the rings stand over one spot)
        for i in spiral:
            target[i] = lo[i] = hi[i] = top + (bot - top) * (i - a) / (b - a)
        lead = int(40 / step)  # level into and out of the helix, where the line runs beside its first and last ring
        for k in range(1, lead + 1):
            target[a - k] = lo[a - k] = hi[a - k] = top
            target[(b + k) % n] = lo[(b + k) % n] = hi[(b + k) % n] = bot
        print(f"  spiral: {top:.1f} m -> {bot:.1f} m, {(top - bot) / sp['turns']:.1f} m between rings, "
              f"grade {(top - bot) / ((b - a) * step) * 100:.1f}%")

    def envelope(arr, better, delta):  # carried along the loop at the steepest grade, both ways round
        arr = arr[:]
        for _ in range(2):
            for i in range(n):
                arr[i] = better(arr[i], arr[i - 1] + delta)
            for i in range(n - 1, -1, -1):
                arr[i] = better(arr[i], arr[(i + 1) % n] + delta)
        return arr
    grade = lv.get('grade', 0.06) * step
    U = envelope(hi, min, grade)
    # where a deck's clearance and a bore's cover can't both be had at this grade, the bore wins: a tunnel must stay
    # under the street, a deck over a moat or a dip the smoothed ground misses may run lower (clipping each bound by
    # U, which keeps to the grade, leaves L under U everywhere)
    eased = sum(1 for i in range(n) if lo[i] > U[i])
    if eased:
        print(f'  levels: {eased * step:.0f} m of deck lower than {lv.get("bridge_min", 5.5)} m over the smoothed ground, '
              f'between tunnels')
    L = envelope([min(lo[i], U[i]) for i in range(n)], max, -grade)
    # the wishes made no steeper than the grade (the mean of the tightest profiles over and under them, which never
    # strays more than half their worst step), then pushed inside the bounds (both keep to the grade)
    h = [(p + q) / 2 for p, q in zip(envelope(target, max, -grade), envelope(target, min, grade))]
    clamp = lambda i, v: (L[i] + U[i]) / 2 if L[i] > U[i] else min(max(v, L[i]), U[i])
    h = [clamp(i, v) for i, v in enumerate(h)]
    for _ in range(3):  # round the changes of grade (vertical curves), still inside the bounds
        h = [clamp(i, v) for i, v in enumerate(bt.smooth_loop(h, lv.get('smooth', 30.0) / step))]
    if os.environ.get('LEVELS_DEBUG'):
        for i in range(0, n, int(50 / step)):
            print(f'    {i * step:7.0f} {kind[i]:8} ground {g[i]:5.1f} want {target[i]:5.1f} '
                  f'bounds {max(L[i], -99):6.1f} {min(U[i], 999):6.1f} road {h[i]:5.1f}')
    steep = max(abs(h[i] - h[i - 1]) for i in range(n)) / step
    print(f'  levels: steepest grade {steep * 100:.1f}%')
    tunnels = []
    for i in range(n):
        if kind[i] == 'tunnel' and kind[i - 1] != 'tunnel':
            j = i
            while kind[(j + 1) % n] == 'tunnel' and (j + 1) % n != i:
                j += 1
            tunnels.append([i, j % n])
    cfg['_kind'] = kind
    return h, tunnels


def check_clearance(pts, elev, half, step, need):
    """Warns where two stretches of the loop pass over one another with less than `need` m between them."""
    n = len(pts)
    cell = 8.0
    grid = {}
    for i, p in enumerate(pts):
        grid.setdefault((int(p[0] // cell), int(p[1] // cell)), []).append(i)
    worst = {}
    for i, p in enumerate(pts):
        cx, cy = int(p[0] // cell), int(p[1] // cell)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for j in grid.get((cx + dx, cy + dy), []):
                    if j <= i or min(j - i, n - j + i) * step < 150 or math.dist(p, pts[j]) > 2 * half + 2:
                        continue
                    gap = abs(elev[i] - elev[j])
                    if gap < need and gap < worst.get(i // 50, (1e9, 0, 0))[0]:
                        worst[i // 50] = (gap, i, j)
    for gap, i, j in worst.values():
        print(f'  WARNING: {i * step:.0f} m and {j * step:.0f} m cross only {gap:.1f} m apart')
    return not worst


def blockages(cfg, osm, route, node_s, pts, half):
    """A barrier across each side road (OSM highway way sharing a node with the route), where it is clear of
    the stage's run-off: [x, y, angle, width]."""
    route_ways = {e['id'] for e in route['elements'] if e['type'] == 'way'}
    route_nodes = set(node_s)
    # a route file that lists its nodes: a route way the loop only partly drives (it turns off it, or crosses it) gets a
    # barrier on the arms it leaves, like any side road; the edges the loop drives are the consecutive listed nodes
    seq = cfg.get('nodes')
    driven = {frozenset(e) for e in zip(seq, seq[1:] + seq[:1])} if seq else None
    P = bt.proj_for(cfg['key'])
    clear = half + cfg['trackdef'].get('runoff', 1.8) + 2.0
    out = []
    for el in osm['elements']:
        tags = el.get('tags', {})
        on_route = el.get('type') == 'way' and el['id'] in route_ways
        if el['type'] != 'way' or (on_route and driven is None) or tags.get('highway') not in cfg['blockage_types']:
            continue
        if tags.get('highway') == 'service' and tags.get('service') in cfg.get('blockage_skip_service', ()):
            continue
        if tags.get('area') == 'yes' or tags.get('access') in ('no', 'private') and tags.get('highway') == 'service':
            continue
        nodes, geom = el.get('nodes', []), el.get('geometry', [])
        if len(nodes) != len(geom):
            continue
        xy = [P(g) for g in geom]
        for k, nid in enumerate(nodes):
            if nid not in route_nodes:
                continue
            for arm, nxt in ((xy[k::-1], k - 1), (xy[k:], k + 1)):  # the side road either way from the junction
                if on_route and (not 0 <= nxt < len(nodes) or frozenset((nid, nodes[nxt])) in driven):
                    continue  # the loop drives on along this way
                hit = arm_point(arm, pts, clear)
                if not hit:
                    continue
                (x, y), (dx, dy) = hit
                hw = tags['highway']
                width = bs.number(tags.get('width')) or bs.ROAD_WIDTH.get(hw) or bs.DIRT_WIDTH.get(hw, 4.0)
                width = max(3.2, min(width + 1.0, 10.0))
                if any(math.dist((x, y), (b[0], b[1])) < 4.0 for b in out):
                    continue
                out.append([round(x, 2), round(y, 2), round(math.atan2(dy, dx) + math.pi / 2, 4), round(width, 1),
                            el['id'], tags.get('name', '')])
    return out


def arm_point(arm, pts, clear):
    """Where a side road's arm (points from the junction outwards) first gets `clear` metres from the stage's
    centreline: (point, direction), or None if it never does (a stub)."""
    run = 0.0
    for a, b in zip(arm, arm[1:]):
        seg = math.dist(a, b)
        if seg < 1e-6:
            continue
        for q in range(1, int(seg / 0.5) + 2):
            f = min(1.0, q * 0.5 / seg)
            p = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
            if nearest(pts, p) >= clear:
                return p, ((b[0] - a[0]) / seg, (b[1] - a[1]) / seg)
        run += seg
        if run > 120:
            return None
    return None


def tram_rails(osm, pts, half, P, step=1.0):
    """OSM railway=tram alignment that lies on the carriageway, as runs in the track's own frame (visual only, no
    collision): [[s, d, s, d, ...]] with s the distance along the centreline and d the signed offset across it
    (+ to the left of the driving direction, the game's normal), sampled every `step` metres. Underground
    (layer<0 / tunnel) and bridge-deck tram ways are skipped, as is any tram way off the road."""
    n = len(pts)
    seg = [math.dist(pts[i], pts[(i + 1) % n]) for i in range(n)]
    ds = sum(seg) / n
    lim = half - 0.9  # the rail bed has to fit on the tarmac
    runs = []
    for el in osm['elements']:
        tags = el.get('tags', {})
        if el['type'] != 'way' or tags.get('railway') != 'tram' or not el.get('geometry'):
            continue
        if tags.get('tunnel') in ('yes', 'building_passage') or tags.get('bridge') == 'yes' or float(tags.get('layer', 0) or 0) != 0:
            continue
        g = [P(p) for p in el['geometry'] if p]
        dense = []
        for a, b in zip(g, g[1:]):
            L = math.dist(a, b)
            for q in range(max(1, int(L / step))):
                f = q * step / L if L else 0
                dense.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
        dense.append(g[-1])
        cur = []
        for p in dense:
            i = min(range(n), key=lambda j: (pts[j][0] - p[0]) ** 2 + (pts[j][1] - p[1]) ** 2)
            c, nx = pts[i], pts[(i + 1) % n]
            tx, ty = nx[0] - pts[i - 1][0], nx[1] - pts[i - 1][1]
            tl = math.hypot(tx, ty) or 1.0
            tx, ty = tx / tl, ty / tl
            along = (p[0] - c[0]) * tx + (p[1] - c[1]) * ty
            d = -(p[0] - c[0]) * ty + (p[1] - c[1]) * tx  # left normal: (-ty, tx)
            if abs(d) <= lim and abs(along) < ds:
                cur += [round(i * ds + along, 2), round(d, 2)]
            else:
                if len(cur) >= 12:
                    runs.append(cur)
                cur = []
        if len(cur) >= 12:
            runs.append(cur)
    return runs


def nearest(pts, p):
    """Distance from p to the nearest centreline sample (2 m apart, close enough for clearances)."""
    return math.sqrt(min((q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2 for q in pts))


def tres_value(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, list) and v and all(isinstance(p, list) and len(p) == 2 for p in v):  # (from, to) pairs
        return 'PackedVector2Array(' + ', '.join(repr(float(x)) for p in v for x in p) + ')'
    if isinstance(v, str) and v.startswith('Color('):  # a Godot colour literal, written as is
        return v
    return json.dumps(v, ensure_ascii=False)


def write_tres(cfg, corners):
    """The TrackDef resource: the route file's settings and the corner names."""
    lines = ['[gd_resource type="Resource" script_class="TrackDef" format=3]', '',
             '[ext_resource type="Script" path="res://scripts/data/corner_name.gd" id="1"]',
             '[ext_resource type="Script" path="res://scripts/data/track_def.gd" id="2"]', '']
    for i, (s, name) in enumerate(corners):
        lines += [f'[sub_resource type="Resource" id="c{i + 1}"]', 'script = ExtResource("1")',
                  f'distance = {s:.1f}', f'name = {json.dumps(name, ensure_ascii=False)}', '']
    lines += ['[resource]', 'script = ExtResource("2")', f'key = "{cfg["key"]}"']
    for k, v in cfg['trackdef'].items():
        lines.append(f'{k} = {tres_value(v)}')
    lines.append('corners = Array[ExtResource("1")]([' + ', '.join(f'SubResource("c{i + 1}")' for i in range(len(corners))) + '])')
    with open(os.path.join(GODOT_TRACKS, cfg['key'] + '.tres'), 'w') as f:
        f.write('\n'.join(lines) + '\n')


def build_trams(key):
    """Only re-bakes env["tram_rails"] into <key>_env.json from the cached OSM download (no other output changes)."""
    cfg = json.load(open(os.path.join(ROUTES, key + '.json')))
    bt.TRACKS[key] = dict(origin=tuple(cfg['origin']), dem=cfg['dem'], grid=cfg['grid'], godot=True)
    P = bt.proj_for(key)
    pts = centreline(cfg, route_data(cfg, False), P)[0]
    osm = json.load(open(os.path.join(fs.OUT_DIR, key + '.json')))
    runs = tram_rails(osm, pts, cfg['trackdef'].get('width', 6.5) / 2, P)
    env_path = os.path.join(GODOT_TRACKS, key + '_env.json')
    env = json.load(open(env_path))
    env['tram_rails'] = runs
    json.dump(env, open(env_path, 'w'), separators=(',', ':'))
    print(f'{key}: {len(runs)} tram rail runs, {sum(len(r) // 2 for r in runs)} samples')


def build(key, refetch=False, check=None):
    cfg = json.load(open(os.path.join(ROUTES, key + '.json')))
    bt.TRACKS[key] = dict(origin=tuple(cfg['origin']), dem=cfg['dem'], grid=cfg['grid'], godot=True)
    P = bt.proj_for(key)
    route = route_data(cfg, refetch)
    pts, names, node_s, total, raw = centreline(cfg, route, P)
    step = total / len(pts)
    ev = elevation(cfg, raw, refetch)  # (the profile runs from the start node)
    # heights along the line: the 20 m DEM profile was taken along the raw chain from the start node
    line = ev['line']
    m = len(line)
    shift = cfg['start']['before'] / total * m
    elev = []
    for i in range(len(pts)):
        u = (i / len(pts) * m - shift) % m
        k, f = int(u) % m, u - int(u)
        elev.append(line[k] * (1 - f) + line[(k + 1) % m] * f)
    elev = bt.smooth_loop(elev, 30 / step)
    tunnels = []
    street = elev  # the ground along the line, before road_levels lifts or sinks the road
    if cfg.get('levels'):
        elev, tunnels = road_levels(cfg, pts, elev, step)
        check_clearance(pts, elev, cfg['trackdef'].get('width', 6.5) / 2, step, cfg['levels'].get('clearance', 6.5))
    if cfg.get('bridges'):
        lift_bridges(cfg, pts, elev, step)
    sectors, last = [], None
    for i, nm in enumerate(names):
        if nm and nm != last:
            sectors.append([i, nm])
            last = nm
    track = {'step': step, 'length': total, 'pts': [v for p in pts for v in (round(p[0], 2), round(p[1], 2))],
             'names': sectors, 'elev': [round(h, 2) for h in elev], 'grid': ev['grid']}
    if tunnels:  # covered spans [first sample, last sample] (Track.tunnels)
        track['tunnels'] = tunnels
    if cfg.get('surfaces'):  # road surface sectors, like the names: [[first sample, 'paved' | 'gravel' | 'dirt']]
        track['surfaces'] = []
        for i, j in enumerate(cfg['_way_at']):
            sf = cfg['_surfs'][j]
            if not track['surfaces'] or track['surfaces'][-1][1] != sf:
                track['surfaces'].append([i, sf])
    if cfg.get('surface_spans'):  # hand-set spans [[from m, to m, kind]] from the start line (paths OSM leaves untagged)
        track['surfaces'] = [[0, 'paved']]
        for a, b, kind in sorted(cfg['surface_spans']):
            track['surfaces'] += [[int(round(a / step)), kind], [int(round(b / step)), 'paved']]
    if 'stage' in cfg:  # a point-to-point rally stage on the loop: [from, to], m from the start line
        track['stage'] = [round(node_s[cfg['stage']['start']], 1), round(node_s[cfg['stage']['finish']], 1)]
        print(f"  stage {track['stage'][0]:.0f} -> {track['stage'][1]:.0f} m ({track['stage'][1] - track['stage'][0]:.0f} m)")
    with open(os.path.join(GODOT_TRACKS, key + '.json'), 'w') as f:
        json.dump(track, f, separators=(',', ':'))
    # corners: s from the start line
    corners = []
    for c in cfg['corners']:
        if 'at' in c:
            s = c['at']
        else:
            s = (node_s[c['node']] - c.get('before', 0) + c.get('after', 0)) % total
        corners.append((round(s, 1), c['name']))
    corners.sort()
    write_tres(cfg, corners)
    print(f'{key}: {total:.0f} m, {len(pts)} samples, height {min(elev):.1f}-{max(elev):.1f} m')
    for s, nm in corners:
        print(f'  {s:7.1f}  {nm}')
    # the surroundings over the terrain grid
    env_src = os.path.join(fs.OUT_DIR, key + '.json')
    if cfg.get('local') and (refetch or not os.path.exists(env_src)):
        # the open world's download already holds everything the scenery uses; keep what touches the terrain box
        s_, w_, n_, e_ = fs.bbox(key)
        def inside(el):
            b = el.get('bounds')
            if b:
                return b['minlat'] <= n_ and b['maxlat'] >= s_ and b['minlon'] <= e_ and b['maxlon'] >= w_
            return 'lat' not in el or (s_ <= el['lat'] <= n_ and w_ <= el['lon'] <= e_)
        os.makedirs(fs.OUT_DIR, exist_ok=True)
        json.dump({'elements': [el for el in local_osm(cfg)['elements'] if inside(el)]}, open(env_src, 'w'), separators=(',', ':'))
    elif refetch or not os.path.exists(env_src):  # (a "local" route never downloads: its surroundings came from the cache above)
        print('  fetching surroundings', fs.bbox(key), flush=True)
        os.makedirs(fs.OUT_DIR, exist_ok=True)
        json.dump(fs.fetch(key), open(env_src, 'w'), separators=(',', ':'))
    bs.DENSE_CITY[key] = bool(cfg.get('dense_city'))
    bs.build(key)
    osm = json.load(open(env_src))
    half = cfg['trackdef'].get('width', 6.5) / 2
    blocks = blockages(cfg, osm, route, node_s, pts, half)
    env_path = os.path.join(GODOT_TRACKS, key + '_env.json')
    env = json.load(open(env_path))
    env['road_blockages'] = [b[:4] for b in blocks]
    env['tram_rails'] = tram_rails(osm, pts, half, P)
    if env.get('bridges'):  # every street stage, not only those with "bridges"/"levels" (Oświęcim's and Pszczyna's
        # own river bridges were drawn as rows of 7 m road bridges along the road)
        # build_surroundings records a bridge "over the circuit" wherever a bridge way crosses the centreline, so the
        # route's own bridges (the S1 over the Soła, a junction's overbridge) weave across it as a row of decks; the
        # game draws a real crossing of the loop over itself (RaceWorld._crossings), so keep only other roads' bridges
        own = [[P(g) for g in w['geometry']] for w in route['elements']
               if w['type'] == 'way' and w.get('tags', {}).get('bridge') not in (None, 'no')]
        def on_route(b):
            return any(point_segment((b[1], b[2]), u, v) < 3.0 for line in own for u, v in zip(line, line[1:]))
        def alongside(b):
            # a bridge way running within 25 degrees of the road where it "crosses" it (the other carriageway or the
            # footway of the route's own bridge, weaving across the smoothed line) does not pass over it
            i = min(range(len(pts)), key=lambda j: (pts[j][0] - b[1]) ** 2 + (pts[j][1] - b[2]) ** 2)
            a, c = pts[i - 1], pts[(i + 1) % len(pts)]
            tl = math.dist(a, c) or 1.0
            return abs(b[3] * (c[0] - a[0]) + b[4] * (c[1] - a[1])) / tl > math.cos(math.radians(25))
        kept = [b for b in env.get('bridges', []) if not on_route(b) and not alongside(b)]
        if cfg.get('levels'):  # another road's bridge passes over the route only where that runs below the street
            def sunk(b):
                i = min(range(len(pts)), key=lambda j: (pts[j][0] - b[1]) ** 2 + (pts[j][1] - b[2]) ** 2)
                return elev[i] < street[i] - 3.0 and cfg['_kind'][i] != 'tunnel'
            kept = [b for b in kept if sunk(b)]
        print(f"  bridges over the route: {len(kept)} kept, {len(env.get('bridges', [])) - len(kept)} of its own dropped")
        env['bridges'] = kept
    if cfg['trackdef'].get('street_stage'):
        env['stands'] = []  # no grandstands on a public road (OSM has none here anyway)
    if cfg.get('building_reach') or cfg.get('spiral'):
        trim_scenery(cfg, env, pts, half)
    if cfg.get('extra_landmarks'):
        extra_landmarks(cfg, env, pts)
    json.dump(env, open(env_path, 'w'), separators=(',', ':'))
    fh.build(key, ev)  # the distant land (its height and cover tiles are cached in tools/.tiles/)
    fl.build(key)
    print(f'  {len(blocks)} road blockages: ' + ', '.join(sorted({b[5] or str(b[4]) for b in blocks})))
    if check:
        check_image(key, pts, osm, blocks, corners, node_s, check)


# footprints (length along the model's x, width) of the props extra_landmarks places (build_wisents.py)
EXTRA_FOOT = {'WisentBull': (3.3, 1.3), 'WisentCow': (2.9, 1.1), 'WisentCowLying': (2.9, 1.3), 'WisentCalf': (1.7, 0.7),
              'HayRack': (3.5, 2.2), 'PaddockFence': (6.0, 0.3)}


def extra_landmarks(cfg, env, pts):
    """Props that OSM has no landmark tag for, placed by the route file's "extra_landmarks" (Pszczyna's wisents):
    {"pieces": [[model, x, y, angle_deg]] (track metres; angle: the model's x axis, from +x towards +y),
     "fence": {"model", "bay" (m), "ring": [[x, y], ...] (the outline it follows, closed), "reach" (m: only the bays
     this near the route)}, "clear" (m: no trees, and no forest on the land map, this near a piece; the fence
     line keeps a quarter of it), "clearings": [[x, y, r]] (more open ground, no trees), "roam" (m: how far an animal
     wanders from where it is placed)}. Appended to env "landmarks" ([model, x, y, length, width, angle, 0]);
     surroundings.gd stands them on the ground and turns their +z side to the road. With a fence, env "herd"
     {ring: [x, y, ...] (the fence outline), roam} lets wisent_herd.gd walk the animals about inside it."""
    ex = cfg['extra_landmarks']
    out = []
    for model, x, y, ang in ex.get('pieces', []):
        ln, wd = EXTRA_FOOT.get(model, (0.0, 0.0))
        out.append([model, round(x, 1), round(y, 1), ln, wd, round(math.radians(ang), 3), 0.0])
    fence = ex.get('fence')
    line = []
    if fence:
        ring = [tuple(p) for p in fence['ring']]
        bay = fence.get('bay', 6.0)
        reach2 = fence.get('reach', 1e9) ** 2
        for a, b in zip(ring, ring[1:] + ring[:1]):
            n = max(1, round(math.dist(a, b) / bay))
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            for k in range(n):
                u = (k + 0.5) / n
                c = (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
                if min((p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 for p in pts[::5]) > reach2:
                    continue
                # each bay stretched to its share of the side, so the posts meet at the corners
                out.append([fence['model'], round(c[0], 1), round(c[1], 1), round(math.dist(a, b) / n, 2), 0.3,
                            round(ang, 3), 0.0])
                line.append(c)
    env.setdefault('landmarks', []).extend(out)
    if fence:
        env['herd'] = {'ring': [round(v, 1) for p in fence['ring'] for v in p], 'roam': ex.get('roam', 10.0)}
    clear = ex.get('clear', 0.0)
    fmodel = fence['model'] if fence else None
    spots = [(o[1], o[2], clear) for o in out if o[0] != fmodel and clear > 0.0]
    spots += [(x, y, clear * 0.25) for x, y in line if clear > 0.0]
    spots += [tuple(c) for c in ex.get('clearings', [])]  # open lawns [x, y, radius] (a view the woods would hide)
    if spots:
        def bare(x, y):
            return any((x - sx) ** 2 + (y - sy) ** 2 < r * r for sx, sy, r in spots)
        trees = env.get('trees', [])
        env['trees'] = [v for k in range(0, len(trees) - 1, 2) if not bare(trees[k], trees[k + 1]) for v in trees[k:k + 2]]
        # and the forest the land map plants trees from: a meadow round the herd
        from PIL import Image
        path = os.path.join(GODOT_TRACKS, cfg['key'] + '_land.png')
        land = env['land']
        img = Image.open(path).convert('RGBA')
        res = land['w'] / img.size[0]
        px = img.load()
        for sx, sy, r in spots:
            for j in range(int((sy - r - land['y0']) / res), int((sy + r - land['y0']) / res) + 1):
                for i in range(int((sx - r - land['x0']) / res), int((sx + r - land['x0']) / res) + 1):
                    if 0 <= i < img.size[0] and 0 <= j < img.size[1] and \
                            (land['x0'] + (i + 0.5) * res - sx) ** 2 + (land['y0'] + (j + 0.5) * res - sy) ** 2 < r * r:
                        q = px[i, j]
                        px[i, j] = (q[0], q[1], q[2], 0)
        img.save(path, optimize=True)
    print(f"  extra landmarks: {len(out)} ({len(line)} fence bays)")


def trim_scenery(cfg, env, pts, half):
    """Drops the buildings and trees further than `building_reach` m from the route (a city centre maps tens of
    thousands, more than the game draws well), and those standing in the spiral's footprint."""
    from PIL import Image, ImageDraw
    reach = cfg.get('building_reach', 1e5)
    res = 5.0
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = min(xs) - reach - 10, min(ys) - reach - 10
    mask = Image.new('1', (int((max(xs) - x0 + reach + 10) / res) + 1, int((max(ys) - y0 + reach + 10) / res) + 1), 0)
    if reach < 1e5:
        ImageDraw.Draw(mask).line([((x - x0) / res, (y - y0) / res) for x, y in pts + pts[:1]], fill=1,
                                  width=int(2 * reach / res), joint='curve')
    else:
        mask.paste(1, (0, 0) + mask.size)
    px = mask.load()
    C = cfg.get('_spiral_centre')
    disc = (cfg['spiral']['radius'] + half + 8.0) if C else 0.0

    def keep(x, y):
        i, j = int((x - x0) / res), int((y - y0) / res)
        inside = 0 <= i < mask.size[0] and 0 <= j < mask.size[1] and px[i, j]
        return inside and not (C and math.dist((x, y), C) < disc)
    before = len(env.get('buildings', []))
    env['buildings'] = [b for b in env.get('buildings', [])
                        if all(keep(b[k], b[k + 1]) for k in range(3, len(b) - 1, 2))]
    trees = env.get('trees', [])
    env['trees'] = [v for k in range(0, len(trees) - 1, 2) if keep(trees[k], trees[k + 1]) for v in trees[k:k + 2]]
    env['towers'] = [t for t in env.get('towers', []) if keep(t[2], t[3])]
    print(f"  scenery: {len(env['buildings'])} of {before} buildings kept (reach {reach:.0f} m, spiral clear)")


def check_image(key, pts, osm, blocks, corners, node_s, path):
    """A top-down picture of the stage over the OSM data it was built from, to compare with the map."""
    from PIL import Image, ImageDraw, ImageFont
    P = bt.proj_for(key)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    pad = 120
    x0, y0, x1, y1 = min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad
    sc = 2000 / max(x1 - x0, y1 - y0)
    im = Image.new('RGB', (int((x1 - x0) * sc), int((y1 - y0) * sc)), '#f4f1ea')
    dr = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 22)
    except OSError:
        font = ImageFont.load_default()
    tp = lambda p: ((p[0] - x0) * sc, (p[1] - y0) * sc)
    for el in osm['elements']:
        tags = el.get('tags', {})
        if el['type'] == 'node':
            continue
        outer, _ = bs.rings_of(el, P)
        if bs.match(tags, bs.WATER_AREAS) is not None:
            for r in outer:
                dr.polygon([tp(p) for p in r], fill='#9cc8ef')
        elif bs.match(tags, bs.FOREST_AREAS) is not None:
            for r in outer:
                dr.polygon([tp(p) for p in r], fill='#bcd8b0')
    for el in osm['elements']:
        tags = el.get('tags', {})
        if el['type'] != 'way':
            continue
        g = [tp(P(p)) for p in el.get('geometry', []) if p]
        if len(g) < 2:
            continue
        if 'building' in tags:
            dr.polygon(g, fill='#a86a50', outline='#5a3020')
        elif tags.get('railway') in ('rail', 'light_rail', 'narrow_gauge'):
            dr.line(g, fill='#222', width=5)
        elif tags.get('highway') in bs.ROAD_WIDTH or tags.get('highway') in bs.DIRT_WIDTH:
            dr.line(g, fill='#9a9a9a', width=max(2, int(bs.ROAD_WIDTH.get(tags['highway'], 2.5) * sc * 0.6)))
    dr.line([tp(p) for p in pts] + [tp(pts[0])], fill='#e01010', width=max(3, int(6.5 * sc)))
    for x, y, ang, w, *_ in blocks:
        dx, dy = math.cos(ang) * w / 2, math.sin(ang) * w / 2
        dr.line([tp((x - dx, y - dy)), tp((x + dx, y + dy))], fill='#ff8800', width=7)
    a, b = pts[0], pts[3]
    nx, ny = -(b[1] - a[1]), b[0] - a[0]
    ln = math.hypot(nx, ny)
    dr.line([tp((a[0] + nx / ln * 8, a[1] + ny / ln * 8)), tp((a[0] - nx / ln * 8, a[1] - ny / ln * 8))], fill='black', width=8)
    total = len(pts)
    step = None
    for s, nm in corners:
        i = int(round(s / 2.0)) % total
        p = tp(pts[i])
        dr.ellipse((p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6), fill='blue')
        dr.text((p[0] + 8, p[1] - 10), nm, fill='#102080', font=font)
    im.save(path)
    print('  check image', path)


if __name__ == '__main__':
    args = sys.argv[1:]
    refetch = '--refetch' in args
    check = None
    if '--check' in args:
        check = args[args.index('--check') + 1]
        args.remove(check)
    keys = [a for a in args if not a.startswith('--')]
    if not keys:
        raise SystemExit(__doc__)
    if '--trams' in args:  # only the tram rails, from the cached download
        for k in keys:
            build_trams(k)
        raise SystemExit(0)
    for k in keys:
        build(k, refetch, check if len(keys) == 1 else (check and check.replace('.png', f'_{k}.png')))
