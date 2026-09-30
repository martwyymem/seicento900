"""Builds js/tracks.js and godot/data/tracks/<key>.json from OpenStreetMap data.

Data © OpenStreetMap contributors, ODbL. Fetched via Overpass:
  Nürburgring   way["highway"="raceway"](50.31,6.90,50.39,7.02); out tags geom;   -> osm_raceways.json
  Monaco        rel(148194); out geom;      (Circuit de Monaco)                    -> osm_monaco.json
                (rel(148194);rel(2126739);); way(r); out tags;                     -> osm_relation_tags.json
  Le Mans       rel(2126739); out geom;     (Circuit des 24 Heures du Mans)        -> osm_lemans.json
                way["highway"="raceway"](47.940,0.195,47.965,0.225); out tags geom; -> osm_lemans_pits.json
  Indianapolis  way["highway"="raceway"](39.785,-86.245,39.805,-86.225); out tags geom; -> osm_indy.json
Suzuka and Zandvoort come from the main API (relation/<id>/full, plus Zandvoort's pit lane way 38144527),
converted to the same relation-with-geometry layout, with the member ways' tags stored alongside:
  Suzuka        relation 284570   (鈴鹿サーキット)                                -> osm_suzuka.json
  Zandvoort     relation 13545573 (Grand Prix Formule 1 van Nederland)             -> osm_zandvoort.json
Fiat Track (Tor Fiata, the Fiat Auto Poland test circuit in Tychy) is one closed service way in the main API's
map call (way 143622821, traced from the GUGiK orthophoto, inside the 'Motodrom' landuse way 143653966):
  Fiat Track    api/0.6/map?bbox=19.055,50.090,19.090,50.106, way 143622821        -> osm_fiat.json
"""
import json, math, os

HERE = os.path.dirname(__file__)

GP = [1149161210, 1149161208, 1443047846, 1443047847, 1079809244, 820679447, 820679448,
      820679446, 1113009623, 820679445, 820330155, 820330154, 1113009624, 820330153,
      820330152, 1079809245, 1443047845, 1443047844, 27852990, 820679450]

NORD = [41395670, 41395673, 1009142894, 1009142895, 799394496, 799394497, 41395681, 41395684,
        799394498, 799394499, 799394500, 799394501, 799394502, 799394503, 799394504, 799394505,
        799394506, 799394507, 683061813, 683061814, 41395647, 683006908, 245166664, 799394508,
        799394509, 683061804, 799394510, 799394511, 799394512, 799394513, 414785755, 414785756,
        799394515, 799394514, 799394516, 799394517, 799394518, 799394519, 799394520, 799394521,
        799394522, 799394523, 799394524, 41395652, 683303211, 683303210, 683303209, 683303208,
        41792406, 799394494, 799394495, 41395668]

# Indianapolis oval, from the start/finish line, counter-clockwise
INDY = [588780349, 51308226, 588780333, 588780334, 588780335, 588780332, 588780343, 588780345,
        588780347, 588780351]

