"""Build low-poly, hand-modelled Brzeszcze landmarks. Run with Blender from the repo root:

  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_brzeszcze.py -- --renders /tmp/gfx/L/renders

Faithful architectural reconstructions based on official heritage registers (NID / zabytek.pl A-81 for św. Marcin,
A-71/M for św. Urban), GUGiK LoD2 3D building measurements, archive photographs from fotopolska.eu, polska-org.pl,
and Wikimedia Commons.
Origins are centred on the footprint and on the ground; front is Godot -Z (Blender +Y).
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit
from kit import MB, srgb, Vector

OUT = os.path.join(kit.ROOT, "godot", "models", "brzeszcze_landmarks.glb")

kit.MATERIALS.update({
    "Stone": (srgb("#76736d"), .88, 0, {}),
    "Brick": (srgb("#9c4836"), .88, 0, {}),
    "Roof": (srgb("#363a3c"), .8, 0, {}),
    "Wood": (srgb("#453325"), .92, 0, {}),
    "Timber": (srgb("#36281e"), .92, 0, {}),
    "Shingle": (srgb("#2a2119"), .95, 0, {}),
    "Steel": (srgb("#525d62"), .55, .4, {}),
    "Glass": (srgb("#3c4c54"), .2, .15, {}),
    "Trim": (srgb("#f2ede2"), .82, 0, {}),
    "Plaster": (srgb("#dfd1b8"), .88, 0, {}),
    "Copper": (srgb("#4b6e62"), .75, 0, {}),
    "Gold": (srgb("#c89f46"), .4, .6, {}),
    "Concrete": (srgb("#98958e"), .88, 0, {}),
    "ConcreteTrim": (srgb("#bcbab3"), .82, 0, {}),
    "SignBlue": (srgb("#1c3b6f"), .8, 0, {}),
})

def box(m, lo, hi, mat, skip=()): m.box(lo, hi, mat, skip=skip)

def beam(m, a, b, w, mat, up=(0,0,1)):
    m.beam(a, b, w, w, mat, up=up)

def roof_y(m, x0, x1, y0, y1, eave, ridge, mat="Roof"):
    """Pitched gable roof where ridge runs along Y at x = (x0+x1)/2."""
    xm = (x0 + x1) * 0.5
    m.quad((x0, y0, eave), (xm, y0, ridge), (xm, y1, ridge), (x0, y1, eave), mat, (-1, 0, 1))
    m.quad((xm, y0, ridge), (x1, y0, eave), (x1, y1, eave), (xm, y1, ridge), mat, (1, 0, 1))
    m.poly([(x0, y0, eave), (x1, y0, eave), (xm, y0, ridge)], mat, (0, -1, 1))
    m.poly([(x0, y1, eave), (xm, y1, ridge), (x1, y1, eave)], mat, (0, 1, 1))

def roof_x(m, x0, x1, y0, y1, eave, ridge, mat="Roof"):
    """Pitched gable roof where ridge runs along X at y = (y0+y1)/2."""
    ym = (y0 + y1) * 0.5
    m.quad((x0, y0, eave), (x1, y0, eave), (x1, ym, ridge), (x0, ym, ridge), mat, (0, -1, 1))
    m.quad((x0, ym, ridge), (x1, ym, ridge), (x1, y1, eave), (x0, y1, eave), mat, (0, 1, 1))
    m.poly([(x0, y0, eave), (x0, ym, ridge), (x0, y1, eave)], mat, (-1, 0, 1))
    m.poly([(x1, y0, eave), (x1, y1, eave), (x1, ym, ridge)], mat, (1, 0, 1))

def cross(m, centre, height, span, width, mat="Gold"):
    cx, cy, cz = centre
    beam(m, (cx, cy, cz), (cx, cy, cz + height), width, mat)
    beam(m, (cx - span*0.5, cy, cz + height*0.68), (cx + span*0.5, cy, cz + height*0.68), width, mat)

def disc(m, centre, radius, normal, mat, segs=8):
    norm = Vector(normal).normalized()
    up = Vector((0, 0, 1)) if abs(norm.z) < 0.9 else Vector((1, 0, 0))
    u = norm.cross(up).normalized()
    v = u.cross(norm).normalized()
    pts = [Vector(centre) + (u * math.cos(2*math.pi*k/segs) + v * math.sin(2*math.pi*k/segs)) * radius for k in range(segs)]
    m.poly(pts, mat, norm)

def wheel_x(m, cx, cy, cz, radius, width, mat="Steel", segs=16):
    """Cylindrical wheel with rim along X axis."""
    x0 = cx - width * 0.5
    x1 = cx + width * 0.5
    r0 = [Vector((x0, cy + radius * math.cos(2*math.pi*k/segs), cz + radius * math.sin(2*math.pi*k/segs))) for k in range(segs)]
    r1 = [Vector((x1, cy + radius * math.cos(2*math.pi*k/segs), cz + radius * math.sin(2*math.pi*k/segs))) for k in range(segs)]
    for k in range(segs):
        k2 = (k + 1) % segs
        m.poly([r0[k], r0[k2], r1[k2], r1[k]], mat, lambda q: Vector((0, q.y - cy, q.z - cz)))
    # Hub cylinder
    rhub = radius * 0.22
    h0 = [Vector((cx - width*0.7, cy + rhub * math.cos(2*math.pi*k/10), cz + rhub * math.sin(2*math.pi*k/10))) for k in range(10)]
    h1 = [Vector((cx + width*0.7, cy + rhub * math.cos(2*math.pi*k/10), cz + rhub * math.sin(2*math.pi*k/10))) for k in range(10)]
    for k in range(10):
        k2 = (k + 1) % 10
        m.poly([h0[k], h0[k2], h1[k2], h1[k]], mat, lambda q: Vector((0, q.y - cy, q.z - cz)))
    m.poly(h0, mat, (-1, 0, 0))
    m.poly(h1, mat, (1, 0, 0))
    # Spokes
    for k in range(6):
        ang = k * math.pi / 6.0
        p_a = (cx, cy + radius * 0.95 * math.cos(ang), cz + radius * 0.95 * math.sin(ang))
        p_b = (cx, cy - radius * 0.95 * math.cos(ang), cz - radius * 0.95 * math.sin(ang))
        m.beam(p_a, p_b, 0.08, 0.08, mat)

def urban():
    """Kościół św. Urbana w Brzeszczach (neobarok, 1874-1876, rejestr zabytków A-71/M)."""
    m = MB()
    # 1. Stone plinth (cokół)
    box(m, (-10.0, -21.0, 0.0), (10.0, 18.5, 1.2), "Stone")

    # 2. Main nave
    box(m, (-7.0, -14.0, 1.2), (7.0, 11.0, 13.0), "Plaster")
    roof_y(m, -7.6, 7.6, -14.2, 11.2, 13.0, 17.5, "Copper")

    # Nave pilasters and arched windows along long walls
    for side in (-1, 1):
        x = side * 7.0
        box(m, (x - 0.25 if side < 0 else x, -14.2, 12.6), (x if side < 0 else x + 0.25, 11.2, 13.1), "Trim")
        for y in (-11.5, -7.0, -2.5, 2.0, 6.5):
            box(m, (x - 0.08 if side < 0 else x - 0.04, y - 0.75, 4.5), (x + 0.04 if side < 0 else x + 0.08, y + 0.75, 10.5), "Glass")
            box(m, (x - 0.16 if side < 0 else x - 0.04, y - 0.9, 4.1), (x + 0.04 if side < 0 else x + 0.16, y + 0.9, 4.5), "Trim")
            box(m, (x - 0.16 if side < 0 else x - 0.04, y - 0.9, 10.5), (x + 0.04 if side < 0 else x + 0.16, y + 0.9, 11.1), "Trim")
        for y in (-14.0, -9.2, -4.7, -0.2, 4.3, 8.8):
            box(m, (x - 0.22 if side < 0 else x, y - 0.28, 1.2), (x if side < 0 else x + 0.22, y + 0.28, 12.8), "Trim")

    # 3. Transept side chapels (Kaplica Ukrzyżowanego / zakrystia)
    box(m, (-10.2, 1.0, 1.2), (10.2, 9.0, 11.5), "Plaster")
    roof_x(m, -10.5, -6.8, 0.8, 9.2, 11.5, 14.8, "Copper")
    roof_x(m, 6.8, 10.5, 0.8, 9.2, 11.5, 14.8, "Copper")
    for side in (-1, 1):
        x = side * 10.2
        box(m, (x - 0.08 if side < 0 else x - 0.04, 3.8, 4.5), (x + 0.04 if side < 0 else x + 0.08, 6.2, 9.8), "Glass")
        box(m, (x - 0.18 if side < 0 else x - 0.04, 3.6, 4.1), (x + 0.04 if side < 0 else x + 0.18, 6.4, 4.5), "Trim")
        box(m, (x - 0.18 if side < 0 else x - 0.04, 3.6, 9.8), (x + 0.04 if side < 0 else x + 0.18, 6.4, 10.3), "Trim")
        box(m, (x - 0.2 if side < 0 else x, 1.0, 1.2), (x if side < 0 else x + 0.2, 1.5, 11.5), "Trim")
        box(m, (x - 0.2 if side < 0 else x, 8.5, 1.2), (x if side < 0 else x + 0.2, 9.0, 11.5), "Trim")

    # 4. Prezbiterium (Chancel & Apse)
    box(m, (-5.2, 11.0, 1.2), (5.2, 16.5, 10.5), "Plaster")
    roof_y(m, -5.5, 5.5, 10.8, 16.8, 10.5, 14.2, "Copper")
    m.poly([(-5.2, 16.5, 1.2), (5.2, 16.5, 1.2), (3.6, 19.5, 1.2), (-3.6, 19.5, 1.2)], "Stone", (0, 0, -1))
    box(m, (-3.6, 16.5, 1.2), (3.6, 19.5, 10.5), "Plaster")
    m.poly([(-5.2, 16.5, 10.5), (0.0, 16.5, 14.2), (0.0, 18.0, 13.0), (-3.6, 19.5, 10.5)], "Copper", (-1, 1, 1))
    m.poly([(5.2, 16.5, 10.5), (3.6, 19.5, 10.5), (0.0, 18.0, 13.0), (0.0, 16.5, 14.2)], "Copper", (1, 1, 1))
    m.poly([(-3.6, 19.5, 10.5), (0.0, 18.0, 13.0), (3.6, 19.5, 10.5)], "Copper", (0, 1, 1))

    # 5. Western Tower & Vestibule Complex
    for side in (-1, 1):
        x0 = 4.0 if side > 0 else -9.5
        x1 = 9.5 if side > 0 else -4.0
        box(m, (x0, -19.5, 1.2), (x1, -14.0, 11.8), "Plaster")
        m.quad((x0, -19.6, 11.8), (x1, -19.6, 11.8), (x1, -14.0, 12.5), (x0, -14.0, 12.5), "Copper", (0, -1, 1))
        xm = (x0 + x1) * 0.5
        box(m, (xm - 0.7, -19.6, 4.0), (xm + 0.7, -19.45, 8.5), "Glass")
        box(m, (xm - 0.85, -19.65, 3.6), (xm + 0.85, -19.45, 4.0), "Trim")
        box(m, (xm - 0.85, -19.65, 8.5), (xm + 0.85, -19.45, 9.0), "Trim")

    box(m, (-4.0, -21.2, 1.2), (4.0, -14.0, 13.5), "Plaster")
    box(m, (-4.3, -21.5, 13.3), (4.3, -13.7, 14.1), "Trim")

    # Portal
    box(m, (-2.5, -21.7, 1.2), (2.5, -21.2, 6.5), "Trim")
    box(m, (-1.5, -21.75, 1.2), (1.5, -21.2, 5.2), "Wood")
    m.poly([(-2.6, -21.7, 6.5), (2.6, -21.7, 6.5), (0.0, -21.7, 7.8)], "Trim", (0, -1, 0))
    m.quad((-2.7, -21.75, 6.5), (0.0, -21.75, 7.9), (0.0, -21.2, 7.9), (-2.7, -21.2, 6.5), "Copper", (-1, -1, 1))
    m.quad((0.0, -21.75, 7.9), (2.7, -21.75, 6.5), (2.7, -21.2, 6.5), (0.0, -21.2, 7.9), "Copper", (1, -1, 1))

    # Tower Middle Stage (Clock stage Z=14.0 to 22.0)
    box(m, (-3.8, -21.0, 14.0), (3.8, -14.2, 22.0), "Plaster")
    for x in (-3.8, 3.4):
        for y in (-21.0, -14.6):
            box(m, (x, y, 14.0), (x + 0.4, y + 0.4, 22.0), "Trim")
    # Clock faces
    for fx, fy, nx, ny in [(0.0, -21.0, 0, -1), (-3.8, -17.6, -1, 0), (3.8, -17.6, 1, 0)]:
        disc(m, (fx + nx*0.04, fy + ny*0.04, 18.0), 1.15, (nx, ny, 0), "Trim", segs=12)
        disc(m, (fx + nx*0.07, fy + ny*0.07, 18.0), 0.95, (nx, ny, 0), "Glass", segs=12)

    box(m, (-4.1, -21.3, 21.8), (4.1, -13.9, 22.6), "Trim")

    # Tower Belfry Stage (Z=22.5 to 27.5) with arched openings
    box(m, (-3.7, -20.9, 22.5), (3.7, -14.3, 27.5), "Plaster")
    for x in (-3.7, 3.3):
        for y in (-20.9, -14.7):
            box(m, (x, y, 22.5), (x + 0.4, y + 0.4, 27.5), "Trim")
    box(m, (-1.2, -21.05, 23.6), (1.2, -20.85, 26.6), "Glass")
    box(m, (-1.4, -21.1, 23.4), (1.4, -20.85, 26.8), "Trim")
    box(m, (-1.2, -14.35, 23.6), (1.2, -14.15, 26.6), "Glass")
    box(m, (-1.4, -14.35, 23.4), (1.4, -14.1, 26.8), "Trim")
    box(m, (-3.85, -18.8, 23.6), (-3.65, -16.4, 26.6), "Glass")
    box(m, (-3.9, -19.0, 23.4), (-3.65, -16.2, 26.8), "Trim")
    box(m, (3.65, -18.8, 23.6), (3.85, -16.4, 26.6), "Glass")
    box(m, (3.65, -19.0, 23.4), (3.9, -16.2, 26.8), "Trim")

    box(m, (-4.2, -21.4, 27.3), (4.2, -13.8, 28.2), "Trim")

    # 6. Neo-Baroque Bulbous Helm
    tc = (0.0, -17.6, 0.0)
    m.lathe([(28.2, 3.8), (28.6, 3.9), (29.5, 4.1), (30.4, 3.6), (31.2, 2.3), (31.8, 1.7)], 16, "Copper", centre=tc)
    box(m, (-1.6, -19.2, 31.8), (1.6, -16.0, 32.2), "Trim")
    box(m, (-1.6, -19.2, 34.2), (1.6, -16.0, 34.6), "Trim")
    for k in range(6):
        ang = k * math.pi / 3.0
        lx = tc[0] + 1.45 * math.cos(ang)
        ly = tc[1] + 1.45 * math.sin(ang)
        beam(m, (lx, ly, 32.0), (lx, ly, 34.4), 0.22, "Trim")
    box(m, (-0.8, -18.4, 32.2), (0.8, -16.8, 34.2), "Glass")
    m.lathe([(34.4, 1.9), (34.8, 2.0), (35.5, 1.6), (36.2, 0.8), (36.9, 0.25)], 12, "Copper", centre=tc)
    m.lathe([(36.9, 0.15), (37.2, 0.35), (37.5, 0.15)], 8, "Gold", centre=tc)
    cross(m, (0.0, -17.6, 37.4), 1.6, 1.1, 0.12, "Gold")

    # 7. Nave Flèche (Sygnaturka) near presbytery
    sc = (0.0, 8.5, 0.0)
    m.lathe([(17.5, 1.0), (18.2, 0.9), (19.8, 0.9)], 8, "Trim", centre=sc)
    box(m, (-0.4, 8.1, 18.5), (0.4, 8.9, 19.6), "Glass")
    m.lathe([(19.8, 1.1), (20.5, 1.2), (21.2, 0.8), (21.9, 0.18)], 8, "Copper", centre=sc)
    cross(m, (0.0, 8.5, 21.9), 1.0, 0.7, 0.08, "Gold")

    return m

def martin():
    """Kościół św. Marcina w Jawiszowicach (1692, rejestr zabytków A-81, Szlak Architektury Drewnianej)."""
    m = MB()
    # 1. Low stone foundation pads under logs
    box(m, (-8.2, -18.5, 0.0), (8.2, 17.5, 0.5), "Stone")

    # 2. Enclosed soboty (podcienia) around church
    box(m, (-8.0, -11.0, 0.4), (-5.2, 17.2, 2.6), "Wood")
    box(m, (5.2, -11.0, 0.4), (8.0, 17.2, 2.6), "Wood")
    box(m, (-5.5, 14.5, 0.4), (5.5, 17.2, 2.6), "Wood")
    m.quad((-8.2, -11.2, 2.5), (-5.2, -11.2, 4.6), (-5.2, 14.5, 4.6), (-8.2, 14.5, 2.5), "Shingle", (-1, 0, 1))
    m.quad((5.2, -11.2, 4.6), (8.2, -11.2, 2.5), (8.2, 14.5, 2.5), (5.2, 14.5, 4.6), "Shingle", (1, 0, 1))
    m.quad((-8.2, 14.5, 2.5), (-5.2, 14.5, 4.6), (0.0, 17.5, 4.6), (-4.2, 17.5, 2.5), "Shingle", (-1, 1, 1))
    m.quad((5.2, 14.5, 4.6), (8.2, 14.5, 2.5), (4.2, 17.5, 2.5), (0.0, 17.5, 4.6), "Shingle", (1, 1, 1))
    for side in (-1, 1):
        x = side * 8.05
        for y in (-8.0, -4.0, 0.0, 4.0, 8.0, 12.0):
            box(m, (x - 0.05 if side < 0 else x - 0.02, y - 0.4, 1.2), (x + 0.02 if side < 0 else x + 0.05, y + 0.4, 1.9), "Glass")

    # 3. Main Nave
    box(m, (-5.2, -11.0, 0.5), (5.2, 8.0, 7.8), "Wood")
    roof_y(m, -6.6, 6.6, -11.2, 8.2, 7.5, 16.8, "Shingle")

    # 4. Chancel (Prezbiterium)
    box(m, (-4.0, 8.0, 0.5), (4.0, 14.0, 7.2), "Wood")
    roof_y(m, -4.8, 4.8, 8.0, 14.2, 7.0, 14.5, "Shingle")
    m.poly([(-4.0, 14.0, 0.5), (4.0, 14.0, 0.5), (2.8, 17.0, 0.5), (-2.8, 17.0, 0.5)], "Wood", (0, 0, -1))
    box(m, (-2.8, 14.0, 0.5), (2.8, 17.0, 7.2), "Wood")
    m.poly([(-4.8, 14.0, 7.0), (0.0, 14.0, 14.5), (0.0, 16.0, 11.5), (-3.2, 17.2, 7.0)], "Shingle", (-1, 1, 1))
    m.poly([(4.8, 14.0, 7.0), (3.2, 17.2, 7.0), (0.0, 16.0, 11.5), (0.0, 14.0, 14.5)], "Shingle", (1, 1, 1))
    m.poly([(-3.2, 17.2, 7.0), (0.0, 16.0, 11.5), (3.2, 17.2, 7.0)], "Shingle", (0, 1, 1))

    # 5. Western Izbica Tower
    b_base = [Vector((-4.3, -18.2, 0.5)), Vector((4.3, -18.2, 0.5)), Vector((4.3, -11.2, 0.5)), Vector((-4.3, -11.2, 0.5))]
    b_top = [Vector((-3.5, -17.2, 14.5)), Vector((3.5, -17.2, 14.5)), Vector((3.5, -12.2, 14.5)), Vector((-3.5, -12.2, 14.5))]
    for k in range(4):
        k2 = (k + 1) % 4
        m.poly([b_base[k], b_base[k2], b_top[k2], b_top[k]], "Wood")

    box(m, (-4.1, -17.8, 14.5), (4.1, -11.6, 17.8), "Timber")
    m.quad((-4.2, -18.0, 14.3), (4.2, -18.0, 14.3), (3.6, -17.3, 14.5), (-3.6, -17.3, 14.5), "Shingle", (0, -1, -1))
    m.quad((-4.2, -11.4, 14.3), (-3.6, -12.1, 14.5), (3.6, -12.1, 14.5), (4.2, -11.4, 14.3), "Shingle", (0, 1, -1))
    for fx, fy, w, d in [(0, -17.85, 1.4, 0.1), (0, -11.55, 1.4, 0.1), (-4.15, -14.7, 0.1, 1.4), (4.05, -14.7, 0.1, 1.4)]:
        box(m, (fx - w*0.5, fy - d*0.5, 15.3), (fx + w*0.5, fy + d*0.5, 17.2), "Glass")

    mc = (0.0, -14.7, 0.0)
    m.lathe([(17.8, 3.5), (18.3, 3.4), (19.2, 2.9), (20.0, 2.1), (20.6, 1.4)], 16, "Shingle", centre=mc)
    box(m, (-1.3, -16.0, 20.6), (1.3, -13.4, 21.8), "Timber")
    box(m, (-0.6, -16.05, 20.8), (0.6, -13.35, 21.6), "Glass")
    m.lathe([(21.8, 1.5), (22.2, 1.4), (22.7, 0.8), (23.2, 0.25)], 12, "Shingle", centre=mc)
    cross(m, (0.0, -14.7, 23.2), 0.9, 0.6, 0.08, "Timber")

    # 6. Ridge Sygnaturka over nave
    nc = (0.0, 2.0, 0.0)
    m.lathe([(16.8, 0.9), (17.5, 0.8), (18.6, 0.8)], 8, "Timber", centre=nc)
    box(m, (-0.35, 1.65, 17.4), (0.35, 2.35, 18.5), "Glass")
    m.lathe([(18.6, 1.0), (19.2, 0.9), (19.8, 0.5), (20.4, 0.15)], 8, "Shingle", centre=nc)
    cross(m, (0.0, 2.0, 20.4), 0.7, 0.5, 0.06, "Timber")

    return m

def station():
    """Dworzec kolejowy Brzeszcze-Jawiszowice (linia 93, II poł. XIX w., styl galicyjski)."""
    m = MB()
    # 1. Base stone plinth
    box(m, (-16.5, -6.5, 0.0), (16.5, 6.5, 0.8), "Stone")

    # 2. Central 2-storey block (X: -7.0 to 7.0, Y: -6.0 to 6.0, Z up to 7.4)
    box(m, (-7.0, -6.0, 0.8), (7.0, 6.0, 4.2), "Plaster")
    for x in (-7.0, 6.5):
        for y in (-6.0, 5.5):
            box(m, (x, y, 0.8), (x + 0.5, y + 0.5, 7.4), "Brick")
    box(m, (-7.2, -6.2, 4.2), (7.2, 6.2, 4.5), "Trim")
    box(m, (-7.0, -6.0, 4.5), (7.0, 6.0, 7.4), "Plaster")
    roof_x(m, -7.4, 7.4, -6.3, 6.3, 7.4, 9.8, "Roof")

    # Central transverse gables / pediments
    for y_sign in (-1, 1):
        y_pos = y_sign * 6.0
        yd = -0.25 if y_sign < 0 else 0.0
        m.poly([(-2.5, y_pos + yd, 7.4), (2.5, y_pos + yd, 7.4), (0.0, y_pos + yd, 9.4)], "Plaster", (0, y_sign, 0))
        m.beam((-2.6, y_pos + yd, 7.4), (0.0, y_pos + yd, 9.5), 0.25, 0.25, "Trim")
        m.beam((0.0, y_pos + yd, 9.5), (2.6, y_pos + yd, 7.4), 0.25, 0.25, "Trim")
        disc(m, (0.0, y_pos + yd + (0.02 if y_sign > 0 else -0.02), 8.35), 0.55, (0, y_sign, 0), "Trim", segs=8)
        disc(m, (0.0, y_pos + yd + (0.04 if y_sign > 0 else -0.04), 8.35), 0.42, (0, y_sign, 0), "Glass", segs=8)

    # 3. Side Wings (1-storey, X: -16.5 to -7.0 and 7.0 to 16.5)
    for x_side in (-1, 1):
        x0 = 7.0 if x_side > 0 else -16.5
        x1 = 16.5 if x_side > 0 else -7.0
        box(m, (x0, -5.5, 0.8), (x1, 5.5, 5.8), "Plaster")
        xe = x1 - 0.5 if x_side > 0 else x0
        for y in (-5.5, 5.0):
            box(m, (xe, y, 0.8), (xe + 0.5, y + 0.5, 5.8), "Brick")
        roof_x(m, x0 - 0.2, x1 + 0.2, -5.8, 5.8, 5.8, 7.8, "Roof")

    # 4. Platform Canopy / Veranda on +Y (Track side)
    box(m, (-11.0, 5.8, 3.6), (11.0, 8.2, 3.8), "Roof")
    for x in (-10.5, -7.0, -3.5, 0.0, 3.5, 7.0, 10.5):
        m.beam((x, 5.8, 2.6), (x, 7.8, 3.6), 0.15, 0.15, "Timber")
        m.beam((x, 7.8, 0.0), (x, 7.8, 3.6), 0.18, 0.18, "Timber")

    # 5. Windows and Doors
    for x in (-4.8, -2.4, 0.0, 2.4, 4.8):
        for y_sign in (-1, 1):
            y_pos = y_sign * 6.0
            yd = -0.06 if y_sign < 0 else 0.02
            is_door = (x == 0.0) or (abs(x) == 2.4 and y_sign > 0)
            if is_door:
                box(m, (x - 0.8, y_pos + yd, 0.8), (x + 0.8, y_pos + yd + 0.05, 3.6), "Wood")
            else:
                box(m, (x - 0.65, y_pos + yd, 1.4), (x + 0.65, y_pos + yd + 0.05, 3.4), "Glass")
                box(m, (x - 0.75, y_pos + yd - 0.05, 1.25), (x + 0.75, y_pos + yd + 0.08, 1.4), "Stone")
            box(m, (x - 0.85, y_pos + yd - 0.02, 3.4), (x + 0.85, y_pos + yd + 0.06, 3.8), "Brick")

    for x in (-4.8, -2.4, 0.0, 2.4, 4.8):
        for y_sign in (-1, 1):
            y_pos = y_sign * 6.0
            yd = -0.06 if y_sign < 0 else 0.02
            box(m, (x - 0.6, y_pos + yd, 5.0), (x + 0.6, y_pos + yd + 0.05, 6.7), "Glass")
            box(m, (x - 0.7, y_pos + yd - 0.05, 4.85), (x + 0.7, y_pos + yd + 0.08, 5.0), "Stone")
            box(m, (x - 0.75, y_pos + yd - 0.02, 6.7), (x + 0.75, y_pos + yd + 0.06, 7.0), "Brick")

    for x in (-14.0, -11.5, -9.0, 9.0, 11.5, 14.0):
        for y_sign in (-1, 1):
            y_pos = y_sign * 5.5
            yd = -0.06 if y_sign < 0 else 0.02
            box(m, (x - 0.6, y_pos + yd, 1.4), (x + 0.6, y_pos + yd + 0.05, 3.4), "Glass")
            box(m, (x - 0.7, y_pos + yd - 0.05, 1.25), (x + 0.7, y_pos + yd + 0.08, 1.4), "Stone")
            box(m, (x - 0.75, y_pos + yd - 0.02, 3.4), (x + 0.75, y_pos + yd + 0.06, 3.8), "Brick")

    # 6. Brick Chimneys on roof
    for cx in (-5.0, 5.0):
        for cy in (-2.0, 2.0):
            box(m, (cx - 0.45, cy - 0.45, 8.5), (cx + 0.45, cy + 0.45, 10.6), "Brick")
            box(m, (cx - 0.55, cy - 0.55, 10.6), (cx + 0.55, cy + 0.55, 10.8), "Stone")

    # 7. Station Sign Board: 'BRZESZCZE JAWISZOWICE'
    box(m, (-3.2, 6.08, 3.8), (3.2, 6.18, 4.4), "SignBlue")
    box(m, (-3.3, 6.06, 3.75), (3.3, 6.19, 3.82), "Trim")
    box(m, (-3.3, 6.06, 4.38), (3.3, 6.19, 4.45), "Trim")
    box(m, (-3.2, -6.18, 3.8), (3.2, -6.08, 4.4), "SignBlue")
    box(m, (-3.3, -6.19, 3.75), (3.3, -6.06, 3.82), "Trim")
    box(m, (-3.3, -6.19, 4.38), (3.3, -6.06, 4.45), "Trim")

    return m

def shaft(name):
    """KWK Brzeszcze shafts: Andrzej I (1903), Andrzej II (1905), Andrzej V (skip tower)."""
    m = MB()
    if name == "AndrzejV":
        box(m, (-4.5, -4.5, 0.0), (4.5, 4.5, 32.5), "Concrete")
        box(m, (-5.4, -5.4, 32.5), (5.4, 5.4, 40.5), "Concrete")
        box(m, (-5.5, -5.5, 40.5), (5.5, 5.5, 41.3), "ConcreteTrim", skip=("-z",))
        box(m, (-5.1, -5.1, 40.5), (5.1, 5.1, 40.7), "Steel")

        for z in (8.0, 16.0, 24.0, 32.5, 40.5):
            box(m, (-4.65, -4.65, z), (4.65, 4.65, z + 0.4), "ConcreteTrim")

        for z in range(6, 31, 4):
            for side in (-1, 1):
                box(m, (side * 2.2 - 0.35, -4.62, z), (side * 2.2 + 0.35, -4.48, z + 2.8), "Glass")
                box(m, (side * 2.2 - 0.35, 4.48, z), (side * 2.2 + 0.35, 4.62, z + 2.8), "Glass")
                box(m, (-4.62, side * 2.2 - 0.35, z), (-4.48, side * 2.2 + 0.35, z + 2.8), "Glass")
                box(m, (4.48, side * 2.2 - 0.35, z), (4.62, side * 2.2 + 0.35, z + 2.8), "Glass")

        for side in (-1, 1):
            box(m, (-3.5, side * 5.42 - 0.06 if side > 0 else -5.48, 35.0), (3.5, side * 5.48 if side > 0 else -5.42 + 0.06, 38.5), "Glass")
            box(m, (side * 5.42 - 0.06 if side > 0 else -5.48, -3.5, 35.0), (side * 5.48 if side > 0 else -5.42 + 0.06, 3.5, 38.5), "Glass")

        box(m, (-1.8, -4.7, 0.0), (1.8, -4.45, 5.5), "Steel")
        box(m, (-1.2, -4.75, 0.0), (1.2, -4.5, 4.5), "Glass")

    else:
        h = 27.5 if name == "AndrzejI" else 31.5
        w = 3.6

        for sx in (-1, 1):
            for sy in (-1, 1):
                box(m, (sx * w - 0.6, sy * w - 0.6, 0.0), (sx * w + 0.6, sy * w + 0.6, 1.2), "Concrete")
        for sx in (-1, 1):
            box(m, (sx * (w * 0.9) - 0.7, -10.5 - 0.7, 0.0), (sx * (w * 0.9) + 0.7, -10.5 + 0.7, 1.5), "Concrete")

        for sx in (-1, 1):
            for sy in (-1, 1):
                p0 = (sx * w, sy * w, 1.0)
                p1 = (sx * w * 0.7, sy * w * 0.7, h)
                m.beam(p0, p1, 0.38, 0.38, "Steel")

        num_stages = int(h // 4.5)
        for s in range(1, num_stages + 1):
            z = s * (h / (num_stages + 1))
            t = z / h
            ws = w * (1.0 - 0.3 * t)
            z_prev = (s - 1) * (h / (num_stages + 1))
            ws_prev = w * (1.0 - 0.3 * (z_prev / h))
            for sy in (-1, 1):
                m.beam((-ws, sy * ws, z), (ws, sy * ws, z), 0.22, 0.22, "Steel")
                if s > 0:
                    m.beam((-ws_prev, sy * ws_prev, z_prev), (ws, sy * ws, z), 0.16, 0.16, "Steel")
                    m.beam((ws_prev, sy * ws_prev, z_prev), (-ws, sy * ws, z), 0.16, 0.16, "Steel")
            for sx in (-1, 1):
                m.beam((sx * ws, -ws, z), (sx * ws, ws, z), 0.22, 0.22, "Steel")
                if s > 0:
                    m.beam((sx * ws_prev, -ws_prev, z_prev), (sx * ws, ws, z), 0.16, 0.16, "Steel")
                    m.beam((sx * ws_prev, ws_prev, z_prev), (sx * ws, -ws, z), 0.16, 0.16, "Steel")

        for sx in (-1, 1):
            p_anchor = (sx * (w * 0.9), -10.5, 1.2)
            p_top = (sx * (w * 0.65), -w * 0.65, h)
            m.beam(p_anchor, p_top, 0.45, 0.45, "Steel")
            for s in range(1, num_stages):
                z = s * (h / (num_stages + 1))
                t = z / h
                by = -10.5 + ((-w * 0.65) - (-10.5)) * t
                bx = sx * (w * 0.9 + (w * 0.65 - w * 0.9) * t)
                ty = -w * (1.0 - 0.3 * t)
                m.beam((bx, by, z), (bx, ty, z), 0.2, 0.2, "Steel")

        for s in range(1, num_stages):
            z0 = (s - 1) * (h / (num_stages + 1))
            z1 = s * (h / (num_stages + 1))
            t0, t1 = z0 / h, z1 / h
            y0 = -10.5 + ((-w * 0.65) - (-10.5)) * t0
            y1 = -10.5 + ((-w * 0.65) - (-10.5)) * t1
            x0 = w * 0.9 + (w * 0.65 - w * 0.9) * t0
            x1 = w * 0.9 + (w * 0.65 - w * 0.9) * t1
            m.beam((-x0, y0, z0), (x1, y1, z1), 0.16, 0.16, "Steel")
            m.beam((x0, y0, z0), (-x1, y1, z1), 0.16, 0.16, "Steel")

        box(m, (-w * 0.85, -w * 0.85, h), (w * 0.85, w * 0.85, h + 0.3), "Steel")
        box(m, (-w * 0.88, -w * 0.88, h + 0.3), (w * 0.88, w * 0.88, h + 1.2), "Steel", skip=("-z", "+z"))

        r_wheel = 2.1 if name == "AndrzejI" else 2.4
        for x_wheel in (-1.2, 1.2):
            wheel_x(m, x_wheel, 0.0, h + r_wheel + 0.4, r_wheel, 0.35, "Steel", segs=16)

    return m

PIECES = {
    "KosciolUrbana": urban,
    "KosciolMarcina": martin,
    "DworzecBrzeszcze": station,
    "AndrzejI": lambda: shaft("AndrzejI"),
    "AndrzejII": lambda: shaft("AndrzejII"),
    "AndrzejV": lambda: shaft("AndrzejV"),
}

def finish(m):
    lo = Vector((min(p.x for p in m.v), min(p.y for p in m.v), min(p.z for p in m.v)))
    hi = Vector((max(p.x for p in m.v), max(p.y for p in m.v), max(p.z for p in m.v)))
    m.v = [p + Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)) for p in m.v]
    return hi - lo

def main():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    objs = []
    total = 0
    for name, fn in PIECES.items():
        mb = fn()
        size = finish(mb)
        tris = mb.tris()
        total += tris
        ob = mb.emit(name)
        objs.append(ob)
        print(f"{name}: {size.x:.1f} x {size.y:.1f} x {size.z:.1f} m, {tris} tris")
    print(f"TOTAL: {total} tris")
    kit.export_glb(OUT, objs)
    out = kit.arg("--renders")
    if out:
        os.makedirs(out, exist_ok=True)
        for ob in objs:
            ob.hide_render = True
        for i, ob in enumerate(objs):
            kit.place(ob, ((i % 3) * 44, (i // 3) * 50, 0)).hide_render = False
        cam = kit.setup_preview(ground=180, ground_colour=(.15, .19, .13))
        kit.render(cam, os.path.join(out, "brzeszcze_landmarks.png"), (68, 115, 62), (44, 38, 15), 55)

if __name__ == "__main__":
    main()
