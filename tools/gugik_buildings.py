"""Measured building data for the open world from GUGiK (Główny Urząd Geodezji i Kartografii) open data:

  LoD2 3D building models (CityGML 2.0, 2017 state, from BDOT10k footprints and ALS lidar): roof type and
      the roof surfaces themselves, per powiat
      https://opendata.geoportal.gov.pl/InneDane/Budynki3D/LOD2/<teryt>_gml.zip
  LoD1 3D building models, 2024 state: a height for every building, including those built since 2017
      https://opendata.geoportal.gov.pl/InneDane/Budynki3D/LOD1/2024/<woj>/<teryt>.zip
  BDOT10k (schema 2021, GeoPackage), layer BUBD_A: building function and number of storeys
      https://opendata.geoportal.gov.pl/bdot10k/schemat2021/GPKG/<woj>/<teryt>_GPKG.zip
  Orthophoto (RGB, 0.25 m, 2024-2026 sheets, GeoTIFF downloads, not the viewing WMS, whose terms forbid
      harvesting images): the roof colour seen from above
      https://opendata.geoportal.gov.pl/ortofotomapa/<work>/<sheet>.tif, listed by the index WMS
      https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/SkorowidzeWgAktualnosci

The download links come from the "Modele 3D budynków" index WMS
(https://mapy.geoportal.gov.pl/wss/service/PZGIK/FOTO/WMS/ModeleBudynkow3D, GetFeatureInfo per powiat).
Polish geodetic and cartographic data from the national resource (PZGiK) is free to use for any purpose,
including commercially, since 31 July 2020 (Prawo geodezyjne i kartograficzne, art. 40a ust. 2 / 40b, as
amended by the act of 16 April 2020). Source: Główny Urząd Geodezji i Kartografii, geoportal.gov.pl.

Downloads are untrusted data: they go to tools/open_world/cache/gugik/ (gitignored, ~700 MB with the orthophoto), are parsed with
a non-validating XML parser (no DTDs or external entities) and sqlite3, and nothing in them is executed.
Only the buildings inside the open world's box are kept, in a compact extract that is committed
(tools/open_world/cache/<key>_gugik.json) so rebuilds run offline:

    python3 -I tools/gugik_buildings.py [--refetch]     # rebuilds the extract (needs the network once)

Coordinates are EPSG:2180 (PUWG 1992: transverse Mercator on GRS80, lon0 19 deg, k0 0.9993,
FE 500000, FN -5300000) in the source files, converted here to the baker's local metres.
"""
import json, math, os, sqlite3, struct, sys, time, urllib.request, zipfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'open_world', 'cache')
RAW = os.path.join(CACHE, 'gugik')
UA = {'User-Agent': 'seicento-game/1.0 (open world buildings)'}

# powiats whose data the Brzeszcze box touches: oświęcimski (Małopolska) and pszczyński (Śląsk, over the Vistula)
POWIATS = [('12', '1213'), ('24', '2410')]
LOD2_URL = 'https://opendata.geoportal.gov.pl/InneDane/Budynki3D/LOD2/{t}_gml.zip'
LOD1_URL = 'https://opendata.geoportal.gov.pl/InneDane/Budynki3D/LOD1/2024/{w}/{t}.zip'
BDOT_URL = 'https://opendata.geoportal.gov.pl/bdot10k/schemat2021/GPKG/{w}/{t}_GPKG.zip'
ORTO_INDEX = 'https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/SkorowidzeWgAktualnosci'
ORTO_LAYERS = ['SkorowidzeOrtofotomapy2026', 'SkorowidzeOrtofotomapy2025', 'SkorowidzeOrtofotomapy2024']

# ---------------------------------------------------------------- EPSG:2180

