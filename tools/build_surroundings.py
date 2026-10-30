"""Turns the OpenStreetMap features around each circuit (tools/osm_env/<key>.json, from fetch_surroundings.py)
into what race_world.gd draws around the track:

  godot/data/tracks/<key>_land.png   land map over the terrain grid; each channel is how much of a texel is
                                     R paved (roads, car parks, yards, buildings), G farmland (its value 0.35-1
                                     picks the field's crop), B bare ground (dirt tracks,
                                     sand, rock, ballast), A forest (the trees stand where A is high)
  godot/data/tracks/<key>_env.json   {"land": {"x0", "y0", "w", "h"} (the map's corner and size in track
                                     metres), "buildings": [[height, kind, levels, x, y, x, y, ...]],
                                     "water": [[x, y, ...] outer rings], "rivers": [[width, x, y, ...]],
                                     "stands": [[x, y, ...] grandstand outlines],
                                     "bridges": [[kind, x, y, dx, dy]] where a mapped bridge crosses the
                                     circuit (kind 0 foot, 1 road; (dx, dy) the bridge's direction),
                                     "hedges": [[x, y, ...]], "trees": [x, y, ...],
                                     "towers": [[kind, height, x, y]],
                                     "landmarks": [[model, x, y, length, width, angle, height]] the
                                     features drawn by a Blender model (tools/blender/build_landmarks.py):
                                     the footprint's centre, its fitted rectangle (length along angle,
                                     radians from +x towards +y) and height (0 for a point),
                                     "pools": [[x, y, ...]] open-air swimming pools,
                                     "banking": [[banked, x, y, bridge, x, y, bridge, ...]] the disused banked
                                     ring (Monza's Sopraelevata), banked 1 concrete / 0 flat asphalt, bridge 1
                                     where it passes over a road}

Coordinates are track metres (x east, y south), as in <key>.json. Building kinds: 0 house, 1 flats/town,
2 industrial or large, 3 shed/garage, 4 farm, 5 church, 6 grandstand.

    python3 tools/build_surroundings.py [key ...]

Data © OpenStreetMap contributors, ODbL.
"""
import re, json, math, os, sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import build_tracks as bt  # noqa: E402

HERE = os.path.dirname(__file__)
ENV_DIR = os.path.join(HERE, 'osm_env')
GODOT_TRACKS = os.path.join(HERE, '..', 'godot', 'data', 'tracks')
MAX_TEXELS = 2048  # the land map's longer side
MIN_RES = 2.0  # metres per texel at best

ROAD_WIDTH = {
    'motorway': 15, 'trunk': 12, 'primary': 9, 'secondary': 8, 'tertiary': 7, 'unclassified': 5.5,
    'residential': 6, 'living_street': 5, 'pedestrian': 5, 'service': 4, 'motorway_link': 7, 'trunk_link': 7,
    'primary_link': 7, 'secondary_link': 6, 'tertiary_link': 6, 'footway': 1.8, 'cycleway': 2.2,
}
DIRT_WIDTH = {'track': 3.0, 'path': 1.4}
PAVED_AREAS = {('amenity', 'parking'): 1.0, ('landuse', 'industrial'): 0.55, ('landuse', 'commercial'): 0.5,
               ('landuse', 'retail'): 0.6, ('landuse', 'railway'): 0.35, ('landuse', 'garages'): 0.9,
               ('landuse', 'construction'): 0.3, ('landuse', 'brownfield'): 0.2, ('man_made', 'pier'): 1.0,
               ('man_made', 'breakwater'): 1.0, ('man_made', 'groyne'): 1.0, ('highway', 'pedestrian'): 1.0,
               ('leisure', 'marina'): 0.4}
FARM_AREAS = {('landuse', 'farmland'): 1.0, ('landuse', 'orchard'): 0.5, ('landuse', 'vineyard'): 0.7,
              ('landuse', 'plant_nursery'): 0.6}
BARE_AREAS = {('natural', 'sand'): 1.0, ('natural', 'beach'): 1.0, ('natural', 'bare_rock'): 0.9,
              ('natural', 'scree'): 0.9, ('natural', 'shingle'): 0.8, ('landuse', 'quarry'): 0.9,
              ('landuse', 'farmyard'): 0.5, ('landuse', 'construction'): 0.5, ('landuse', 'brownfield'): 0.5}