# key: source file, chain (explicit way ids, or 'relation' to chain the relation's members by their
# endpoints), projection origin, start line (lat, lon) for new tracks, pit-lane ways (for hints) and
# the OpenTopoData dataset used for elevation. Optional: 'oneway' orients the loop along the relation's
# oneway=yes ways (for layouts whose winding says nothing, like Suzuka's figure of eight), 'name_tag'
# picks the OSM name tag for the section names, 'bridges' parts the two roads where the loop crosses
# itself, and 'godot' keeps a track out of the JS reference's tracks.js (and puts its start exactly on
# the given point rather than the nearest OSM node).
TRACKS = {
    'gp': dict(src='osm_raceways.json', ids=GP, origin=(50.35, 6.96), dem='eudem25m', grid=30),
    'nordschleife': dict(src='osm_raceways.json', ids=NORD, origin=(50.35, 6.96), dem='eudem25m', grid=75),
    'monaco': dict(src='osm_monaco.json', ids='relation', origin=(43.7367, 7.4258), start=(43.7350269, 7.4212652),
                   pits=('osm_monaco.json', [850261588]), dem='eudem25m', grid=25, length=3337, tunnels=True, reverse=True,
                   skip=[1551240830, 1551240829],  # two stub ways that zig-zag at the top of Beau Rivage
                   # the 25 m DEM sees buildings and the cliff above the tunnel, so the road uses the circuit's
                   # published profile instead (distance from the line in m, height above sea level in m)
                   profile=[(0, 7), (200, 8), (400, 20), (600, 33), (760, 40), (900, 42), (1050, 38), (1150, 33),
                            (1250, 27), (1350, 20), (1430, 11), (1550, 9), (1900, 8), (2100, 3), (2350, 2),
                            (2700, 2), (2900, 3), (3050, 5), (3337, 7)]),
    'lemans': dict(src='osm_lemans.json', ids='relation', origin=(47.9376, 0.2257), start=(47.95075, 0.20766),
                   pits=('osm_lemans_pits.json', [257067964, 354149765, 777192900, 777192901, 257063576]),
                   dem='eudem25m', grid=75, length=13626),
    'indy': dict(src='osm_indy.json', ids=INDY, origin=(39.7950, -86.2346), start=(39.7931571, -86.2388466),
                 pits=('osm_indy.json', [588780266, 1176980820, 588780264, 588780328]),
                 dem='ned10m', grid=30, length=4023,
                 # the mapped oval has wobbly corners: rebuild it from the published layout (5/8 mi straights,
                 # 1/8 mi short chutes, four 1/4 mi turns measured near the inside wall; the centreline turns
                 # sit ~7.5 m further out, so 402 m + 7.5 * pi / 2) and fit that onto the OSM loop
                 oval=dict(straight=1006, chute=201, turn=414, ease=30)),
    'monza': dict(src='osm_monza.json', ids='relation', origin=(45.6216, 9.2888), start=(45.61896, 9.28112),
                  pits=('osm_monza.json', [38168747]), dem='eudem25m', grid=45, length=5793, cw=True),
    'silverstone': dict(src='osm_silverstone.json', ids='relation', origin=(52.0712, -1.0168), start=(52.0693, -1.0218),
                        pits=('osm_silverstone.json', [227902927]), dem='eudem25m', grid=40, length=5891, cw=True),
    'spa': dict(src='osm_spa.json', ids='relation', origin=(50.4370, 5.9686), start=(50.4427568, 5.9666915),
                pits=('osm_spa.json', [323851541]), dem='eudem25m', grid=60, length=7004, cw=True),
    # no start node in the relation: the control line faces the middle of the pit building
    'suzuka': dict(src='osm_suzuka.json', ids='relation', origin=(34.8431, 136.5367), start=(34.843871, 136.539761),
                   pits=('osm_suzuka.json', [120917578]), dem='aster30m', grid=30, length=5807, oneway=True,
                   name_tag='name:en', rename={'Hitachi Automotive Systems Chicane': 'Hitachi Astemo Chicane'},
                   bridges=dict(deck=120, clearance=7.5, ramp=150), godot=True),
    # the finish line (the relation also has a start node 60 m further on)
    'zandvoort': dict(src='osm_zandvoort.json', ids='relation', origin=(52.3880, 4.5440), start=(52.3889948, 4.5408762),
                      pits=('osm_zandvoort.json', [38144527]), dem='eudem25m', grid=30, length=4259, oneway=True,
                      rename={'CM.com Circuit Zandvoort': None}, godot=True),
    # OSM has no start line or pit lane here: the line is on the north straight, at the junction with the
    # infield roads (where the paddock buildings are); the loop keeps the direction it is drawn in
    'fiat': dict(src='osm_fiat.json', ids=[143622821], origin=(50.0975, 19.0720), start=(50.0972148, 19.0704380),
                 dem='eudem25m', grid=30, godot=True),
}

_cache = {}

def load(src):
    if src not in _cache:
        data = json.load(open(os.path.join(HERE, src)))
        ways = {}
        for e in data['elements']:
            if e['type'] == 'way':
                ways[e['id']] = e
            elif e['type'] == 'relation':
                ways['relation'] = e
                for m in e['members']:
                    if m['type'] == 'way':
                        ways.setdefault(m['ref'], {'id': m['ref'], 'geometry': m['geometry'], 'role': m['role'], 'tags': {}})
        # relation members come without tags; they were fetched separately: (rel(148194);rel(2126739);); way(r); out tags;
        if 'relation' in ways:
            for e in json.load(open(os.path.join(HERE, 'osm_relation_tags.json')))['elements']:
                if e['id'] in ways:
                    ways[e['id']]['tags'] = e.get('tags', {})
        _cache[src] = ways
    return _cache[src]

