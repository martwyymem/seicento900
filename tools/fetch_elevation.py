"""Fetches EU-DEM 25 m (Europe) / NED 10 m (USA) elevations (via the public OpenTopoData API) for the track centrelines and
a terrain grid around each track. Results are cached in tools/elevation.json, so builds run offline.

Rate limits of the public API: 100 locations per request, 1 request per second.
"""
import json, math, os, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, 'elevation.json')
API = 'https://api.opentopodata.org/v1/'

import build_tracks as bt  # noqa: E402  (reuses the chain definitions + projection)

def query(latlons, dataset):
    out = []
    for i in range(0, len(latlons), 100):
        chunk = latlons[i:i + 100]
        body = urllib.parse.urlencode({'locations': '|'.join(f'{a:.6f},{b:.6f}' for a, b in chunk)}).encode()
        for attempt in range(5):
            try:
                req = urllib.request.Request(API + dataset, data=body, headers={'User-Agent': 'seicento-game/1.0'})
                res = json.load(urllib.request.urlopen(req, timeout=60))
                if res.get('status') == 'OK':
                    break
            except Exception as e:  # rate limit / transient
                print('  retry', attempt, e)
            time.sleep(3 + attempt * 3)
        else:
            raise SystemExit('elevation API failed')
        out += [r['elevation'] if r['elevation'] is not None else 0 for r in res['results']]
        print(f'  {len(out)}/{len(latlons)}', flush=True)
        time.sleep(1.1)
    return out

def main():
    cache = json.load(open(OUT)) if os.path.exists(OUT) else {}
    only = sys.argv[1:]
    for key, t in bt.TRACKS.items():
        if key in cache or (only and key not in only):
            continue
        P = bt.proj_for(key)
        unproj = P.inv
        grid_step = t['grid']
        pts, _, _ = bt.centreline(key)
        rs, _, total = bt.resample(pts, [None] * len(pts), 20.0)
        print(key, 'centreline', len(rs))
        line = query([unproj(x, y) for x, y in rs], t['dem'])
        xs = [p[0] for p in rs]; ys = [p[1] for p in rs]
        margin = 700
        x0, y0 = min(xs) - margin, min(ys) - margin
        nx = int((max(xs) + margin - x0) / grid_step) + 1
        ny = int((max(ys) + margin - y0) / grid_step) + 1
        print(key, 'grid', nx, 'x', ny)
        cells = [unproj(x0 + i * grid_step, y0 + j * grid_step) for j in range(ny) for i in range(nx)]
        grid = query(cells, t['dem'])
        cache[key] = {'line_step': total / len(rs), 'line': [round(h, 2) for h in line],
                      'grid': {'x0': x0, 'y0': y0, 'step': grid_step, 'nx': nx, 'ny': ny, 'h': [round(h, 1) for h in grid]}}
        json.dump(cache, open(OUT, 'w'))
    print('done')

if __name__ == '__main__':
    main()