FOREST_AREAS = {('landuse', 'forest'): 1.0, ('natural', 'wood'): 1.0, ('leisure', 'park'): 0.5}
# OSM features drawn by a landmark model instead of a plain block: (type, id) -> model in landmarks.glb.
# Castle towers (castle:tower=yes, or a ruined man_made=tower) and big wheels are found by their tags.
LANDMARKS = {
    'indy': {('way', 286357114): 'IndyPagoda', ('node', 5623124056): 'ScoringPylon'},
    'suzuka': {('way', 183394069): 'FerrisWheel'},
    'silverstone': {('way', 227332429): 'SilverstoneWing'},
    'monza': {('way', 219396377): 'MonzaPodio'},
    'lemans': {('way', 256129642): 'TyreBridge'},  # the Dunlop (now Goodyear) footbridge
    'monaco': {('way', 161769674): 'Casino'},
    'krakow': {('relation', 13562708): 'Barbakan', ('way', 39357538): 'FloriaGate'},
    'pszczyna': {('way', 172583260): 'PszczynaCastle'},
}
WATER_AREAS = {('natural', 'water'), ('landuse', 'reservoir'), ('landuse', 'basin'), ('waterway', 'riverbank'),
               ('waterway', 'dock')}


def match(tags, table):
    """The weight of the first (key, value) in table that tags has, or None."""
    for (k, v), w in (table.items() if isinstance(table, dict) else ((t, 1.0) for t in table)):
        if tags.get(k) == v:
            return w
    return None


def rings_of(el, proj):
    """Outer and inner rings (lists of (x, y)) of a closed way or a multipolygon relation."""
    if el['type'] == 'way':
        pts = [proj(p) for p in el.get('geometry', []) if p]
        return ([pts], []) if len(pts) >= 4 and pts[0] == pts[-1] else ([], [])
    outer, inner = [], []
    for role, dest in (('outer', outer), ('inner', inner)):
        segs = [[proj(p) for p in m.get('geometry', []) if p] for m in el.get('members', [])
                if m['type'] == 'way' and m.get('role', 'outer') in ((role, '') if role == 'outer' else (role,))]
        dest.extend(join_rings([s for s in segs if len(s) >= 2]))
    return outer, inner


def join_rings(segs):
    """Joins way segments end to end into closed rings (unclosable leftovers are dropped)."""
    rings = []
    segs = [list(s) for s in segs]
    while segs:
        ring = segs.pop()
        changed = True
        while ring[0] != ring[-1] and changed:
            changed = False
            for i, s in enumerate(segs):
                if close(s[0], ring[-1]):
                    ring += s[1:]
                elif close(s[-1], ring[-1]):
                    ring += s[-2::-1]
                elif close(s[-1], ring[0]):
                    ring = s[:-1] + ring
                elif close(s[0], ring[0]):
                    ring = s[:0:-1] + ring
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        if len(ring) >= 4 and close(ring[0], ring[-1]):
            rings.append(ring)
    return rings


def close(a, b):
    """Whether two points are within 5 cm (the ends of joining ways)."""
    return abs(a[0] - b[0]) < 0.05 and abs(a[1] - b[1]) < 0.05


def simplify(pts, tol):
    """Douglas-Peucker."""
    if len(pts) < 3:
        return pts
    ax, ay = pts[0]
    bx, by = pts[-1]
    dx, dy = bx - ax, by - ay
    ln = math.hypot(dx, dy)
    best, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        px, py = pts[i]
        d = abs(dy * px - dx * py + bx * ay - by * ax) / ln if ln > 1e-9 else math.hypot(px - ax, py - ay)
        if d > best:
            best, idx = d, i
    if best <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:idx + 1], tol)[:-1] + simplify(pts[idx:], tol)


def area(ring):
    """Area of a closed ring (shoelace formula)."""
    return abs(sum(ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1] for i in range(len(ring) - 1))) / 2


def number(text):
    """Parses an OSM number tag such as '12 m' or '7,5'; None if it is not a number."""
    try:
        return float(str(text).split(';')[0].replace('m', '').replace(',', '.').strip())
    except ValueError:
        return None


