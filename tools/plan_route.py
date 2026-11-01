"""Plans a route on the Brzeszcze open world's road graph and writes tools/street_routes/<key>.json, which
build_street_tracks.py then bakes from the open world's own caches (nothing is downloaded):

    cd tools && python3 plan_route.py <key> && python3 build_street_tracks.py <key> --check /tmp/<key>.png

Two kinds of route (ROUTES below):

- a loop ("waypoints"): routed through the waypoints in order and back to the first, never reusing a junction
  (the Goliath, the S1 Sprint);
- a rally stage ("stage"): point to point through the stage waypoints, then `runoff` metres straight on past the
  finish, then back to the start through the "return" waypoints on other roads, so that it still bakes as a loop.
  ("runoff_to": a waypoint the run-off heads for instead). The start line goes in the middle of the run-off and the route file gets "stage": {"start": node, "finish": node};
  the baker turns those into the track's "stage": [from, to] (m from the start line).

A waypoint is [x, y] (m east / south of the open world's origin) with optionally the highway classes to snap to
("motorway|tertiary", default MAJOR) and a heading (degrees, 0 = east, 90 = south). A route may weight the roads by
surface ("prefer": {"paved"|"gravel"|"dirt": cost factor}; gravel and dirt as the open world tells them apart, from
build_open_world.UNPAVED and LOOSE_GRAVEL). Also draws /tmp/<key>_route.png over /tmp/<key>_roads.png when present.
"""
import json, sys, heapq, math, os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_open_world as bw  # noqa: E402
from build_street_tracks import surface_of  # noqa: E402  ('paved' / 'gravel' / 'dirt', as the open world drives a road)

# cost per metre by highway class (lower is preferred); track and living_street are the open world's unpaved
# lanes and home zones, dear so that a tarmac route only takes them when told to
COST = {'motorway': 0.45, 'motorway_link': 0.8, 'trunk': 0.6, 'primary': 0.65, 'secondary': 0.7, 'tertiary': 0.9,
        'secondary_link': 1.2, 'tertiary_link': 1.2, 'unclassified': 1.8, 'residential': 3.0, 'living_street': 3.5,
        'track': 4.0}
MAJOR = {'secondary', 'tertiary', 'primary', 'trunk'}
U = 'track|unclassified|residential|living_street|service'  # snap a waypoint to a minor road
BLOCKAGE_TYPES = ['primary', 'secondary', 'tertiary', 'unclassified', 'residential', 'living_street', 'service', 'track',
                  'primary_link', 'secondary_link', 'tertiary_link', 'motorway_link']
SKIP_SERVICE = ['driveway', 'parking_aisle', 'drive-through']

# the TrackDef of a forest rally stage (Mały Bór's), for the point-to-point stages
RALLY_TRACKDEF = {'display_name': '', 'short_name': '', 'width': 6.5, 'theme': 'forest', 'street_stage': True,
                  'point_to_point': True, 'barrier': 'guardrail', 'runoff': 1.8, 'runoff_surface': 'grass', 'runoff_paved': 0.0,
                  'kerb_style': 'none', 'kerb_width': 0.0, 'tree_density': 0.9, 'tree_patch': 0.75, 'tree_conifer': 0.8,
                  'grandstands': False, 'stand_tiers': 0, 'floodlight_spacing': 0.0, 'pit_entry': -120.0, 'pit_exit': 120.0,
                  'pit_ramp': 40.0, 'pit_offset': 8.0, 'box_start': -60.0, 'box_spacing': 9.0}

