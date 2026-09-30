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
                                     "towers": [[kind, height, x, y]]}

Coordinates are track metres (x east, y south), as in <key>.json. Building kinds: 0 house, 1 flats/town,
2 industrial or large, 3 shed/garage, 4 farm, 5 church, 6 grandstand.

    python3 tools/build_surroundings.py [key ...]

Data © OpenStreetMap contributors, ODbL.
"""
import json, math, os, sys

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
WATER_AREAS = {('natural', 'water'), ('landuse', 'reservoir'), ('landuse', 'basin'), ('waterway', 'riverbank'),
               ('waterway', 'dock')}


def match(tags, table):
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
    return abs(sum(ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1] for i in range(len(ring) - 1))) / 2


def number(text):
    try:
        return float(str(text).split(';')[0].replace('m', '').replace(',', '.').strip())
    except ValueError:
        return None


def building_kind(tags, footprint):
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
             'bunker', 'static_caravan', 'shelter', 'transformer_tower', 'boathouse'):
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


def build(key):
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
           'buildings': [], 'stands': [], 'bridges': [], 'water': [], 'rivers': [], 'hedges': [], 'trees': [], 'towers': []}
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
        if tags.get('natural') == 'tree':
            out['trees'] += [round(p[0], 1), round(p[1], 1)]
        elif tags.get('man_made') in ('tower', 'water_tower', 'chimney', 'mast'):
            ht = number(tags.get('height')) or {'water_tower': 25, 'chimney': 40, 'mast': 35}.get(tags['man_made'], 20)
            out['towers'].append([tags['man_made'], round(ht, 1), round(p[0], 1), round(p[1], 1)])
    for el in els:  # tower outlines mapped as ways: their centre
        tags = el.get('tags', {})
        if el['type'] == 'way' and tags.get('man_made') in ('tower', 'water_tower', 'chimney', 'silo') and 'building' not in tags:
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
                if hit:
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
          f'{len(out["towers"])} towers')


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
    return [round(v, 1) for p in ring for v in p]


if __name__ == '__main__':
    for k in (sys.argv[1:] or bt.TRACKS):
        build(k)
