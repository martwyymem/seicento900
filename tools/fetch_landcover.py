"""Adds the real land cover to the distant terrain round each circuit (godot/data/tracks/<key>_far.json, from
fetch_horizon.py), so far_land.gd puts woods, towns, fields and lakes where they are instead of where noise
would. The cover comes from ESA WorldCover 2021 (10 m, CC BY 4.0, https://esa-worldcover.org), read from the
public COGs on AWS at their 1/8 overview (about 75 m per pixel): only the internal tiles that the grid
touches are fetched, by HTTP range requests, and cached in tools/.tiles/worldcover/ so later builds run offline.

  "cover" in <key>_far.json   one character per grid point, row by row as "h": the cover of the ground round
                              the point (its share of the cells between it and its neighbours):
                              f wood, t town, c cropland, g grass or scrub, r bare ground or rock, s snow and
                              ice, w water, m wetland

    python3 tools/fetch_landcover.py [key ...]

Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.
"""
import json, math, os, struct, sys, time, urllib.error, urllib.request, zlib

sys.path.insert(0, os.path.dirname(__file__))
import build_tracks as bt  # noqa: E402

HERE = os.path.dirname(__file__)
CACHE = os.path.join(HERE, '.tiles', 'worldcover')
GODOT_TRACKS = os.path.join(HERE, '..', 'godot', 'data', 'tracks')
URL = 'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{name}_Map.tif'
LEVEL = 3  # the IFD read: 0 is the full 36000 px, each overview half the last, so 3 is 4500 px over 3 degrees
SAMPLE = 75.0  # metres between the samples over a grid point's footprint
# WorldCover classes -> cover codes (10 tree cover, 20 shrubland, 30 grassland, 40 cropland, 50 built-up,
# 60 bare/sparse vegetation, 70 snow and ice, 80 permanent water, 90 herbaceous wetland, 95 mangroves, 100 moss)
CLASS = {10: 'f', 20: 'g', 30: 'g', 40: 'c', 50: 't', 60: 'r', 70: 's', 80: 'w', 90: 'm', 95: 'f', 100: 'g'}
# a town covers less of the ground than the woods and fields round it but is what the eye picks out
WEIGHT = {'t': 2.2}


def fetch(url, start=None, length=None):
    headers = {'User-Agent': 'seicento-game/1.0'}
    if start is not None:
        headers['Range'] = f'bytes={start}-{start + length - 1}'
    for attempt in range(5):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60).read()
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):
                return None  # no file: open ocean
            print('  retry', attempt, e)
        except Exception as e:
            print('  retry', attempt, e)
        time.sleep(2 + attempt * 2)
    raise SystemExit('download failed: ' + url)