ROUTES = {
    'goliath': {
        'comment': 'The Goliath: one long lap round the whole Brzeszcze open world (the final race), planned on the open '
                   'world\'s road graph by waypoints and baked from its own caches ("local"). See tools/build_street_tracks.py.',
        # the Goliath was planned before track and living_street were routable; it keeps its own table
        'cost': {k: v for k, v in COST.items() if k not in ('track', 'living_street')},
        'waypoints': [[-520, 2600], [-2400, -400, "motorway", -125], [-3200, -2500], [-1150, -3400],
                      [0, -3400, "unclassified|tertiary|residential"], [900, -2300], [850, -1650], [2050, -1250],
                      [3150, -1500], [3200, 0], [3600, 1700], [3300, 3150], [1500, 3300]],
        'start_before': 150, 'corner_radius': 18.0,
        'trackdef': {'display_name': 'The Seicento Goliath', 'short_name': 'Goliath', 'width': 8.0, 'theme': 'country',
                     'street_stage': True, 'barrier': 'armco', 'runoff': 2.0, 'runoff_surface': 'grass', 'runoff_paved': 0.0,
                     'kerb_style': 'none', 'kerb_width': 0.0, 'tree_density': 0.4, 'tree_patch': 0.6, 'tree_conifer': 0.4,
                     'grandstands': False, 'stand_tiers': 0, 'floodlight_spacing': 0.0, 'pit_entry': -120.0, 'pit_exit': 170.0,
                     'pit_ramp': 50.0, 'pit_offset': 9.0, 'box_start': -65.0, 'box_spacing': 9.0}},
    's1_sprint': {
        'comment': 'The S1 Sprint: both carriageways of the S1 expressway between the Wola junction (DW933 Pszczyńska) and '
                   'the Brzeszcze junction, closed by the ramps and the bridges between the junctions\' roundabouts. '
                   'Planned by tools/plan_route.py on the open world\'s road graph, baked from its caches ("local").',
        # south-east on the Brzeszcze-bound carriageway, off at Brzeszcze, back north-west, off at Wola
        'waypoints': [[-3000, -1060, "motorway", 51], [-1600, 900, "motorway", 70], [-1450, 1300, "motorway", -105],
                      [-2300, -100, "motorway", -129], [-3500, -1700, "motorway", -129]],
        # the carriageways run 12-16 m apart: the Goliath's 8 m road and 2 m run-off keep their barriers in the median
        'start_at': [-2700, -680, "motorway", 51], 'start_before': 0, 'corner_radius': 25.0,
        'blockage_types': BLOCKAGE_TYPES + ['motorway', 'trunk'],
        'surface': 'paved',
        'trackdef': {'display_name': 'S1 Sprint', 'short_name': 'S1', 'width': 8.0, 'theme': 'country',
                     'street_stage': True, 'barrier': 'armco', 'runoff': 2.0, 'runoff_surface': 'grass', 'runoff_paved': 0.0,
                     'kerb_style': 'none', 'kerb_width': 0.0, 'tree_density': 0.35, 'tree_patch': 0.6, 'tree_conifer': 0.5,
                     'grandstands': False, 'stand_tiers': 0, 'floodlight_spacing': 0.0, 'pit_entry': -120.0, 'pit_exit': 170.0,
                     'pit_ramp': 50.0, 'pit_offset': 9.0, 'box_start': -65.0, 'box_spacing': 9.0}},
    'maly_bor': {
        'comment': 'Mały Bór: a gravel rally stage through the forest tracks and fishponds between Brzeszcze-Bór and the '
                   'Wisła (ul. Nazieleńce, ul. Kolejowa), point to point; baked as a loop with a run-off past the finish '
                   'and a return leg on other roads. Planned by tools/plan_route.py, baked from the open world\'s caches.',
        # east to west: the gravel track off ul. Bór, ul. Nazieleńce, ul. Kolejowa past the fishponds, the forest
        # tracks down to the Młyńska woods and back north along the Wisła embankment track to ul. Kolejowa
        'stage': [[166, -1607, U], [-474, -1223, U], [-868, -1144, U], [-772, -1433, U], [-1146, -1684, U],
                  [-1223, -1514, U], [-1289, -1433, U], [-1497, -952, U], [-1762, -1065, U], [-1625, -1257, U],
                  [-1712, -1450, U], [-1657, -1618, U], [-1500, -1811, U]],
        # the way back: north past the big pond, ul. Lachowicka down to ul. Bór
        'return': [[-1081, -2713, U], [-277, -2385, U], [-68, -2069, U]],
        'runoff': 300.0, 'prefer': {'paved': 3.0, 'dirt': 1.0, 'gravel': 0.9}, 'corner_radius': 12.0,
        'surface': 'loose',
        'trackdef': {'display_name': 'Mały Bór Rally Stage', 'short_name': 'Mały Bór', 'width': 6.5, 'theme': 'forest',
                     'street_stage': True, 'point_to_point': True, 'barrier': 'guardrail', 'runoff': 1.8,
                     'runoff_surface': 'grass', 'runoff_paved': 0.0, 'kerb_style': 'none', 'kerb_width': 0.0,
                     'tree_density': 0.9, 'tree_patch': 0.75, 'tree_conifer': 0.8, 'grandstands': False, 'stand_tiers': 0,
                     'floodlight_spacing': 0.0, 'pit_entry': -120.0, 'pit_exit': 120.0, 'pit_ramp': 40.0, 'pit_offset': 8.0,
                     'box_start': -60.0, 'box_spacing': 9.0}},
    'brzeszcze': {
        'comment': 'Brzeszcze Kopalnia: a town loop past the mine (the Andrzej shafts) on ul. Ofiar Oświęcimia, Przemysłowa, '
                   'Leśna, Kościuszki, Piastowska, Drobniaka, Daszyńskiego and Przecieszyńska. Replaced the invented 2.8 km '
                   'Brzeszcze circuit (tools/generate_city_tracks.py) in place, under the same key. Planned by '
                   'tools/plan_route.py on the open world\'s road graph, baked from its caches ("local").',
        # north-east up ul. Ofiar Oświęcimia past the shafts, ul. Przemysłowa, west on ul. Leśna, down to ul. Kościuszki,
        # south on ul. Piastowska, east on ul. Drobniaka, north on ul. Daszyńskiego and ul. Przecieszyńska
        'waypoints': [[800, 600, "primary|secondary|tertiary", -45], [1100, 150, U + "|tertiary"], [700, -60, U + "|tertiary"],
                      [330, 300, U + "|tertiary"], [-130, 800, U + "|tertiary"], [-190, 1140, U + "|tertiary"],
                      [-170, 1600, U + "|tertiary"], [-100, 2000, U + "|tertiary"], [300, 2000, U + "|tertiary"],
                      [520, 1750, U + "|tertiary"], [450, 1350, U + "|tertiary"]],
        'start_before': 0, 'corner_radius': 12.0,
        'surface': 'paved',
        'trackdef': {'display_name': 'Brzeszcze Kopalnia', 'short_name': 'Brzeszcze', 'width': 7.0, 'theme': 'city',
                     'street_stage': True, 'barrier': 'plastic', 'runoff': 1.5, 'runoff_surface': 'asphalt', 'runoff_paved': 1.5,
                     'kerb_style': 'none', 'kerb_width': 0.0, 'tree_density': 0.4, 'tree_patch': 0.6, 'tree_conifer': 0.2,
                     'grandstands': False, 'stand_tiers': 0, 'floodlight_spacing': 0.0, 'pit_entry': -120.0, 'pit_exit': 170.0,
                     'pit_ramp': 50.0, 'pit_offset': 8.4, 'box_start': -65.0, 'box_spacing': 9.0}},
    'kolonia_stawowa': {
        'comment': 'Kolonia Stawowa: a gravel rally stage on the compacted forest tracks between Wola and the Harmęże edge, '
                   'point to point: north-east from ul. Graniczna past ul. Powstańców to ul. Oświęcimska at Most Bronisław, '
                   'a hairpin onto the parallel track back south-west, and the tracks south to ul. Kolejowa. Baked as a loop '
                   'with a run-off past the finish and a return leg (ul. Kolejowa, ul. Graniczna). Planned by '
                   'tools/plan_route.py, baked from the open world\'s caches.',
        'stage': [[-1871, -2245, U], [-1544, -2422, 'track'], [-1300, -2900, 'track'], [-501, -3666, 'track'],
                  [-342, -3597, 'track'], [-450, -3300, 'track'], [-1078, -2711, 'track'], [-1300, -2270, 'track'],
                  [-1111, -2022, 'track'], [-1211, -1840, U]],
        'return': [[-1744, -2022, U]],
        'runoff': 300.0, 'prefer': {'paved': 3.0, 'dirt': 1.0, 'gravel': 0.9}, 'corner_radius': 12.0,
        'surface': 'loose',
        'trackdef': dict(RALLY_TRACKDEF, display_name='Kolonia Stawowa Rally Stage', short_name='Kolonia Stawowa')},
    'babudy_gora': {
        'comment': 'Babudy–Góra: a gravel rally stage on the compacted tracks west of the S1, point to point from Babudy '
                   '(ul. Wojciecha Korfantego), under the S1 and back, south-west to Góra by ul. Kościelna. Baked as a loop '
                   'with a run-off to ul. Pszczyńska and a return leg (Topolowa, Zapadź, Bażantów, Korfantego). Planned by '
                   'tools/plan_route.py, baked from the open world\'s caches.',
        'stage': [[-2317, 67, U], [-1950, 0, 'track'], [-1925, 250, 'track'], [-2150, 550, U], [-2470, 800, 'track'],
                  [-2625, 1100, 'track'], [-2625, 1550, 'track'], [-2658, 1760, 'track']],
        'return': [[-2900, 1300, U], [-2750, 600, U]],
        'runoff': 300.0, 'prefer': {'paved': 3.0, 'dirt': 1.0, 'gravel': 0.9}, 'corner_radius': 12.0,
        'surface': 'loose',
        'trackdef': dict(RALLY_TRACKDEF, display_name='Babudy–Góra Rally Stage', short_name='Babudy–Góra')},
    'rajsko_wilczkowice': {
        'comment': 'Rajsko–Wilczkowice: a dirt rally stage on the forest tracks along the east edge, point to point from '
                   'ul. Przemysłowa in Rajsko south through the woods, round the loop by the Soła and west to Wilczkowice, '
                   'inside the playable area and off ul. Oświęcimska (the Goliath) until the run-off. Baked as a loop with '
                   'the return up ul. Oświęcimska. Planned by tools/plan_route.py, baked from the open world\'s caches.',
        'stage': [[3600, -2160, 'track'], [3771, -2174, 'track'], [3957, -1929, 'track'], [4036, -414, 'track'],
                  [4137, -110, 'track'], [4022, 123, 'track'], [3900, -300, 'track'], [3592, -444, 'track'],
                  [3560, 0, 'track'], [3450, 140, U]],
        'return': [], 'runoff_to': [3300, -150, 'tertiary|secondary'],
        'runoff': 300.0, 'prefer': {'paved': 3.0, 'dirt': 0.9, 'gravel': 1.0}, 'corner_radius': 12.0,
        'surface': 'dirt',
        'trackdef': dict(RALLY_TRACKDEF, display_name='Rajsko–Wilczkowice Rally Stage', short_name='Rajsko–Wilczkowice')},
    'lipowiec_kobylec': {
        'comment': 'Lipowiec–Kobylec: a gravel rally stage on the gravel track along the south edge east of Lipowiec, then '
                   'north across ul. Łęcka to the forest track beyond, point to point, inside the playable area (it starts '
                   'past the track\'s dip over the edge). Baked as a loop with a run-off west and a return leg (Łęcka, '
                   'Pocztowa, Krucza). Planned by tools/plan_route.py, baked from the open world\'s caches.',
        'stage': [[1180, 4310, 'track'], [1752, 4187, 'track'], [1971, 4192, 'track'], [1929, 3712, 'track'],
                  [1925, 3330, 'track'], [1925, 2935, 'track']],
        # (back down ul. Pocztowa into Krucza, so the turn onto the edge track is not a hairpin)
        'return': [[122, 3659, U], [527, 4051, U]], 'runoff_to': [1600, 2878, 'track'],
        'runoff': 300.0, 'prefer': {'paved': 3.0, 'dirt': 1.0, 'gravel': 0.9}, 'corner_radius': 12.0,
        'surface': 'loose',
        'trackdef': dict(RALLY_TRACKDEF, display_name='Lipowiec–Kobylec Rally Stage', short_name='Lipowiec–Kobylec')},
}