_A = 6378137.0
_F = 1 / 298.257222101
_K0, _LON0, _FE, _FN = 0.9993, math.radians(19.0), 500000.0, -5300000.0
_N = _F / (2 - _F)
_AA = _A / (1 + _N) * (1 + _N ** 2 / 4 + _N ** 4 / 64)
_ALPHA = [_N / 2 - 2 * _N ** 2 / 3 + 5 * _N ** 3 / 16, 13 * _N ** 2 / 48 - 3 * _N ** 3 / 5, 61 * _N ** 3 / 240]
_BETA = [_N / 2 - 2 * _N ** 2 / 3 + 37 * _N ** 3 / 96, _N ** 2 / 48 + _N ** 3 / 15, 17 * _N ** 3 / 480]
_DELTA = [2 * _N - 2 * _N ** 2 / 3 - 2 * _N ** 3, 7 * _N ** 2 / 3 - 8 * _N ** 3 / 5, 56 * _N ** 3 / 15]
_E = math.sqrt(_F * (2 - _F))


def to_2180(lat, lon):
    """(easting, northing) of a WGS84/ETRS89 point (Krüger series, sub-millimetre here)."""
    phi, lam = math.radians(lat), math.radians(lon) - _LON0
    t = math.sinh(math.atanh(math.sin(phi)) - _E * math.atanh(_E * math.sin(phi)))
    xi = math.atan2(t, math.cos(lam))
    eta = math.atanh(math.sin(lam) / math.sqrt(1 + t * t))
    x, y = xi, eta
    for j, a in enumerate(_ALPHA, 1):
        x += a * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
        y += a * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
    return _FE + _K0 * _AA * y, _FN + _K0 * _AA * x


def from_2180(east, north):
    """(lat, lon) of an EPSG:2180 point."""
    xi = (north - _FN) / (_K0 * _AA)
    eta = (east - _FE) / (_K0 * _AA)
    x, y = xi, eta
    for j, b in enumerate(_BETA, 1):
        x -= b * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
        y -= b * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
    chi = math.asin(math.sin(x) / math.cosh(y))
    phi = chi
    for j, d in enumerate(_DELTA, 1):
        phi += d * math.sin(2 * j * chi)
    lam = _LON0 + math.atan2(math.sinh(y), math.cos(x))
    return math.degrees(phi), math.degrees(lam)


# ---------------------------------------------------------------- fetching

def _download(url, path, refetch):
    if os.path.exists(path) and not refetch:
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for attempt in range(4):
        try:
            print('  fetching', url, flush=True)
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=900) as r, open(path + '.part', 'wb') as f:
                while True:
                    block = r.read(1 << 20)
                    if not block:
                        break
                    f.write(block)
            os.replace(path + '.part', path)
            return path
        except Exception as err:
            print('  retry', attempt, err, flush=True)
            time.sleep(10 + attempt * 20)
    raise SystemExit('download failed: ' + url)


def _get(url):
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers=UA)
            return urllib.request.urlopen(req, timeout=60).read().decode('utf-8', 'replace')
        except Exception as err:
            print('  retry', attempt, err, flush=True)
            time.sleep(5 + attempt * 10)
    raise SystemExit('request failed: ' + url)


# ---------------------------------------------------------------- CityGML

_NS = {'bldg': 'http://www.opengis.net/citygml/building/2.0', 'gml': 'http://www.opengis.net/gml',
       'gen': 'http://www.opengis.net/citygml/generics/2.0'}
_B = '{%s}' % _NS['bldg']
_G = '{%s}' % _NS['gml']
_GEN = '{%s}' % _NS['gen']


def _parser():
    # expat without DTD or external entity handling: CityGML needs neither
    p = ET.XMLPullParser(events=('end',))
    return p


def _rings_3d(el):
    """Every gml:LinearRing under el as a list of (e, n, z), closing point dropped."""
    out = []
    for lr in el.iter(_G + 'LinearRing'):
        pts = []
        for pos in lr.iter(_G + 'pos'):
            v = pos.text.split()
            pts.append((float(v[0]), float(v[1]), float(v[2])))
        pl = lr.find(_G + 'posList')
        if pl is not None:
            v = [float(t) for t in pl.text.split()]
            pts += [(v[i], v[i + 1], v[i + 2]) for i in range(0, len(v) - 2, 3)]
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts.pop()
        if len(pts) >= 3:
            out.append(pts)
    return out