def building_kind(tags, footprint):
    """(style, default height in m) for a building from its tags and footprint area."""
    b = tags.get('building', 'yes')
    if tags.get('building:part') and b == 'yes':
        b = tags['building:part']
    if b in ('house', 'detached', 'semidetached_house', 'terrace', 'bungalow', 'residential', 'dormitory', 'hotel'):
        return (1 if b in ('residential', 'dormitory', 'hotel') and footprint > 250 else 0), 7.5
    if b in ('apartments', 'flats', 'office', 'civic', 'public', 'government', 'hospital', 'school', 'university',
             'college', 'train_station', 'transportation'):
        return 1, 15.0
    if b in ('industrial', 'warehouse', 'hangar', 'manufacture', 'factory', 'storage_tank', 'hall', 'service',
             'supermarket', 'commercial', 'retail', 'sports_hall', 'sports_centre', 'kindergarten'):
        return 2, 9.0
    if b in ('garage', 'garages', 'shed', 'hut', 'cabin', 'carport', 'roof', 'kiosk', 'toilets', 'container',
             'bunker', 'static_caravan', 'shelter', 'transformer_tower', 'boathouse', 'outbuilding'):
        return 3, 3.2
    if b in ('farm', 'barn', 'farm_auxiliary', 'stable', 'cowshed', 'greenhouse', 'silo'):
        return 4, 8.0
    if b in ('church', 'chapel', 'cathedral', 'mosque', 'temple', 'shrine', 'religious'):
        return 5, 14.0
    if b in ('grandstand', 'stadium'):
        return 6, 12.0
    # plain building=yes: guess from the footprint
    if footprint < 45:
        return 3, 3.2
    if footprint > 1800:
        return 2, 10.0
    return 0, 7.5


def landmark_of(key, el):
    """The landmark mesh name for an OSM element (by id in LANDMARKS, or by tags), or None."""
    tags = el.get('tags', {})
    name = LANDMARKS.get(key, {}).get((el['type'], el['id']))
    if name:
        return name
    if tags.get('attraction') == 'big_wheel':
        return 'FerrisWheel'
    if tags.get('castle:tower') == 'yes' or (tags.get('man_made') == 'tower' and tags.get('historic') == 'ruins'):
        return 'CastleKeep' if tags.get('defensive') == 'Bergfried' or (number(tags.get('height')) or 0) >= 15 else 'CastleTower'
    return None


def hull(pts):
    """Convex hull of points (monotone chain)."""
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def fit_rect(pts):
    """The smallest rectangle round pts: (cx, cy, length, width, angle of the long side)."""
    h = hull(pts)
    best = None
    for i in range(len(h)):
        a, b = h[i], h[(i + 1) % len(h)]
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        c, s = math.cos(ang), math.sin(ang)
        us = [p[0] * c + p[1] * s for p in h]
        vs = [-p[0] * s + p[1] * c for p in h]
        du, dv = max(us) - min(us), max(vs) - min(vs)
        if best is None or du * dv < best[0]:
            cu, cv = (max(us) + min(us)) / 2, (max(vs) + min(vs)) / 2
            if du < dv:
                du, dv, ang = dv, du, ang + math.pi / 2
            best = (du * dv, cu * c - cv * s, cu * s + cv * c, du, dv, math.atan2(math.sin(ang), math.cos(ang)))
    return best[1:]


def castle_walls(towers):
    """Curtain walls between a castle's towers: round the towers of each castle in angle order, skipping
    gaps too wide to be one wall. towers: [x, y, radius]."""
    walls = []
    used = set()
    for i in range(len(towers)):
        if i in used:
            continue
        group, todo = [], [i]
        while todo:  # the towers within 60 m of each other are one castle
            k = todo.pop()
            if k in used:
                continue
            used.add(k)
            group.append(towers[k])
            todo += [j for j in range(len(towers)) if j not in used and math.dist(towers[k][:2], towers[j][:2]) < 60]
        if len(group) < 3:
            continue
        cx = sum(t[0] for t in group) / len(group)
        cy = sum(t[1] for t in group) / len(group)
        group.sort(key=lambda t: math.atan2(t[1] - cy, t[0] - cx))
        for a, b in zip(group, group[1:] + group[:1]):
            d = math.dist(a[:2], b[:2])
            span = d - a[2] - b[2] + 1.0
            if 2 < span < 45:
                walls.append(['CastleWall', round((a[0] + b[0]) / 2, 1), round((a[1] + b[1]) / 2, 1), round(span, 1), 1.8,
                              round(math.atan2(b[1] - a[1], b[0] - a[0]), 3), 7.0])
    return walls