class Graph:
    def __init__(self, cost, prefer=None):
        d = json.load(open(os.path.join(HERE, 'open_world', 'cache', 'brzeszcze_osm.json')))
        self.cost = cost
        self.ways, self.xy, self.adj = {}, {}, {}
        for e in d['elements']:
            if e['type'] != 'way': continue
            t = e.get('tags', {}); h = t.get('highway')
            if h not in cost: continue
            self.ways[e['id']] = e
            ns = e['nodes']
            for n, g in zip(ns, e['geometry']):
                self.xy[n] = bw.proj(g['lat'], g['lon'])
            ow = t.get('oneway') == 'yes' or h == 'motorway' or t.get('junction') == 'roundabout'
            rev = t.get('oneway') == '-1'
            for a, b in zip(ns, ns[1:]):
                L = math.dist(self.xy[a], self.xy[b])
                if not rev: self.adj.setdefault(a, []).append((b, L * cost[h], e['id'], L))
                if not ow or rev: self.adj.setdefault(b, []).append((a, L * cost[h], e['id'], L))
        self.cls = {}
        for wid, e in self.ways.items():
            for n in e['nodes']: self.cls.setdefault(n, set()).add(e['tags']['highway'])
        self.surf = {wid: surface_of(e['tags']['highway'], e['tags']) for wid, e in self.ways.items()}

    def nearest(self, p):
        kinds = set(p[2].split('|')) if len(p) > 2 else MAJOR
        cand = [n for n in self.adj if self.cls.get(n, set()) & kinds]
        if len(p) > 3:  # heading (deg, 0 = east, 90 = south): only nodes whose onward edge points that way
            hd = math.radians(p[3])
            def ok(n):
                for m, w, wid, L in self.adj[n]:
                    v = (self.xy[m][0] - self.xy[n][0], self.xy[m][1] - self.xy[n][1])
                    if L > 0 and (v[0] * math.cos(hd) + v[1] * math.sin(hd)) / L > 0.8: return True
                return False
            cand = [n for n in cand if ok(n)]
        return min(cand, key=lambda n: math.dist(self.xy[n], p[:2]))

    def route(self, a, b, used, penalty=30, prefer=None):
        dist = {a: 0}; prev = {}; q = [(0, a)]
        while q:
            c, n = heapq.heappop(q)
            if n == b: break
            if c > dist[n]: continue
            for m, w, wid, L in self.adj.get(n, []):
                if prefer: w *= prefer.get(self.surf[wid], 1.0)
                w2 = w * (penalty if m in used else 1)
                if c + w2 < dist.get(m, 1e18):
                    dist[m] = c + w2; prev[m] = (n, wid); heapq.heappush(q, (c + w2, m))
        path = [b]; wids = []
        while path[-1] != a:
            n, wid = prev[path[-1]]; wids.append(wid); path.append(n)
        return path[::-1], wids[::-1]

    def straight_on(self, path, wids, metres, used):
        """Extends a path `metres` further, at each junction taking the unused edge that turns least."""
        path, wids, run = list(path), list(wids), 0.0
        while run < metres:
            n, p = path[-1], path[-2]
            h0 = math.atan2(self.xy[n][1] - self.xy[p][1], self.xy[n][0] - self.xy[p][0])
            best = None
            for m, w, wid, L in self.adj.get(n, []):
                if m in used or m in path or L <= 0: continue
                h1 = math.atan2(self.xy[m][1] - self.xy[n][1], self.xy[m][0] - self.xy[n][0])
                turn = abs((h1 - h0 + math.pi) % (2 * math.pi) - math.pi)
                if best is None or turn < best[0]: best = (turn, m, wid, L)
            if best is None: break
            path.append(best[1]); wids.append(best[2]); run += best[3]
        return path, wids

    def length(self, path):
        return sum(math.dist(self.xy[a], self.xy[b]) for a, b in zip(path, path[1:]))