def _attrs(bld):
    a = {}
    for s in bld.iter(_GEN + 'stringAttribute'):
        v = s.find(_GEN + 'value')
        a[s.get('name')] = v.text if v is not None else None
    for s in bld.iter(_GEN + 'doubleAttribute'):
        v = s.find(_GEN + 'value')
        try:
            a[s.get('name')] = float(v.text)
        except (TypeError, ValueError, AttributeError):
            pass
    for tag in ('roofType', 'measuredHeight', 'function', 'storeysAboveGround'):
        v = bld.find(_B + tag)
        if v is not None and v.text:
            a[tag] = v.text.strip()
    return a


def _envelope(head):
    """(e0, n0, e1, n1) from the gml:Envelope at the top of a CityGML file."""
    import re
    m = re.search(rb'lowerCorner>([-\d. ]+)<.*?upperCorner>([-\d. ]+)<', head, re.S)
    if not m:
        return None
    lo = [float(v) for v in m.group(1).split()]
    hi = [float(v) for v in m.group(2).split()]
    return lo[0], lo[1], hi[0], hi[1]


def iter_citygml(zpath, box):
    """Yields (attrs, ground rings, wall rings, roof rings) of every bldg:Building in a zip whose files'
    envelopes overlap box (e0, n0, e1, n1)."""
    z = zipfile.ZipFile(zpath)
    for name in z.namelist():
        if not name.lower().endswith('.gml'):
            continue
        with z.open(name) as f:
            env = _envelope(f.read(4096))
        if env and (env[2] < box[0] or env[0] > box[2] or env[3] < box[1] or env[1] > box[3]):
            continue
        p = _parser()
        with z.open(name) as f:
            while True:
                block = f.read(1 << 20)
                if not block:
                    break
                p.feed(block)
                for _, el in p.read_events():
                    if el.tag != _B + 'Building':
                        continue
                    ground, walls, roofs = [], [], []
                    for kind, dst in (('GroundSurface', ground), ('WallSurface', walls), ('RoofSurface', roofs)):
                        for s in el.iter(_B + kind):
                            dst += _rings_3d(s)
                    if not ground and not roofs:
                        # LoD1: a solid only, the footprint is its lowest ring
                        rings = _rings_3d(el)
                        if rings:
                            zmin = min(min(p[2] for p in r) for r in rings)
                            zmax = max(max(p[2] for p in r) for r in rings)
                            ground = [r for r in rings if max(p[2] for p in r) - zmin < 0.01][:1]
                            roofs = [r for r in rings if min(p[2] for p in r) > zmax - 0.01][:1]
                    yield _attrs(el), ground, walls, roofs
                    el.clear()
        p.close()


# ---------------------------------------------------------------- BDOT10k

