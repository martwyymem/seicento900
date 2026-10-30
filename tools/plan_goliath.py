"""Plans the Goliath (the final race: one lap of the whole Brzeszcze open world) on the open world's road graph and
writes tools/street_routes/goliath.json, which build_street_tracks.py then bakes (it reads the open world's caches, so
nothing is downloaded):

    cd tools && python3 plan_goliath.py && python3 build_street_tracks.py goliath --check /tmp/goliath.png

The lap is routed through WAYPOINTS in order (x east, y south, m from the open world's origin; optional highway
classes to snap to and a heading in degrees), preferring big roads and never reusing a junction. It also draws
/tmp/goliath_route.png over the road map (the map from /tmp/goliath_roads.png when present).
"""
import json, sys, heapq, math, os

WAYPOINTS = [[-520,2600],[-2400,-400,"motorway",-125],[-3200,-2500],[-1150,-3400],[0,-3400,"unclassified|tertiary|residential"],[900,-2300],[850,-1650],[2050,-1250],[3150,-1500],[3200,0],[3600,1700],[3300,3150],[1500,3300]]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.dirname(os.path.abspath(__file__)))
import build_open_world as bw
from PIL import Image, ImageDraw
d = json.load(open('open_world/cache/brzeszcze_osm.json'))
COST = {'motorway': 0.45, 'motorway_link': 0.8, 'trunk': 0.6, 'primary': 0.65, 'secondary': 0.7, 'tertiary': 0.9,
        'secondary_link': 1.2, 'tertiary_link': 1.2, 'unclassified': 1.8, 'residential': 3.0}
ways = {}
xy = {}
adj = {}
for e in d['elements']:
    if e['type'] != 'way': continue
    t = e.get('tags', {}); h = t.get('highway')
    if h not in COST: continue
    ways[e['id']] = e
    ns = e['nodes']
    for n, g in zip(ns, e['geometry']):
        xy[n] = bw.proj(g['lat'], g['lon'])
    ow = t.get('oneway') == 'yes' or h == 'motorway' or t.get('junction') == 'roundabout'
    rev = t.get('oneway') == '-1'
    for a, b in zip(ns, ns[1:]):
        L = math.dist(xy[a], xy[b])
        if not rev: adj.setdefault(a, []).append((b, L * COST[h], e['id'], L))
        if not ow or rev: adj.setdefault(b, []).append((a, L * COST[h], e['id'], L))
cls = {}
for wid, e in ways.items():
    for n in e['nodes']: cls.setdefault(n, set()).add(e['tags']['highway'])
MAJOR = {'secondary', 'tertiary', 'primary', 'trunk'}
def nearest(p):
    kinds = set(p[2].split('|')) if len(p) > 2 else MAJOR
    cand = [n for n in adj if cls.get(n, set()) & kinds]
    if len(p) > 3:  # heading (deg, 0 = east, 90 = south): only nodes whose onward edge points that way
        hd = math.radians(p[3])
        def ok(n):
            for m, w, wid, L in adj[n]:
                v = (xy[m][0] - xy[n][0], xy[m][1] - xy[n][1])
                if L > 0 and (v[0] * math.cos(hd) + v[1] * math.sin(hd)) / L > 0.8: return True
            return False
        cand = [n for n in cand if ok(n)]
    return min(cand, key=lambda n: math.dist(xy[n], p[:2]))
def route(a, b, used):
    dist = {a: 0}; prev = {}; q = [(0, a)]
    while q:
        c, n = heapq.heappop(q)
        if n == b: break
        if c > dist[n]: continue
        for m, w, wid, L in adj.get(n, []):
            w2 = w * (30 if m in used else 1)
            if c + w2 < dist.get(m, 1e18):
                dist[m] = c + w2; prev[m] = (n, wid); heapq.heappush(q, (c + w2, m))
    path = [b]; wids = []
    while path[-1] != a:
        n, wid = prev[path[-1]]; wids.append(wid); path.append(n)
    return path[::-1], wids[::-1]
WP = WAYPOINTS
nodes = [nearest(p) for p in WP]
full, fw, used = [nodes[0]], [], set()
for i in range(len(nodes)):
    a, b = nodes[i], nodes[(i + 1) % len(nodes)]
    p, w = route(a, b, used)
    used |= set(p[1:-1])
    full += p[1:]; fw += w