class Proj:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320 * math.cos(math.radians(lat0))
        self.ky = 110540

    def __call__(self, p):
        return ((p['lon'] - self.lon0) * self.kx, -(p['lat'] - self.lat0) * self.ky)  # x east, y south (screen)

    def inv(self, x, y):
        return (self.lat0 - y / self.ky, self.lon0 + x / self.kx)

def proj_for(key):
    return Proj(*TRACKS[key]['origin'])

def relation_chain(ways, P, skip=()):
    """Orders a circuit relation's (unordered, possibly reversed) member ways into one closed loop.
    Small mapping gaps (< 45 m) are bridged; at a fork the way drawn in the direction of travel wins."""
    rel = ways['relation']
    pool = [ways[m['ref']] for m in rel['members'] if m['type'] == 'way' and m['role'] != 'pit_lane'
            and ways[m['ref']]['tags'].get('name') != 'Sortie des stands' and m['ref'] not in skip]
    head = lambda w: P(w['geometry'][0])
    tail = lambda w: P(w['geometry'][-1])
    order = [(pool[0], False)]
    used = {pool[0]['id']}
    start, end = head(pool[0]), tail(pool[0])
    while math.dist(end, start) > 3 or len(order) < 3:
        best = None
        for w in pool:
            if w['id'] in used:
                continue
            for flip, q in ((False, head(w)), (True, tail(w))):
                gap = math.dist(q, end) + (0.5 if flip else 0)
                if best is None or gap < best[0]:
                    best = (gap, w, flip)
        if best is None or best[0] > 45:
            if math.dist(end, start) < 45:
                break
            raise AssertionError(f'relation chain did not close ({len(order)} of {len(pool)} ways)')
        _, w, flip = best
        order.append((w, flip))
        used.add(w['id'])
        end = head(w) if flip else tail(w)
    return order

def chain(key):
    t = TRACKS[key]
    ways = load(t['src'])
    P = proj_for(key)
    if t['ids'] == 'relation':
        seq = relation_chain(ways, P, t.get('skip', ()))
    else:
        seq = [(ways[i], False) for i in t['ids']]
    pts, names, tunnel, bridge = [], [], [], []
    forward = backward = 0.0  # length of oneway=yes ways run with / against their drawn direction
    for w, flip in seq:
        g = w['geometry'][::-1] if flip else w['geometry']
        if pts:
            gap = math.dist(P(g[0]), pts[-1])
            assert gap < 45.0, f'gap {gap:.1f} m before way {w["id"]}'
            if gap < 3.0:
                g = g[1:]
        if w.get('tags', {}).get('oneway') == 'yes':
            run = sum(math.dist(P(a), P(b)) for a, b in zip(w['geometry'], w['geometry'][1:]))
            if flip:
                backward += run
            else:
                forward += run
        tags = w.get('tags', {})
        name = tags.get(t.get('name_tag', 'name')) or tags.get('name')
        name = t.get('rename', {}).get(name, name)
        for p in g:
            pts.append(P(p)); names.append(name); tunnel.append(tags.get('tunnel') == 'yes')
            bridge.append(tags.get('bridge') == 'yes')
    assert math.dist(pts[0], pts[-1]) < 45.0, 'loop not closed'
    if math.dist(pts[0], pts[-1]) < 3.0:
        pts, names, tunnel, bridge = pts[:-1], names[:-1], tunnel[:-1], bridge[:-1]
    if not TRACKS[key].get('tunnels'):
        tunnel = [False] * len(pts)
    if t.get('oneway'):  # oneway ways are drawn in the direction of the race
        assert forward + backward > 0, 'no oneway ways to orient the loop'
        if backward > forward:
            pts, names, tunnel, bridge = pts[::-1], names[::-1], tunnel[::-1], bridge[::-1]
    return pts, names, tunnel, bridge

def resample(pts, names, step):
    n = len(pts)
    seg = [math.dist(pts[i], pts[(i + 1) % n]) for i in range(n)]
    total = sum(seg)
    count = round(total / step)
    step = total / count
    out, onames = [], []
    i, acc = 0, 0.0
    for k in range(count):
        s = k * step
        while acc + seg[i] < s:
            acc += seg[i]; i += 1
        t = (s - acc) / seg[i] if seg[i] else 0
        a, b = pts[i], pts[(i + 1) % n]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        onames.append(names[i])
    return out, onames, total

def smooth(pts, passes):
    n = len(pts)
    for _ in range(passes):
        pts = [((pts[i-1][0] + 2*pts[i][0] + pts[(i+1) % n][0]) / 4,
                (pts[i-1][1] + 2*pts[i][1] + pts[(i+1) % n][1]) / 4) for i in range(n)]
    return pts