def build(key):
    """Turns tools/osm_env/<key>.json into godot/data/tracks/<key>_env.json and its land map."""
    src = os.path.join(ENV_DIR, key + '.json')
    if not os.path.exists(src):
        print(key, ': no', src, '(run fetch_surroundings.py)')
        return
    data = json.load(open(src))
    proj = bt.proj_for(key)
    g = json.load(open(os.path.join(GODOT_TRACKS, key + '.json')))['grid']
    x0, y0 = g['x0'], g['y0']
    w, h = (g['nx'] - 1) * g['step'], (g['ny'] - 1) * g['step']
    res = max(MIN_RES, max(w, h) / MAX_TEXELS)
    tw, th = int(math.ceil(w / res)), int(math.ceil(h / res))
    ss = 2  # supersampling, for soft edges
    chans = [Image.new('L', (tw * ss, th * ss), 0) for _ in range(4)]
    draws = [ImageDraw.Draw(c) for c in chans]

    def px(p):
        return ((p[0] - x0) / res * ss, (p[1] - y0) / res * ss)

    def fill(ch, outer, inner, weight):
        v = int(255 * weight)
        for r in outer:
            if len(r) >= 3:
                draws[ch].polygon([px(p) for p in r], fill=v)
        for r in inner:
            if len(r) >= 3:
                draws[ch].polygon([px(p) for p in r], fill=0)

    def line(ch, pts, width, weight):
        pp = [px(p) for p in pts]
        wpx = max(1, int(round(width / res * ss)))
        draws[ch].line(pp, fill=int(255 * weight), width=wpx, joint='curve')
        r = wpx / 2
        for q in pp:  # round caps and joins
            draws[ch].ellipse((q[0] - r, q[1] - r, q[0] + r, q[1] + r), fill=int(255 * weight))

    out = {'land': {'x0': round(x0, 2), 'y0': round(y0, 2), 'w': round(tw * res, 2), 'h': round(th * res, 2)},
           'buildings': [], 'stands': [], 'bridges': [], 'water': [], 'rivers': [], 'hedges': [], 'trees': [], 'towers': [],
           'landmarks': [], 'pools': [], 'banking': []}
    bank_ways = []
    # areas first (larger features under smaller ones), then lines
    els = data['elements']
    areas = []
    for el in els:
        tags = el.get('tags', {})
        if el['type'] == 'node' or 'building' in tags or 'building:part' in tags:
            continue
        for ch, table in ((3, FOREST_AREAS), (1, FARM_AREAS), (2, BARE_AREAS), (0, PAVED_AREAS)):
            wgt = match(tags, table)
            if wgt is None or (ch == 0 and tags.get('highway') == 'pedestrian' and tags.get('area') != 'yes'):
                continue
            outer, inner = rings_of(el, proj)
            if outer:
                if ch == 1:  # one crop per field: the value picks it (0.35-1), so it can't be a coverage
                    wgt = 0.35 + 0.65 * ((el['id'] * 2654435761) % 1000) / 999.0
                areas.append((-sum(area(r) for r in outer), ch, outer, inner, wgt))
        if tags.get('leisure') == 'swimming_pool' and 'building' not in tags and tags.get('indoor') != 'yes' \
                and tags.get('covered') != 'yes':
            outer, _ = rings_of(el, proj)
            for r in outer:
                r = simplify(r, 0.2)
                if len(r) >= 4 and area(r) > 6:
                    out['pools'].append(flat(r[:-1]))
                    line(0, r, 3.0, 1.0)  # the paved surround
        if match(tags, WATER_AREAS) is not None:
            outer, _ = rings_of(el, proj)
            for r in outer:
                r = simplify(r, 1.0)
                if len(r) >= 4 and area(r) > 30:
                    out['water'].append(flat(r))
    for _, ch, outer, inner, wgt in sorted(areas, key=lambda a: a[0]):
        fill(ch, outer, inner, wgt)
    for el in els:
        tags = el.get('tags', {})
        if el['type'] != 'way':
            continue
        pts = [proj(p) for p in el.get('geometry', []) if p]
        if len(pts) < 2:
            continue
        hw = tags.get('highway')
        if hw == 'raceway' and tags.get('historic') == 'ruins' and re.search('sopraelevata|alta velocit|rettilineo anello', tags.get('name', ''), re.I):
            bank_ways.append((tags.get('surface') == 'concrete', tags.get('bridge') == 'yes', pts))
            continue
        if hw in ROAD_WIDTH and tags.get('area') != 'yes':
            width = number(tags.get('width')) or ROAD_WIDTH[hw]
            paved = tags.get('surface', 'asphalt') not in ('gravel', 'dirt', 'ground', 'grass', 'unpaved', 'compacted',
                                                          'fine_gravel', 'earth', 'mud', 'sand', 'wood')
            if hw in ('footway', 'cycleway') and not paved:
                line(2, pts, width, 0.8)
            elif tags.get('tunnel') not in ('yes', 'building_passage'):
                line(0 if paved else 2, pts, width, 1.0 if hw not in ('footway', 'cycleway') else 0.75)
        elif hw in DIRT_WIDTH:
            paved = tags.get('surface') in ('asphalt', 'paved', 'concrete', 'paving_stones')
            line(0 if paved else 2, pts, DIRT_WIDTH[hw] * (1.3 if paved else 1.0), 0.85)
        elif tags.get('railway') in ('rail', 'light_rail', 'narrow_gauge') and tags.get('tunnel') != 'yes':
            line(2, pts, 4.0, 0.7)
        elif tags.get('waterway') in ('river', 'canal') and tags.get('tunnel') != 'yes':
            width = number(tags.get('width')) or (12.0 if tags['waterway'] == 'river' else 8.0)
            out['rivers'].append([round(width, 1)] + flat(simplify(pts, 1.0)))
        elif tags.get('barrier') == 'hedge':
            out['hedges'].append(flat(simplify(pts, 0.5)))
        elif tags.get('natural') == 'tree_row':
            out['hedges'].append([-1.0] + flat(simplify(pts, 0.5)))  # -1: a row of trees, not a hedge
    castle = []
    for el in els:
        tags = el.get('tags', {})
        if 'building' not in tags and 'building:part' not in tags:
            continue
        if tags.get('building') in ('no', 'construction', 'ruins', 'collapsed') or tags.get('location') == 'underground':
            continue
        if 'building:part' in tags and 'building' not in tags:
            continue  # parts duplicate their building's outline (heights would need the whole 3D model)
        outer, _ = rings_of(el, proj)
        for r in outer:
            r = simplify(r, 0.35)
            if len(r) < 4:
                continue
            fp = area(r)
            if fp < 8:
                continue
            fill(0, [r], [], 1.0)  # (no trees through the house)
            lm = landmark_of(key, el)
            if lm:
                cx, cy, ln, wd, ang = fit_rect(r[:-1])
                ht = number(tags.get('height')) or 0.0
                out['landmarks'].append([lm, round(cx, 1), round(cy, 1), round(ln, 1), round(wd, 1), round(ang, 3), ht])
                if lm.startswith('Castle'):
                    castle.append([cx, cy, wd / 2])
                continue
            kind, height = building_kind(tags, fp)
            levels = number(tags.get('building:levels'))
            if number(tags.get('height')):
                height = number(tags['height'])
            elif levels:
                height = levels * (3.0 if kind != 2 else 4.5) + (1.5 if kind in (0, 4) else 0.6)
            else:
                levels = 0
            if kind == 6:  # grandstands are built from the trackside pieces, facing the circuit
                out['stands'].append(flat(r[:-1]))
                continue
            out['buildings'].append([round(max(2.5, min(height, 200.0)), 1), kind, int(levels or 0)] + flat(r[:-1]))
    for el in els:
        tags = el.get('tags', {})
        if el['type'] != 'node':
            continue
        p = proj(el)
        lm = landmark_of(key, el)
        if lm:
            out['landmarks'].append([lm, round(p[0], 1), round(p[1], 1), 0.0, 0.0, 0.0, number(tags.get('height')) or 0.0])
        elif tags.get('natural') == 'tree':
            out['trees'] += [round(p[0], 1), round(p[1], 1)]
        elif tags.get('man_made') in ('tower', 'water_tower', 'chimney', 'mast'):
            ht = number(tags.get('height')) or {'water_tower': 25, 'chimney': 40, 'mast': 35}.get(tags['man_made'], 20)
            out['towers'].append([tags['man_made'], round(ht, 1), round(p[0], 1), round(p[1], 1)])
    out['landmarks'] += castle_walls(castle)
    for banked, chain in banking_chains(bank_ways):
        out['banking'].append([1 if banked else 0] + [round(v, 1) for p in chain for v in p])
        if not banked:
            line(0, [(p[0], p[1]) for p in chain], 9.0, 1.0)
    for el in els:  # tower outlines mapped as ways: their centre
        tags = el.get('tags', {})
        if el['type'] == 'way' and tags.get('man_made') in ('tower', 'water_tower', 'chimney', 'silo') and 'building' not in tags \
                and not landmark_of(key, el):
            pts = [proj(p) for p in el.get('geometry', []) if p]
            if pts:
                cx = sum(p[0] for p in pts) / len(pts)
                cy = sum(p[1] for p in pts) / len(pts)
                ht = number(tags.get('height')) or 20
                out['towers'].append([tags['man_made'], round(ht, 1), round(cx, 1), round(cy, 1)])

    # bridges over the circuit: where a bridge way crosses the centreline
    track = json.load(open(os.path.join(GODOT_TRACKS, key + '.json')))
    tp = list(zip(track['pts'][0::2], track['pts'][1::2]))
    tsegs = list(zip(tp, tp[1:] + tp[:1]))
    for el in els:
        tags = el.get('tags', {})
        if el['type'] != 'way' or tags.get('bridge') not in ('yes', 'viaduct') or 'highway' not in tags:
            continue
        pts = [proj(p) for p in el.get('geometry', []) if p]
        for a, b in zip(pts, pts[1:]):
            for c, d in tsegs:
                hit = cross_point(a, b, c, d)
                if hit and landmark_of(key, el):
                    ln = math.dist(a, b) or 1.0
                    out['landmarks'].append([landmark_of(key, el), round(hit[0], 1), round(hit[1], 1),
                                             round(math.dist(pts[0], pts[-1]), 1), 5.0,
                                             round(math.atan2(b[1] - a[1], b[0] - a[0]), 3), 0.0])
                elif hit:
                    foot = tags['highway'] in ('footway', 'path', 'cycleway', 'steps', 'pedestrian', 'track', 'bridleway')
                    ln = math.dist(a, b) or 1.0
                    out['bridges'].append([0 if foot else 1, round(hit[0], 1), round(hit[1], 1),
                                           round((b[0] - a[0]) / ln, 3), round((b[1] - a[1]) / ln, 3)])

    img = Image.merge('RGBA', [c.resize((tw, th), Image.LANCZOS) for c in chans])
    img.save(os.path.join(GODOT_TRACKS, key + '_land.png'), optimize=True)
    json.dump(out, open(os.path.join(GODOT_TRACKS, key + '_env.json'), 'w'), separators=(',', ':'))
    print(f'{key}: land map {tw}x{th} at {res:.1f} m, {len(out["buildings"])} buildings, {len(out["stands"])} stands, '
          f'{len(out["water"])} water, '
          f'{len(out["rivers"])} rivers, {len(out["hedges"])} hedges/tree rows, {len(out["trees"]) // 2} trees, '
          f'{len(out["towers"])} towers, {len(out["pools"])} pools, landmarks: '
          f'{", ".join(sorted(set(m[0] for m in out["landmarks"])))}')


