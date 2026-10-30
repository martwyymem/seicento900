"""Builds a street stage (a closed loop of real public roads) from OpenStreetMap, one route file per track:

    tools/street_routes/<key>.json      the route: the OSM way ids in loop order, where the start line is, the
                                        corner names (anchored to OSM nodes), and the TrackDef settings
    python3 tools/build_street_tracks.py <key> [...] [--refetch] [--check PNG]

Writes, like build_tracks.py + build_surroundings.py do for the circuits:

    godot/data/tracks/<key>.json        centreline (2 m samples), elevation, terrain grid, street names
    godot/data/tracks/<key>.tres        the TrackDef (settings from the route file, corners)
    godot/data/tracks/<key>_env.json    the real surroundings (build_surroundings.py) plus "road_blockages":
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

Data © OpenStreetMap contributors, ODbL. Elevation: EU-DEM via OpenTopoData.
"""
import json, math, os, sys, time, urllib.parse, urllib.request

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
    return pts, nodes, names


def chain_nodes(cfg, ways, P):
    """chain() for a route file that lists its nodes: each step runs along a route way joining the two nodes."""
    where = {}  # node -> [(way, index)]
    for w in ways.values():
        for j, n in enumerate(w['nodes']):
            where.setdefault(n, []).append((w, j))
    seq = cfg['nodes']
    pts, nodes, names = [], [], []
    for k, n in enumerate(seq):
        m = seq[(k + 1) % len(seq)]
        hit = next(((w, j) for w, j in where[n] if (j + 1 < len(w['nodes']) and w['nodes'][j + 1] == m)
                    or (j > 0 and w['nodes'][j - 1] == m)), None)
        assert hit, f'nodes {n} and {m} are not neighbours on any route way'
        w, j = hit
        pts.append(P(w['geometry'][j]))
        nodes.append(n)
        names.append(w['tags'].get('name'))
    return pts, nodes, names


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


def elevation(cfg, pts, refetch):
    """Centreline heights (every 20 m) and the terrain grid round the route from OpenTopoData, cached."""
    path = os.path.join(CACHE, cfg['key'] + '_elevation.json')
    # (the profile runs from the start node, so a moved start line or changed route needs a new one)
    stale = os.path.exists(path) and json.load(open(path)).get('route', [cfg['start'], cfg['ways']]) != [cfg['start'], cfg['ways']]
    if refetch or stale or not os.path.exists(path):
        P = bt.proj_for(cfg['key'])
        rs, _, total = bt.resample(pts, [None] * len(pts), 20.0)
        step, margin = cfg['grid'], cfg['margin']
        if cfg.get('local'):
            line, (x0, y0, nx, ny, grid) = local_elevation(cfg, P, rs, step, margin)
        else:
            line = fe.query([P.inv(x, y) for x, y in rs], cfg['dem'])
            xs, ys = [p[0] for p in rs], [p[1] for p in rs]
            x0, y0 = min(xs) - margin, min(ys) - margin
            nx = int((max(xs) + margin - x0) / step) + 1
            ny = int((max(ys) + margin - y0) / step) + 1
            print(f'  terrain grid {nx} x {ny}', flush=True)
            grid = fe.query([P.inv(x0 + i * step, y0 + j * step) for j in range(ny) for i in range(nx)], cfg['dem'])
        os.makedirs(CACHE, exist_ok=True)
        json.dump({'route': [cfg['start'], cfg['ways']], 'line_step': total / len(rs), 'line': [round(h, 2) for h in line],
                   'grid': {'x0': x0, 'y0': y0, 'step': step, 'nx': nx, 'ny': ny, 'h': [round(h, 1) for h in grid]}},
                  open(path, 'w'))
    return json.load(open(path))


def centreline(cfg, data, P):
    """The driven line: the chained OSM ways from the start line, junctions filleted, smoothed and resampled
    to STEP. Returns (points, street name per point, s of each route node on the line)."""
    raw, nodes, names = chain(cfg, data, P)
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
    for p in pts:  # street name per sample, from the nearest raw OSM point
        i = min(range(len(raw)), key=lambda j: (raw[j][0] - p[0]) ** 2 + (raw[j][1] - p[1]) ** 2)
        name_at.append(names[i])
    return pts, name_at, node_s, total, raw


def blockages(cfg, osm, route, node_s, pts, half):
    """A barrier across each side road (OSM highway way sharing a node with the route), where it is clear of
    the stage's run-off: [x, y, angle, width]."""
    route_ways = {e['id'] for e in route['elements'] if e['type'] == 'way'}
    route_nodes = set(node_s)
    P = bt.proj_for(cfg['key'])
    clear = half + cfg['trackdef'].get('runoff', 1.8) + 2.0
    out = []
    for el in osm['elements']:
        tags = el.get('tags', {})
        if el['type'] != 'way' or el['id'] in route_ways or tags.get('highway') not in cfg['blockage_types']:
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
            for arm in (xy[k::-1], xy[k:]):  # the side road either way from the junction
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
    sectors, last = [], None
    for i, nm in enumerate(names):
        if nm and nm != last:
            sectors.append([i, nm])
            last = nm
    track = {'step': step, 'length': total, 'pts': [v for p in pts for v in (round(p[0], 2), round(p[1], 2))],
             'names': sectors, 'elev': [round(h, 2) for h in elev], 'grid': ev['grid']}
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
    if refetch or not os.path.exists(env_src):
        print('  fetching surroundings', fs.bbox(key), flush=True)
        os.makedirs(fs.OUT_DIR, exist_ok=True)
        json.dump(fs.fetch(key), open(env_src, 'w'), separators=(',', ':'))
    bs.build(key)
    osm = json.load(open(env_src))
    half = cfg['trackdef'].get('width', 6.5) / 2
    blocks = blockages(cfg, osm, route, node_s, pts, half)
    env_path = os.path.join(GODOT_TRACKS, key + '_env.json')
    env = json.load(open(env_path))
    env['road_blockages'] = [b[:4] for b in blocks]
    if cfg['trackdef'].get('street_stage'):
        env['stands'] = []  # no grandstands on a public road (OSM has none here anyway)
    json.dump(env, open(env_path, 'w'), separators=(',', ':'))
    fh.build(key, ev)  # the distant land (its height and cover tiles are cached in tools/.tiles/)
    fl.build(key)
    print(f'  {len(blocks)} road blockages: ' + ', '.join(sorted({b[5] or str(b[4]) for b in blocks})))
    if check:
        check_image(key, pts, osm, blocks, corners, node_s, check)


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
    for k in keys:
        build(k, refetch, check if len(keys) == 1 else (check and check.replace('.png', f'_{k}.png')))