class Sheet:
    """One 3 x 3 degree WorldCover file: its overview's tile layout, and the tiles read so far."""

    def __init__(self, name, lat0, lon0):
        self.name, self.lat0, self.lon0 = name, lat0, lon0
        self.tiles = {}
        os.makedirs(CACHE, exist_ok=True)
        meta_path = os.path.join(CACHE, name + '.json')
        if os.path.exists(meta_path):
            self.meta = json.load(open(meta_path))
        else:
            self.meta = self._read_layout()
            json.dump(self.meta, open(meta_path, 'w'))

    def _read_layout(self):
        head = fetch(URL.format(name=self.name), 0, 1 << 18)
        if head is None:
            return None
        assert head[:4] == b'II*\x00', 'expected a little-endian classic TIFF'
        off = struct.unpack('<I', head[4:8])[0]
        for _ in range(LEVEL):
            n = struct.unpack('<H', head[off:off + 2])[0]
            off = struct.unpack('<I', head[off + 2 + n * 12: off + 6 + n * 12])[0]
        n = struct.unpack('<H', head[off:off + 2])[0]
        tags = {}
        for i in range(n):
            tag, typ, cnt = struct.unpack('<HHI', head[off + 2 + i * 12: off + 10 + i * 12])
            raw = head[off + 10 + i * 12: off + 14 + i * 12]
            size = {3: 2, 4: 4}.get(typ, 1)
            fmt = {3: 'H', 4: 'I'}.get(typ, 'B')
            if cnt * size <= 4:
                vals = struct.unpack('<' + fmt * cnt, raw[:cnt * size])
            else:
                p = struct.unpack('<I', raw)[0]
                vals = struct.unpack('<' + fmt * cnt, head[p:p + cnt * size])
            tags[tag] = list(vals)
        assert tags[259][0] == 8 and tags.get(317, [1])[0] == 1, 'expected deflate without a predictor'
        return {'size': tags[256][0], 'tile': tags[322][0], 'offsets': tags[324], 'counts': tags[325]}

    def tile(self, tx, ty):
        key = (tx, ty)
        if key not in self.tiles:
            m = self.meta
            across = math.ceil(m['size'] / m['tile'])
            i = ty * across + tx
            path = os.path.join(CACHE, f'{self.name}_{LEVEL}_{tx}_{ty}.bin')
            if os.path.exists(path):
                data = open(path, 'rb').read()
            else:
                data = fetch(URL.format(name=self.name), m['offsets'][i], m['counts'][i])
                open(path, 'wb').write(data)
            self.tiles[key] = zlib.decompress(data)
        return self.tiles[key]

    def at(self, lat, lon):
        if self.meta is None:
            return 80
        m = self.meta
        px = min(int((lon - self.lon0) / 3.0 * m['size']), m['size'] - 1)
        py = min(int((self.lat0 + 3.0 - lat) / 3.0 * m['size']), m['size'] - 1)
        t = m['tile']
        return self.tile(px // t, py // t)[(py % t) * t + px % t]


_sheets = {}


def cover_at(lat, lon):
    lat0 = math.floor(lat / 3.0) * 3
    lon0 = math.floor(lon / 3.0) * 3
    key = (lat0, lon0)
    if key not in _sheets:
        name = f"{'N' if lat0 >= 0 else 'S'}{abs(lat0):02d}{'E' if lon0 >= 0 else 'W'}{abs(lon0):03d}"
        _sheets[key] = Sheet(name, lat0, lon0)
    return _sheets[key].at(lat, lon)


def footprint(axis, i):
    """The stretch of the axis nearer position i than its neighbours."""
    lo = (axis[i] - axis[i - 1]) / 2 if i > 0 else (axis[1] - axis[0]) / 2
    hi = (axis[i + 1] - axis[i]) / 2 if i < len(axis) - 1 else lo
    return axis[i] - lo, axis[i] + hi


def build(key):
    path = os.path.join(GODOT_TRACKS, key + '_far.json')
    far = json.load(open(path))
    P = bt.proj_for(key)
    xs, zs = far['xs'], far['zs']
    spans_x = [footprint(xs, i) for i in range(len(xs))]
    spans_z = [footprint(zs, j) for j in range(len(zs))]
    out = []
    for j, z in enumerate(zs):
        z0, z1 = spans_z[j]
        nz = max(1, min(9, round((z1 - z0) / SAMPLE)))
        for i, x in enumerate(xs):
            x0, x1 = spans_x[i]
            nx = max(1, min(9, round((x1 - x0) / SAMPLE)))
            votes = {}
            for b in range(nz):
                for a in range(nx):
                    lat, lon = P.inv(x0 + (a + 0.5) / nx * (x1 - x0), z0 + (b + 0.5) / nz * (z1 - z0))
                    c = CLASS.get(cover_at(lat, lon), 'g')
                    votes[c] = votes.get(c, 0.0) + WEIGHT.get(c, 1.0)
            out.append(max(votes, key=votes.get))
    far['cover'] = ''.join(out)
    json.dump(far, open(path, 'w'), separators=(',', ':'))
    counts = {c: far['cover'].count(c) for c in sorted(set(far['cover']))}
    print(key, len(xs), 'x', len(zs), counts, flush=True)


def main():
    only = sys.argv[1:]
    for key in bt.TRACKS:
        if only and key not in only:
            continue
        build(key)
    print('done')


if __name__ == '__main__':
    main()