def banking_chains(ways, tol=4.0):
    """Joins mapped pieces of a disused banked ring (Monza's Sopraelevata) end to end, concrete with concrete and
    asphalt with asphalt: [(banked, [(x, y, bridge), ...])]. bridge is 1 where the ring passes over a road."""
    pieces = [(b, [(p[0], p[1], 1 if bridge else 0) for p in pts]) for b, bridge, pts in ways]
    chains = []
    while pieces:
        banked, chain = pieces.pop(0)
        grew = True
        while grew:
            grew = False
            for i, (b2, pts) in enumerate(pieces):
                if b2 != banked:
                    continue
                for cand in (pts, pts[::-1]):
                    if math.dist(chain[-1][:2], cand[0][:2]) < tol:
                        chain = chain + cand[1:]
                    elif math.dist(chain[0][:2], cand[-1][:2]) < tol:
                        chain = cand[:-1] + chain
                    else:
                        continue
                    pieces.pop(i)
                    grew = True
                    break
                if grew:
                    break
        chains.append((banked, chain))
    return chains


def cross_point(a, b, c, d):
    """Where segment ab crosses segment cd, or None."""
    r = (b[0] - a[0], b[1] - a[1])
    q = (d[0] - c[0], d[1] - c[1])
    den = r[0] * q[1] - r[1] * q[0]
    if abs(den) < 1e-9:
        return None
    t = ((c[0] - a[0]) * q[1] - (c[1] - a[1]) * q[0]) / den
    u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
    if 0 <= t <= 1 and 0 <= u <= 1:
        return (a[0] + r[0] * t, a[1] + r[1] * t)
    return None


def flat(ring):
    """A ring as a flat [x0, y0, x1, y1, ...] list rounded to 10 cm, for the JSON."""
    return [round(v, 1) for p in ring for v in p]


if __name__ == '__main__':
    for k in (sys.argv[1:] or bt.TRACKS):
        build(k)
