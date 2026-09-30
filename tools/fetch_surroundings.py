"""Fetches the OpenStreetMap features around each circuit (buildings, woods, water, land use, roads,
railways) from the public Overpass API, for the area its terrain grid covers. Raw responses are cached in
tools/osm_env/<key>.json, so build_surroundings.py runs offline.

    python3 tools/fetch_surroundings.py [key ...]      (all circuits without a cached file by default)

Data © OpenStreetMap contributors, ODbL.
"""
import json, os, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import build_tracks as bt  # noqa: E402  (projection and track list)

HERE = os.path.dirname(__file__)
OUT_DIR = os.path.join(HERE, 'osm_env')
API = 'https://overpass-api.de/api/interpreter'
GODOT_TRACKS = os.path.join(HERE, '..', 'godot', 'data', 'tracks')

LANDUSE = ('forest|farmland|meadow|grass|residential|industrial|commercial|retail|orchard|vineyard|allotments|'
           'cemetery|recreation_ground|reservoir|basin|construction|brownfield|railway|military|quarry|garages|'
           'village_green|greenfield|farmyard|plant_nursery')
NATURAL = 'wood|water|scrub|heath|sand|beach|grassland|wetland|bare_rock|scree|shingle|tree_row'
HIGHWAY = ('motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|track|living_street|'
           'pedestrian|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link|footway|path|cycleway')


def bbox(key):
    """(south, west, north, east) of the circuit's terrain grid."""
    g = json.load(open(os.path.join(GODOT_TRACKS, key + '.json')))['grid']
    proj = bt.proj_for(key)
    x0, y0 = g['x0'], g['y0']
    x1, y1 = x0 + (g['nx'] - 1) * g['step'], y0 + (g['ny'] - 1) * g['step']
    lat_a, lon_a = proj.inv(x0, y0)
    lat_b, lon_b = proj.inv(x1, y1)
    return min(lat_a, lat_b), min(lon_a, lon_b), max(lat_a, lat_b), max(lon_a, lon_b)


def query(key):
    s, w, n, e = bbox(key)
    b = f'({s:.6f},{w:.6f},{n:.6f},{e:.6f})'
    parts = [
        f'way["building"]{b};', f'relation["building"]{b};',
        f'way["building:part"]{b};',
        f'way["landuse"~"^({LANDUSE})$"]{b};', f'relation["landuse"~"^({LANDUSE})$"]{b};',
        f'way["natural"~"^({NATURAL})$"]{b};', f'relation["natural"~"^({NATURAL})$"]{b};',
        f'way["waterway"~"^(river|stream|canal|riverbank|dock)$"]{b};',
        f'way["leisure"~"^(park|pitch|golf_course|garden|marina|stadium|track)$"]{b};',
        f'way["amenity"="parking"]{b};',
        f'way["highway"~"^({HIGHWAY})$"]{b};',
        f'way["railway"~"^(rail|light_rail|narrow_gauge|tram)$"]{b};',
        f'way["man_made"~"^(pier|breakwater|groyne|tower|water_tower|chimney|silo)$"]{b};',
        f'node["man_made"~"^(tower|water_tower|chimney|mast)$"]{b};',
        f'node["natural"="tree"]{b};',
        f'way["barrier"="hedge"]{b};',
    ]
    return '[out:json][timeout:300];(' + ''.join(parts) + ');out tags geom;'


def fetch(key):
    body = urllib.parse.urlencode({'data': query(key)}).encode()
    for attempt in range(6):
        try:
            req = urllib.request.Request(API, data=body, headers={'User-Agent': 'seicento-game/1.0 (track scenery)'})
            return json.load(urllib.request.urlopen(req, timeout=400))
        except Exception as err:  # rate limit / busy server
            print('  retry', attempt, err, flush=True)
            time.sleep(15 + attempt * 20)
    raise SystemExit('Overpass failed for ' + key)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    only = sys.argv[1:]
    for key in bt.TRACKS:
        path = os.path.join(OUT_DIR, key + '.json')
        if (only and key not in only) or (not only and os.path.exists(path)):
            continue
        print(key, bbox(key), flush=True)
        data = fetch(key)
        json.dump(data, open(path, 'w'), separators=(',', ':'))
        print(f'  {len(data["elements"])} elements, {os.path.getsize(path) // 1024} KB', flush=True)
        time.sleep(5)


if __name__ == '__main__':
    main()