def _wkb_rings(blob):
    """Outer rings of a GeoPackage geometry blob (Polygon / MultiPolygon WKB, 2D or Z) as [(e, n), ...]."""
    if blob[:2] != b'GP':
        return []
    flags = blob[3]
    env = (flags >> 1) & 7
    off = 8 + {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}.get(env, 0)
    out = []

    def geom(o):
        bo = '<' if blob[o] == 1 else '>'
        t = struct.unpack_from(bo + 'I', blob, o + 1)[0]
        o += 5
        dims = 3 if (t // 1000 in (1, 2) or t & 0x80000000) else 2
        if t // 1000 == 3:
            dims = 4
        base = (t & 0xffff) % 1000
        if base == 3:
            nr = struct.unpack_from(bo + 'I', blob, o)[0]
            o += 4
            for k in range(nr):
                n = struct.unpack_from(bo + 'I', blob, o)[0]
                o += 4
                pts = [struct.unpack_from(bo + 'dd', blob, o + i * 8 * dims) for i in range(n)]
                o += n * 8 * dims
                if k == 0:
                    out.append(pts[:-1] if pts and pts[0] == pts[-1] else pts)
            return o
        if base == 6:
            n = struct.unpack_from(bo + 'I', blob, o)[0]
            o += 4
            for _ in range(n):
                o = geom(o)
            return o
        return o

    try:
        geom(off)
    except struct.error:
        return []
    return out


def iter_bdot(zpath, box):
    """Yields (attrs, footprint) of every BUBD_A building in a BDOT10k GeoPackage zip inside box."""
    z = zipfile.ZipFile(zpath)
    names = [n for n in z.namelist() if n.lower().endswith('.gpkg') and 'BUBD_A' in n.upper()]
    for name in names:
        dst = os.path.join(RAW, 'bdot_' + os.path.basename(name))
        if not os.path.exists(dst):
            with z.open(name) as f, open(dst, 'wb') as g:
                while True:
                    block = f.read(1 << 20)
                    if not block:
                        break
                    g.write(block)
        con = sqlite3.connect('file:' + dst + '?mode=ro', uri=True)
        tables = [r[0] for r in con.execute("select table_name from gpkg_contents where data_type='features'")]
        for tname in tables:
            cols = [r[1] for r in con.execute(f'pragma table_info("{tname}")')]
            gcol = con.execute('select column_name from gpkg_geometry_columns where table_name=?', (tname,)).fetchone()[0]
            want = [c for c in cols if c.lower() in ('lokalnyid', 'kodkst', 'liczbakondygnacji', 'kategoriaistnienia',
                                                     'przewazajacafunkcjabudynku')]
            q = f'select {",".join(chr(34) + c + chr(34) for c in want)}, "{gcol}" from "{tname}"'
            for row in con.execute(q):
                rings = _wkb_rings(row[-1]) if row[-1] else []
                if not rings:
                    continue
                r = rings[0]
                e0 = min(p[0] for p in r)
                n0 = min(p[1] for p in r)
                if e0 > box[2] or n0 > box[3] or max(p[0] for p in r) < box[0] or max(p[1] for p in r) < box[1]:
                    continue
                yield {c.lower(): v for c, v in zip(want, row[:-1])}, r
        con.close()


# ---------------------------------------------------------------- orthophoto

def orto_sheets(box_ll, refetch):
    """[(e0, n0, e1, n1, path)] the newest RGB orthophoto sheet (GeoTIFF, 0.25 m) of every map section in the
    box, found through the orthophoto index WMS (one GetFeatureInfo lookup per ~1 km; the index lists the
    download link of each sheet) and downloaded from opendata.geoportal.gov.pl."""
    import re
    path = os.path.join(RAW, 'orto_index.json')
    if refetch or not os.path.exists(path):
        s, w, n, e = box_ll
        found = {}
        steps_y = int((n - s) / 0.009) + 2
        steps_x = int((e - w) / 0.014) + 2
        for i in range(steps_y):
            for j in range(steps_x):
                lat = s + (n - s) * i / (steps_y - 1)
                lon = w + (e - w) * j / (steps_x - 1)
                for layer in ORTO_LAYERS:
                    q = (f'{ORTO_INDEX}?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetFeatureInfo&LAYERS={layer}&QUERY_LAYERS={layer}'
                         f'&SRS=EPSG:4326&BBOX={lon - 0.0005},{lat - 0.0005},{lon + 0.0005},{lat + 0.0005}'
                         f'&WIDTH=11&HEIGHT=11&X=5&Y=5&INFO_FORMAT=text/html&STYLES=&FEATURE_COUNT=10')
                    text = _get(q)
                    hits = []
                    for m in re.finditer(r'push\(\{url:"(https://opendata\.geoportal\.gov\.pl/ortofotomapa/[^"]+\.tif)",'
                                         r'godlo:"([^"]+)",\s*aktualnosc:"([^"]+)".*?kolor:"([A-Z]+)"', text):
                        if m.group(4) == 'RGB':
                            hits.append((m.group(3), m.group(2), m.group(1)))
                    if hits:
                        for date, godlo, url in hits:
                            if godlo not in found or found[godlo][0] < date:
                                found[godlo] = (date, url)
                        break
                    time.sleep(0.2)
        json.dump(found, open(path, 'w'), indent=1)
    found = json.load(open(path))
    out = []
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    for godlo, (date, url) in sorted(found.items()):
        tif = _download(url, os.path.join(RAW, 'orto', os.path.basename(url)), refetch)
        im = Image.open(tif)
        tie = im.tag_v2.get(33922)
        scale = im.tag_v2.get(33550)
        if not tie or not scale:
            continue
        e0, n1 = tie[3], tie[4]
        out.append((e0, n1 - im.size[1] * scale[1], e0 + im.size[0] * scale[0], n1, tif, scale[0], date))
    return out


def sample_roof_colours(lod2, lod1, bdot, box_ll, local_proj, refetch):
    """{'cols': [[x, y, r, g, b] ...], 'dates': [...]}: the orthophoto's median colour inside every footprint
    (shrunk away from its edges, where the walls lean in and the eaves cast shadows), keyed by the footprint's
    centroid in local metres."""
    from PIL import Image, ImageDraw, ImageFilter
    Image.MAX_IMAGE_PIXELS = None
    sheets = orto_sheets(box_ll, refetch)
    rings = [r['ring'] for r in lod2] + [r['ring'] for r in lod1] + [r['ring'] for r in bdot]
    seen = set()
    by_sheet = {}
    for ring in rings:
        cx = sum(p[0] for p in ring) / len(ring)
        cy = sum(p[1] for p in ring) / len(ring)
        k = (round(cx), round(cy))
        if k in seen:
            continue
        seen.add(k)
        en = [to_2180(*_unlocal(local_proj, p[0], p[1])) for p in ring]
        ce = sum(p[0] for p in en) / len(en)
        cn = sum(p[1] for p in en) / len(en)
        best = None
        for i, t in enumerate(sheets):
            if t[0] <= ce < t[2] and t[1] <= cn < t[3] and (best is None or t[6] > sheets[best][6]):
                best = i
        if best is not None:
            by_sheet.setdefault(best, []).append((cx, cy, en))
    cols = []
    for i, items in sorted(by_sheet.items()):
        t = sheets[i]
        img = Image.open(t[4]).convert('RGB')
        img = img.reduce(2)  # 0.5 m is plenty for a roof's mean colour, and a quarter of the memory
        res = t[5] * 2
        px = img.load()
        W, H = img.size
        for cx, cy, en in items:
            pts = [((p[0] - t[0]) / res, (t[3] - p[1]) / res) for p in en]
            x0 = max(0, int(min(p[0] for p in pts)) - 1)
            y0 = max(0, int(min(p[1] for p in pts)) - 1)
            x1 = min(W - 1, int(max(p[0] for p in pts)) + 2)
            y1 = min(H - 1, int(max(p[1] for p in pts)) + 2)
            if x1 - x0 < 3 or y1 - y0 < 3:
                continue
            mask = Image.new('L', (x1 - x0 + 1, y1 - y0 + 1), 0)
            ImageDraw.Draw(mask).polygon([(p[0] - x0, p[1] - y0) for p in pts], fill=255)
            if mask.size[0] > 8 and mask.size[1] > 8:
                mask = mask.filter(ImageFilter.MinFilter(3))
            m = mask.load()
            rs, gs, bs_ = [], [], []
            for yy in range(y0, y1 + 1):
                for xx in range(x0, x1 + 1):
                    if m[xx - x0, yy - y0]:
                        c = px[xx, yy]
                        rs.append(c[0])
                        gs.append(c[1])
                        bs_.append(c[2])
            if len(rs) < 4:
                continue
            rs.sort()
            gs.sort()
            bs_.sort()
            k = len(rs) // 2
            cols.append([round(cx, 1), round(cy, 1), rs[k], gs[k], bs_[k]])
        img.close()
        print(f'  orthophoto {os.path.basename(t[4])}: {len(cols)} roof colours so far', flush=True)
    return {'cols': cols, 'dates': sorted({t[6] for t in sheets})}


# ---------------------------------------------------------------- extract

def _area(r):
    a = 0.0
    for i in range(len(r)):
        x0, y0 = r[i][0], r[i][1]
        x1, y1 = r[(i + 1) % len(r)][0], r[(i + 1) % len(r)][1]
        a += x0 * y1 - x1 * y0
    return a * 0.5


def _inside(ring, box):
    e = sum(p[0] for p in ring) / len(ring)
    n = sum(p[1] for p in ring) / len(ring)
    return box[0] <= e <= box[2] and box[1] <= n <= box[3]


def extract(local_proj, box_ll, out_path, refetch=False, orto=True):
    """Writes the compact extract for the box (s, w, n, e in degrees): local_proj(lat, lon) -> (x, y)."""
    s, w, n, e = box_ll
    corners = [to_2180(lat, lon) for lat in (s, n) for lon in (w, e)]
    box = (min(c[0] for c in corners), min(c[1] for c in corners), max(c[0] for c in corners), max(c[1] for c in corners))

    def loc(en):
        lat, lon = from_2180(en[0], en[1])
        x, y = local_proj(lat, lon)
        return [round(x, 2), round(y, 2)]

    lod2, lod1, bdot = [], [], []
    for woj, t in POWIATS:
        zp = _download(LOD2_URL.format(t=t), os.path.join(RAW, f'lod2_{t}.zip'), refetch)
        for a, ground, walls, roofs in iter_citygml(zp, box):
            if not ground or not _inside(ground[0], box):
                continue
            g = max(ground, key=lambda r: abs(_area(r)))
            gz = min(p[2] for p in g)
            rec = {'id': a.get('buildingId'), 'rt': int(a.get('roofType') or 0), 'z': round(gz, 2),
                   'ring': [loc(p) for p in g],
                   'roofs': [[v for p in r for v in loc(p) + [round(p[2] - gz, 2)]] for r in roofs]}
            if a.get('aktZrodla'):
                rec['yr'] = a['aktZrodla']
            lod2.append(rec)
        print(f'  LoD2 {t}: {len(lod2)} buildings so far', flush=True)
        zp = _download(LOD1_URL.format(w=woj, t=t), os.path.join(RAW, f'lod1_2024_{t}.zip'), refetch)
        for a, ground, walls, roofs in iter_citygml(zp, box):
            if not ground or not _inside(ground[0], box):
                continue
            g = ground[0]
            gz = min(p[2] for p in g)
            top = max(max(p[2] for p in r) for r in roofs) if roofs else None
            h = a.get('measuredHeight')
            try:
                h = float(h) if h is not None else (top - gz if top is not None else None)
            except ValueError:
                h = None
            if h is None:
                continue
            lod1.append({'id': a.get('buildingId'), 'h': round(h, 2), 'ring': [loc(p) for p in g]})
        print(f'  LoD1 2024 {t}: {len(lod1)} buildings so far', flush=True)
        zp = _download(BDOT_URL.format(w=woj, t=t), os.path.join(RAW, f'bdot_{t}.zip'), refetch)
        for a, r in iter_bdot(zp, box):
            rec = {'ring': [loc(p) for p in r]}
            for k_in, k_out in (('lokalnyid', 'id'), ('kodkst', 'f'), ('przewazajacafunkcjabudynku', 'pf'),
                                ('liczbakondygnacji', 'lk'), ('kategoriaistnienia', 'ki')):
                if a.get(k_in) not in (None, ''):
                    rec[k_out] = a[k_in]
            bdot.append(rec)
        print(f'  BDOT10k {t}: {len(bdot)} buildings so far', flush=True)
    out = {'source': 'GUGiK: Modele 3D budynków LoD2 (2017), LoD1 (2024), BDOT10k BUBD_A; ortofotomapa',
           'box2180': [round(v, 1) for v in box], 'lod2': lod2, 'lod1': lod1, 'bdot': bdot}
    if orto:
        out['orto'] = sample_roof_colours(lod2, lod1, bdot, box_ll, local_proj, refetch)
    json.dump(out, open(out_path, 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
    print('wrote', out_path, os.path.getsize(out_path) // 1024, 'KB', flush=True)


def _unlocal(local_proj, x, y):
    """(lat, lon) of local metres, by Newton steps on local_proj (an equirectangular projection here)."""
    lat, lon = 50.0, 19.15
    for _ in range(3):
        px, py = local_proj(lat, lon)
        qx, _ = local_proj(lat, lon + 1e-3)
        _, qy = local_proj(lat + 1e-3, lon)
        lon += (x - px) / ((qx - px) / 1e-3)
        lat += (y - py) / ((qy - py) / 1e-3)
    return lat, lon


if __name__ == '__main__':
    sys.path.insert(0, HERE)
    import build_open_world as bow
    path = os.path.join(CACHE, bow.KEY + '_gugik.json')
    extract(bow.proj, bow.box(bow.FETCH_MARGIN), path, refetch='--refetch' in sys.argv, orto='--no-orto' not in sys.argv)