L = sum(math.dist(xy[a], xy[b]) for a, b in zip(full, full[1:]))
seq = []
for w in fw:
    if not seq or seq[-1] != w: seq.append(w)
from collections import Counter
dup = [w for w, c in Counter(seq).items() if c > 1]
rep = [n for n, c in Counter(full[:-1]).items() if c > 1]
print('length %.1f km, %d ways, repeated ways %s, repeated nodes %d' % (L / 1000, len(seq), dup, len(rep)))
by = Counter()
for a, b, w in zip(full, full[1:], fw): by[ways[w]['tags']['highway']] += math.dist(xy[a], xy[b])
print({k: round(v / 1000, 1) for k, v in by.most_common()})
W = 1600; S = W / 10000.0
import os
img = Image.open('/tmp/goliath_roads.png') if os.path.exists('/tmp/goliath_roads.png') else Image.new('RGB', (W, W), (245, 245, 240)); dr = ImageDraw.Draw(img)
px = lambda p: ((p[0] + 5000) * S, (p[1] + 5000) * S)
dr.line([px(xy[n]) for n in full], fill=(150, 0, 200), width=5)
for i, p in enumerate(WP): dr.ellipse([px(p)[0]-7, px(p)[1]-7, px(p)[0]+7, px(p)[1]+7], fill=(0,0,0)); dr.text((px(p)[0]+9, px(p)[1]), str(i), fill=(0,0,0))
img.save('/tmp/goliath_route.png')
for n in rep: print('rep node', n, [round(v) for v in xy[n]])
for w in dup: print('dup way', w, ways[w]['tags'].get('highway'), ways[w]['tags'].get('name'))
# the route file
nodes_loop = full[:-1]
start = nodes[0]
corners, last = [], None
names = []
for a, b, w in zip(full, full[1:], fw):
    nm = ways[w]['tags'].get('name') or ('S1' if ways[w]['tags']['highway'] == 'motorway' else None)
    if nm and nm != last:
        if not corners or math.dist(xy[a], xy[corners[-1]['node']]) > 250:
            corners.append({'node': a, 'after': 30, 'name': ('ul. ' + nm) if nm != 'S1' and not nm.startswith(('Rondo', 'ul.')) else nm})
        last = nm
cfg = {
    '_comment': 'The Goliath: one long lap round the whole Brzeszcze open world (the final race), planned on the open '
                'world\'s road graph by waypoints and baked from its own caches ("local"). See tools/build_street_tracks.py.',
    'key': 'goliath', 'local': 'brzeszcze', 'origin': list(bw.ORIGIN), 'dem': 'eudem25m', 'grid': 40, 'margin': 450,
    'ways': seq, 'nodes': nodes_loop, 'start': {'node': start, 'before': 150}, 'corner_radius': 18.0, 'corners': corners,
    'blockage_types': ['primary', 'secondary', 'tertiary', 'unclassified', 'residential', 'living_street', 'service', 'track',
                       'primary_link', 'secondary_link', 'tertiary_link', 'motorway_link'],
    'blockage_skip_service': ['driveway', 'parking_aisle', 'drive-through'],
    'trackdef': {'display_name': 'The Seicento Goliath', 'short_name': 'Goliath', 'width': 8.0, 'theme': 'country',
                 'street_stage': True, 'barrier': 'armco', 'runoff': 2.0, 'runoff_surface': 'grass', 'runoff_paved': 0.0,
                 'kerb_style': 'none', 'kerb_width': 0.0, 'tree_density': 0.4, 'tree_patch': 0.6, 'tree_conifer': 0.4,
                 'grandstands': False, 'stand_tiers': 0, 'floodlight_spacing': 0.0, 'pit_entry': -120.0, 'pit_exit': 170.0,
                 'pit_ramp': 50.0, 'pit_offset': 9.0, 'box_start': -65.0, 'box_spacing': 9.0}}
json.dump(cfg, open('street_routes/goliath.json', 'w'), indent=1, ensure_ascii=False)
print(len(corners), 'corners')
