"""Adds the cities and towns round each circuit to its distant terrain (godot/data/tracks/<key>_far.json, from
fetch_horizon.py), so far_land.gd raises the towers of a city centre where a real city stands, as tall and as
many as its size, rather than over every built-up suburb. The places are OpenStreetMap's place=city and
place=town nodes with a population (public Overpass API, (c) OpenStreetMap contributors, ODbL); the raw
response is cached in tools/.tiles/places/ so later builds run offline.

  "places" in <key>_far.json   [[x, z, population, name], ...] in track metres, largest first

    python3 tools/fetch_places.py [key ...]
"""
import json, os, re, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import build_tracks as bt  # noqa: E402

HERE = os.path.dirname(__file__)
CACHE = os.path.join(HERE, '.tiles', 'places')
GODOT_TRACKS = os.path.join(HERE, '..', 'godot', 'data', 'tracks')
API = 'https://overpass-api.de/api/interpreter'
MIN_POPULATION = 15000  # smaller towns have no centre to see from 10 km


def fetch(key, south, west, north, east):
    """Queries Overpass for the cities and towns in a lat/lon box, cached under CACHE."""
    path = os.path.join(CACHE, key + '.json')
    if os.path.exists(path):
        return json.load(open(path))
    q = f'[out:json][timeout:120];node["place"~"^(city|town)$"]["population"]({south},{west},{north},{east});out;'
    for attempt in range(5):
        try:
            req = urllib.request.Request(API, data=urllib.parse.urlencode({'data': q}).encode(),
                                         headers={'User-Agent': 'seicento-game/1.0'})
            data = json.load(urllib.request.urlopen(req, timeout=180))
            os.makedirs(CACHE, exist_ok=True)
            json.dump(data, open(path, 'w'))
            return data
        except Exception as e:
            print('  retry', attempt, e)
            time.sleep(5 + attempt * 10)
    raise SystemExit('Overpass failed for ' + key)


def population(tags):
    """The population tag as a number (tolerating separators and notes), 0 if missing."""
    m = re.match(r'[\d.,\s]+', tags.get('population', ''))
    return int(re.sub(r'[^\d]', '', m.group(0)) or 0) if m else 0


def build(key):
    """Adds the towns over MIN_POPULATION inside the far terrain to <key>_far.json."""
    path = os.path.join(GODOT_TRACKS, key + '_far.json')
    far = json.load(open(path))
    P = bt.proj_for(key)
    xs, zs = far['xs'], far['zs']
    corners = [P.inv(x, z) for x in (xs[0], xs[-1]) for z in (zs[0], zs[-1])]
    lats = [c[0] for c in corners]
    lons = [c[1] for c in corners]
    data = fetch(key, min(lats), min(lons), max(lats), max(lons))
    places = []
    for el in data['elements']:
        pop = population(el.get('tags', {}))
        if pop < MIN_POPULATION:
            continue
        x, z = P(el)
        if xs[0] <= x <= xs[-1] and zs[0] <= z <= zs[-1]:
            places.append([round(x), round(z), pop, el['tags'].get('name', '')])
    places.sort(key=lambda p: -p[2])
    far['places'] = places
    json.dump(far, open(path, 'w'), separators=(',', ':'))
    print(key, len(places), ', '.join(f'{p[3]} {p[2]}' for p in places[:5]), flush=True)


def main():
    """Adds the places for every track (or those named on the command line)."""
    only = sys.argv[1:]
    for key in bt.TRACKS:
        if only and key not in only:
            continue
        build(key)
    print('done')


if __name__ == '__main__':
    main()