def smooth_loop(vals, sigma_samples):
    # repeated circular box blur ~ gaussian
    n = len(vals)
    r = max(1, int(sigma_samples))
    for _ in range(3):
        acc = sum(vals[i % n] for i in range(-r, r + 1))
        out = []
        for i in range(n):
            out.append(acc / (2 * r + 1))
            acc += vals[(i + r + 1) % n] - vals[(i - r) % n]
        vals = out
    return vals

def nearest_index(pts, q):
    return min(range(len(pts)), key=lambda i: (pts[i][0] - q[0]) ** 2 + (pts[i][1] - q[1]) ** 2)

def rotate(seq, k):
    return seq[k:] + seq[:k]

def ideal_oval(pts, straight, chute, turn, ease, ds=0.25):
    """Four identical turns joined by straights, with eased curvature at each end of a turn, placed over the
    mapped loop `pts` (same direction of travel, best-fitting rotation and position)."""
    pts = resample(pts, [None] * len(pts), 4.0)[0]  # even spacing, so the sparse straights weigh as much as the corners
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    sign = 1 if area > 0 else -1  # y points south: a positive area turns clockwise on the map
    kmax = (math.pi / 2) / (turn - ease)  # each smoothstep ease covers half its length's worth of turning
    def ramp(u):
        return u * u * (3 - 2 * u)
    def k_turn(u):
        return sign * kmax * ramp(min(1, u / ease, (turn - u) / ease))
    segs = [(straight, None), (turn, k_turn), (chute, None), (turn, k_turn)] * 2
    loop, x, y, a = [], 0.0, 0.0, 0.0
    for length, kf in segs:
        for q in range(round(length / ds)):
            u = (q + 0.5) * ds
            if kf:
                a += kf(u) * ds
            x += math.cos(a) * ds
            y += math.sin(a) * ds
            if q % 8 == 0:
                loop.append((x, y))
    cx = sum(p[0] for p in loop) / len(loop)
    cy = sum(p[1] for p in loop) / len(loop)
    mx = sum(p[0] for p in pts) / len(pts)
    my = sum(p[1] for p in pts) / len(pts)
    # principal axis of the mapped loop -> first guess for the rotation, then refine by mean distance
    sxx = sum((p[0] - mx) ** 2 for p in pts)
    syy = sum((p[1] - my) ** 2 for p in pts)
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts)
    axis = 0.5 * math.atan2(2 * sxy, sxx - syy)
    def place(rot, dx=0.0, dy=0.0):
        c, s = math.cos(rot), math.sin(rot)
        return [(mx + dx + (p[0] - cx) * c - (p[1] - cy) * s, my + dy + (p[0] - cx) * s + (p[1] - cy) * c) for p in loop]
    probe = pts[::6]
    def cost(cand):
        return sum(min((q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2 for p in cand[::4]) for q in probe)
    best = None
    for base in (axis, axis + math.pi / 2, axis + math.pi, axis - math.pi / 2):
        for dr in [i * 0.002 for i in range(-10, 11)]:
            c = cost(place(base + dr))
            if best is None or c < best[0]:
                best = (c, base + dr)
    rot = best[1]
    dx = dy = 0.0
    for h in (4, 2, 1, 0.5):  # nudge the position too
        moved = True
        while moved:
            moved = False
            for ddx, ddy in ((h, 0), (-h, 0), (0, h), (0, -h)):
                c = cost(place(rot, dx + ddx, dy + ddy))
                if c < best[0]:
                    best, dx, dy, moved = (c, rot), dx + ddx, dy + ddy, True
    return place(rot, dx, dy)

def centreline(key):
    """Chain, resample and (for the new tracks) rotate so index 0 is on the start line.
    Returns the points with per-point section names and OSM tunnel / bridge flags."""
    t = TRACKS[key]
    pts, names, tunnel, bridge = chain(key)
    if 'oval' in t:
        pts = ideal_oval(pts, **t['oval'])
        names, tunnel, bridge = [None] * len(pts), [False] * len(pts), [False] * len(pts)
    if t.get('reverse'):  # the relation's ways run against the direction of the race
        pts, names, tunnel, bridge = pts[::-1], names[::-1], tunnel[::-1], bridge[::-1]
    if 'cw' in t:  # OSM way directions are arbitrary: make the loop run the way the real race does
        area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
        if (area > 0) != t['cw']:  # y points south, so a positive area is clockwise on the map
            pts, names, tunnel, bridge = pts[::-1], names[::-1], tunnel[::-1], bridge[::-1]
    if 'start' in t:
        q = proj_for(key)({'lat': t['start'][0], 'lon': t['start'][1]})
        k = nearest_index(pts, q)
        # no OSM node on the line: split the segment it crosses (the JS tracks keep the nearest node, for parity)
        if t.get('godot') and math.dist(pts[k], q) > 1.0:
            best = None
            for i in range(len(pts)):
                a, b = pts[i], pts[(i + 1) % len(pts)]
                L2 = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2 or 1
                f = max(0.0, min(1.0, ((q[0] - a[0]) * (b[0] - a[0]) + (q[1] - a[1]) * (b[1] - a[1])) / L2))
                c = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
                if best is None or math.dist(c, q) < best[0]:
                    best = (math.dist(c, q), i, c)
            _, i, c = best
            pts.insert(i + 1, c); names.insert(i + 1, names[i]); tunnel.insert(i + 1, tunnel[i]); bridge.insert(i + 1, bridge[i])
            k = i + 1
        pts, names, tunnel, bridge = rotate(pts, k), rotate(names, k), rotate(tunnel, k), rotate(bridge, k)
    return pts, names, tunnel, bridge

def pit_hints(key, pts, step):
    """Where the real pit lane leaves/rejoins the track, relative to the start line, and on which side."""
    t = TRACKS[key]
    if 'pits' not in t:
        return None
    src, ids = t['pits']
    ways = load(src)
    P = proj_for(key)
    lane = [P(p) for wid in ids for p in ways[wid]['geometry']]
    n = len(pts)
    out = []
    for q in lane:
        i = nearest_index(pts, q)
        a, b = pts[i], pts[(i + 1) % n]
        tx, ty = b[0] - a[0], b[1] - a[1]
        l = math.hypot(tx, ty) or 1
        d = ((q[0] - a[0]) * -ty + (q[1] - a[1]) * tx) / l  # + = right of travel
        s = i * step
        if s > n * step / 2:
            s -= n * step
        out.append((round(s), round(d, 1)))
    return out

def crossings(pts, bridge, step):
    """(upper, lower) sample pairs where the loop passes over itself under a bridge=yes stretch."""
    n = len(pts)
    runs, i = [], 0
    while i < n:
        if bridge[i]:
            j = i
            while j + 1 < n and bridge[j + 1]:
                j += 1
            runs.append((i, j))
            i = j + 1
        else:
            i += 1
    far = int(200 / step)  # ignore the bridge's own approaches
    pad = int(60 / step)  # flags label OSM segments by one end, so look a little either side
    out = []
    for a, b in runs:
        best = None
        for i in (k % n for k in range(a - pad, b + pad + 1)):
            for j in range(n):
                if min(abs(i - j), n - abs(i - j)) < far:
                    continue
                d = math.dist(pts[i], pts[j])
                if best is None or d < best[0]:
                    best = (d, i, j)
        d, up, low = best
        assert d < 10, f'no road passes under the bridge at sample {a} ({d:.0f} m away)'
        out.append((up, low))
    return out

def level_decks(elev, pairs, step, deck=0, **_):
    """The DEM sees the valley under a bridge on the upper road too: carry the deck on a straight grade
    across +-`deck` m, as the tunnels are."""
    n = len(elev)
    span = int(deck / step)
    for up, _ in pairs:
        h0, h1 = elev[(up - span) % n], elev[(up + span) % n]
        for k in range(-span, span + 1):
            elev[(up + k) % n] = h0 + (h1 - h0) * (k + span) / (2 * span)

def cut_underpasses(elev, pairs, step, clearance=0, ramp=0, **_):
    """Lower the road under each bridge until the deck clears it by `clearance` m, eased in over `ramp` m."""
    n = len(elev)
    span = int(ramp / step)
    for up, low in pairs:
        need = clearance - (elev[up] - elev[low])
        if need > 0:
            for k in range(-span, span + 1):
                elev[(low + k) % n] -= need * (0.5 + 0.5 * math.cos(math.pi * k / span))
        print(f'  bridge at {up * step:.0f} m over {low * step:.0f} m: {elev[up] - elev[low]:.1f} m clearance'
              + (f' (underpass cut {need:.1f} m)' if need > 0 else ''))

def build(key, step=2.0):
    t = TRACKS[key]
    pts, names, tunnel, bridge = centreline(key)
    # resample the tunnel / bridge flags alongside the names
    tn = [('\x01' if f else '') + ('\x02' if b else '') + (nm or '') for nm, f, b in zip(names, tunnel, bridge)]
    pts, tn, _ = resample(pts, tn, 4.0)
    pts = smooth(pts, 3)  # take the corners off OSM polyline vertices
    pts, tn, total = resample(pts, tn, step)
    tunnel = [x.startswith('\x01') for x in tn]
    bridge = ['\x02' in x for x in tn]
    names = [x.lstrip('\x01\x02') or None for x in tn]
    # run-length encode sector names: [[startIndex, name], ...]
    sectors, last = [], object()
    for i, nm in enumerate(names):
        if nm != last and nm:
            sectors.append([i, nm]); last = nm
    tunnels = []
    for i, f in enumerate(tunnel):
        if f and (i == 0 or not tunnel[i - 1]):
            tunnels.append([i, i])
        if f:
            tunnels[-1][1] = i
    out = {}
    elev_path = os.path.join(HERE, 'elevation.json')
    ev = json.load(open(elev_path)).get(key) if os.path.exists(elev_path) else None
    if ev:
        line = ev['line']
        m = len(line)
        # centreline elevation by fractional distance, then smoothed (~60 m) to remove DEM canopy noise
        elev = []
        for i in range(len(pts)):
            u = i / len(pts) * m
            k = int(u) % m
            f = u - int(u)
            elev.append(line[k] * (1 - f) + line[(k + 1) % m] * f)
        # the DEM sees the hillside/buildings above a tunnel: bridge it with a straight grade
        for a, b in tunnels:
            a0, b0 = max(0, a - 8), min(len(elev) - 1, b + 8)
            for i in range(a0, b0 + 1):
                elev[i] = elev[a0] + (elev[b0] - elev[a0]) * (i - a0) / max(1, b0 - a0)
        if 'profile' in t:
            prof = t['profile']
            scale = prof[-1][0] / total
            elev = []
            for i in range(len(pts)):
                u = i * (total / len(pts)) * scale
                k = max(j for j in range(len(prof) - 1) if prof[j][0] <= u)
                (a, ha), (b, hb) = prof[k], prof[k + 1]
                elev.append(ha + (hb - ha) * (u - a) / (b - a))
        pairs = crossings(pts, bridge, total / len(pts)) if 'bridges' in t else []
        level_decks(elev, pairs, total / len(pts), **t.get('bridges', {}))
        elev = smooth_loop(elev, 30 / (total / len(pts)))
        cut_underpasses(elev, pairs, total / len(pts), **t.get('bridges', {}))
        out['elev'] = [round(h, 2) for h in elev]
        out['grid'] = ev['grid']
    if tunnels:
        out['tunnels'] = tunnels
    hints = pit_hints(key, pts, total / len(pts))
    if hints:
        print(f'  {key} pit lane (s, d): {hints[0]} ... {hints[len(hints) // 2]} ... {hints[-1]}')
    return {**out, 'step': total / len(pts), 'length': total,
            'pts': [v for p in pts for v in (round(p[0], 2), round(p[1], 2))],
            'names': sectors}

if __name__ == '__main__':
    out = {}
    for key in TRACKS:
        out[key] = build(key)
        print(f"{key}: {out[key]['length']:.0f} m"
              + (f" (official {TRACKS[key]['length']} m)" if 'length' in TRACKS[key] else '')
              + (f", {len(out[key].get('tunnels', []))} tunnel(s)" if out[key].get('tunnels') else '')
              + (', no elevation yet' if 'elev' not in out[key] else ''))
    with open(os.path.join(HERE, '..', 'js', 'tracks.js'), 'w') as f:
        f.write('// Generated by tools/build_tracks.py — geometry © OpenStreetMap contributors (ODbL)\n')
        f.write('window.TRACK_DATA = ')
        json.dump({k: v for k, v in out.items() if not TRACKS[k].get('godot')}, f, separators=(',', ':'))
        f.write(';\n')
    # Godot port: one JSON file per track
    gdir = os.path.join(HERE, '..', 'godot', 'data', 'tracks')
    os.makedirs(gdir, exist_ok=True)
    for key, data in out.items():
        with open(os.path.join(gdir, key + '.json'), 'w') as f:
            json.dump(data, f, separators=(',', ':'))