def plan(key):
    R = ROUTES[key]
    G = Graph(R.get('cost', COST))
    xy, ways = G.xy, G.ways
    stage = None
    if 'stage' in R:
        sn = [G.nearest(p) for p in R['stage']]
        full, fw, used = [sn[0]], [], {sn[0]}
        for a, b in zip(sn, sn[1:]):
            p, w = G.route(a, b, used, 1e4, R.get('prefer'))
            used |= set(p); full += p[1:]; fw += w
        stage_len = G.length(full)
        k_finish = len(full) - 1
        if 'runoff_to' in R:  # the run-off heads for a waypoint (a junction where straight on is the wrong way)
            p, w = G.route(full[-1], G.nearest(R['runoff_to']), used, 1e4)
            full += p[1:]; fw += w
        else:
            full, fw = G.straight_on(full, fw, R['runoff'], used)
        used |= set(full)
        # the start line: the node nearest the middle of the run-off
        acc, mid = 0.0, k_finish
        for k in range(k_finish, len(full) - 1):
            if acc >= R['runoff'] / 2: break
            acc += math.dist(xy[full[k]], xy[full[k + 1]]); mid = k + 1
        back = [full[-1]] + [G.nearest(p) for p in R['return']] + [sn[0]]
        for a, b in zip(back, back[1:]):
            p, w = G.route(a, b, used - {sn[0]}, 1e4)
            used |= set(p); full += p[1:]; fw += w
        start, before = full[mid], 0
        if 'runoff_to' in R:  # a long last edge: the line sits half the run-off past the finish, before the node
            before = max(0.0, round(acc - min(R['runoff'], G.length(full[k_finish:])) / 2, 1))
        stage = {'start': sn[0], 'finish': sn[-1]}
        WP = R['stage'] + R['return']
        print('stage %.2f km, run-off %.0f m' % (stage_len / 1000, G.length(full[k_finish:mid + 1]) * 2))
    else:
        WP = R['waypoints']
        nodes = [G.nearest(p) for p in WP]
        full, fw, used = [nodes[0]], [], set()
        for i in range(len(nodes)):
            a, b = nodes[i], nodes[(i + 1) % len(nodes)]
            p, w = G.route(a, b, used)
            used |= set(p[1:-1])
            full += p[1:]; fw += w
        start = G.nearest(R['start_at']) if 'start_at' in R else nodes[0]
        before = R['start_before']
    L = G.length(full)
    seq = []
    for w in fw:
        if not seq or seq[-1] != w: seq.append(w)
    dup = [w for w, c in Counter(seq).items() if c > 1]
    rep = [n for n, c in Counter(full[:-1]).items() if c > 1]
    print('length %.1f km, %d ways, repeated ways %s, repeated nodes %d' % (L / 1000, len(seq), dup, len(rep)))
    by = Counter()
    for a, b, w in zip(full, full[1:], fw): by[ways[w]['tags']['highway']] += math.dist(xy[a], xy[b])
    print({k: round(v / 1000, 1) for k, v in by.most_common()})
    if key != 'goliath':
        surf = Counter()
        for a, b, w in zip(full, full[1:], fw): surf[G.surf[w]] += math.dist(xy[a], xy[b])
        print('surfaces', {k: round(v / 1000, 2) for k, v in surf.most_common()})
    draw(key, G, full, WP)
    for n in rep: print('rep node', n, [round(v) for v in xy[n]])
    for w in dup: print('dup way', w, ways[w]['tags'].get('highway'), ways[w]['tags'].get('name'))
    # the route file
    nodes_loop = full[:-1]
    corners, last = [], None
    for a, b, w in zip(full, full[1:], fw):
        nm = ways[w]['tags'].get('name') or ('S1' if ways[w]['tags']['highway'] == 'motorway' else None)
        if nm and nm != last:
            if not corners or math.dist(xy[a], xy[corners[-1]['node']]) > 250:
                corners.append({'node': a, 'after': 30, 'name': ('ul. ' + nm) if nm != 'S1' and not nm.startswith(('Rondo', 'ul.')) else nm})
            last = nm
    cfg = {
        '_comment': R['comment'],
        'key': key, 'local': 'brzeszcze', 'origin': list(bw.ORIGIN), 'dem': 'eudem25m', 'grid': 40, 'margin': 450,
        'ways': seq, 'nodes': nodes_loop, 'start': {'node': start, 'before': before}}
    if stage:
        cfg['stage'] = stage
    cfg.update({'corner_radius': R['corner_radius'], 'corners': corners,
                'blockage_types': R.get('blockage_types', BLOCKAGE_TYPES), 'blockage_skip_service': SKIP_SERVICE})
    cfg['surfaces'] = True  # the baker writes each sample's road surface (gravel / dirt / paved)
    cfg['bridges'] = True  # lifts an overbridge where the loop passes under itself, drops the route's own bridges from the env
    cfg['trackdef'] = R['trackdef']
    json.dump(cfg, open(os.path.join(HERE, 'street_routes', key + '.json'), 'w'), indent=1, ensure_ascii=False)
    print(len(corners), 'corners')


def draw(key, G, full, WP):
    from PIL import Image, ImageDraw
    W = 1600; S = W / 10000.0
    bg = '/tmp/%s_roads.png' % key
    img = Image.open(bg) if os.path.exists(bg) else Image.new('RGB', (W, W), (245, 245, 240)); dr = ImageDraw.Draw(img)
    px = lambda p: ((p[0] + 5000) * S, (p[1] + 5000) * S)
    dr.line([px(G.xy[n]) for n in full], fill=(150, 0, 200), width=5)
    for i, p in enumerate(WP): dr.ellipse([px(p)[0]-7, px(p)[1]-7, px(p)[0]+7, px(p)[1]+7], fill=(0,0,0)); dr.text((px(p)[0]+9, px(p)[1]), str(i), fill=(0,0,0))
    img.save('/tmp/%s_route.png' % key)


if __name__ == '__main__':
    keys = sys.argv[1:]
    if not keys:
        raise SystemExit(__doc__ + '\nroutes: ' + ', '.join(ROUTES))
    for k in keys:
        plan(k)
