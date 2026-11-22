"""Shared car-modelling helpers for the Blender build scripts (build_seicento.py's generic parts, for cars after the Seicento).

    sys.path.insert(0, os.path.dirname(__file__))
    import carkit
    from carkit import MB, Projector, Curve, smoothstep, ...
    carkit.MATERIALS.update(MY_MATERIALS)   # name: (linear colour, roughness, metallic, extra) as in kit.MATERIALS

Blender frame: +X right, +Y forward, +Z up (glTF export turns it into Godot's -Z forward). A car is lofted from cross
sections at stations s (metres from the nose), then lamps, bumpers, decals and trim are projected onto the shell with
Projector. build_golf4.py is the worked example; build_seicento.py keeps its own copy of these (its GLB is rebuilt
byte-identical, so it is left alone).
"""
import bmesh
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import kit
from kit import arg, lerp, newell

MATERIALS = {}


def smoothstep(a, b, x):
	t = min(1.0, max(0.0, (x - a) / (b - a)))
	return t * t * (3.0 - 2.0 * t)



class Curve:
	"""Monotone cubic (PCHIP) through (s, value) points, so profiles never overshoot."""

	def __init__(self, pts):
		self.x = [p[0] for p in pts]
		self.y = [p[1] for p in pts]
		n = len(pts)
		h = [self.x[i + 1] - self.x[i] for i in range(n - 1)]
		d = [(self.y[i + 1] - self.y[i]) / h[i] for i in range(n - 1)]
		m = [0.0] * n
		m[0], m[-1] = d[0], d[-1]
		for i in range(1, n - 1):
			if d[i - 1] * d[i] <= 0:
				m[i] = 0.0
			else:
				w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
				m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
		self.h, self.m = h, m

	def __call__(self, s):
		x = self.x
		if s <= x[0]:
			return self.y[0]
		if s >= x[-1]:
			return self.y[-1]
		lo, hi = 0, len(x) - 1
		while hi - lo > 1:
			mid = (lo + hi) // 2
			if x[mid] <= s:
				lo = mid
			else:
				hi = mid
		h = self.h[lo]
		t = (s - x[lo]) / h
		t2, t3 = t * t, t * t * t
		return ((2 * t3 - 3 * t2 + 1) * self.y[lo] + (t3 - 2 * t2 + t) * h * self.m[lo]
			+ (-2 * t3 + 3 * t2) * self.y[hi] + (t3 - t2) * h * self.m[hi])



def cr(p0, p1, p2, p3, t):
	def nxt(ti, a, b):
		return ti + max((b - a).length, 1e-6) ** 0.5
	t0 = 0.0
	t1 = nxt(t0, p0, p1)
	t2 = nxt(t1, p1, p2)
	t3 = nxt(t2, p2, p3)
	u = t1 + (t2 - t1) * t
	a1 = p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
	a2 = p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
	a3 = p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
	b1 = a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
	b2 = a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))


def material(name):
	"""kit.material over this script's MATERIALS: Paint is tinted by the vertex colours, the rest are plain."""
	if name not in kit.MATERIALS:
		col, rough, metal, extra = MATERIALS[name]
		kit.MATERIALS[name] = (col, rough, metal, extra if name == "Paint" else {**extra, "plain": True})
	return kit.material(name)


class MB:
	def __init__(self):
		self.v = []
		self.f = []
		self.m = []
		self.col = []

	def vert(self, p, col=1.0):
		self.v.append(Vector(p))
		self.col.append(col)
		return len(self.v) - 1

	def face(self, idx, mat, out=None):
		if out is not None:
			pts = [self.v[i] for i in idx]
			ref = out(sum(pts, Vector()) / len(pts)) if callable(out) else out
			if newell(pts).dot(ref) < 0:
				idx = list(reversed(idx))
		self.f.append(list(idx))
		self.m.append(mat)

	def poly(self, pts, mat, out=None, col=1.0):
		return self.face([self.vert(p, col) for p in pts], mat, out)

	def quad(self, a, b, c, d, mat, out=None, col=1.0):
		self.poly([a, b, c, d], mat, out, col)

	def disc(self, centre, r, mat, normal=(0, 0, 1), segs=16, col=1.0):
		c, n = Vector(centre), Vector(normal).normalized()
		helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
		u = n.cross(helper).normalized()
		v = n.cross(u)
		self.poly([c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r
			for k in range(segs)], mat, n, col=col)

	def ring(self, centre, r_in, r_out, mat, normal=(0, 0, 1), segs=16, col=1.0):
		c, n = Vector(centre), Vector(normal).normalized()
		helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
		u = n.cross(helper).normalized()
		v = n.cross(u)
		pts_in = [c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r_in for k in range(segs)]
		pts_out = [c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r_out for k in range(segs)]
		for k in range(segs):
			k2 = (k + 1) % segs
			self.quad(pts_in[k], pts_out[k], pts_out[k2], pts_in[k2], mat, n, col=col)

	def grid(self, rows, mat, closed=False, out=None, cap_ends=False):
		ids = [[self.vert(p) for p in row] for row in rows]
		n = len(rows[0])
		for i in range(len(rows) - 1):
			for j in range(n if closed else n - 1):
				j2 = (j + 1) % n
				self.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], mat, out)
		if cap_ends and closed:
			for r, sign in ((ids[0], -1), (ids[-1], 1)):
				c = sum((self.v[i] for i in r), Vector()) / n
				ci = self.vert(c)
				for j in range(n):
					other = rows[1] if sign < 0 else rows[-2]
					oc = sum(other, Vector()) / n
					self.face([ci, r[j], r[(j + 1) % n]], mat, c - oc)
		return ids

	def lathe(self, profile, segs, mat, centre=Vector(), out=None, closed_profile=False):
		rows = []
		for ax, r in profile:
			rows.append([centre + Vector((ax, r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs)))
				for k in range(segs)])
		if closed_profile:
			rows.append(rows[0])
		ids = [[self.vert(p) for p in row] for row in rows]
		for i in range(len(rows) - 1):
			for k in range(segs):
				k2 = (k + 1) % segs
				self.face([ids[i][k], ids[i][k2], ids[i + 1][k2], ids[i + 1][k]], mat, out)

	def tube(self, a, b, r, mat, segs=10, caps=True):
		a, b = Vector(a), Vector(b)
		axis = (b - a).normalized()
		helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
		u = axis.cross(helper).normalized()
		v = axis.cross(u)
		rings = []
		for p in (a, b):
			rings.append([p + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r
				for k in range(segs)])
		mid = (a + b) / 2

		def out(c):
			d = c - mid
			return d - axis * d.dot(axis) if abs(d.dot(axis)) < (b - a).length / 2 - 1e-5 else d
		ids = [[self.vert(p) for p in ring] for ring in rings]
		for k in range(segs):
			k2 = (k + 1) % segs
			self.face([ids[0][k], ids[0][k2], ids[1][k2], ids[1][k]], mat, out)
		if caps:
			self.face(ids[0], mat, -axis)
			self.face(ids[1], mat, axis)

	def blob(self, c, radii, mat, e=0.35, basis=None, nu=12, nv=20):
		c = Vector(c)

		def sp(a, k):
			return math.copysign(abs(a) ** k, a)
		rows = []
		for i in range(1, nu):
			la = -math.pi / 2 + math.pi * i / nu
			row = []
			for j in range(nv):
				lo = -math.pi + 2 * math.pi * j / nv
				p = Vector((radii[0] * sp(math.cos(la), e) * sp(math.cos(lo), e),
					radii[1] * sp(math.cos(la), e) * sp(math.sin(lo), e), radii[2] * sp(math.sin(la), e)))
				row.append(c + (basis @ p if basis else p))
			rows.append(row)
		ids = self.grid(rows, mat, closed=True, out=lambda q: q - c)
		for r, z in ((ids[0], -1), (ids[-1], 1)):
			pole = self.vert(c + (basis @ Vector((0, 0, z * radii[2])) if basis else Vector((0, 0, z * radii[2]))))
			for j in range(nv):
				self.face([pole, r[j], r[(j + 1) % nv]], mat, lambda q: q - c)

	def box(self, c, size, mat, basis=None):
		c = Vector(c)
		hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
		corners = [Vector((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
		ids = [self.vert(c + (basis @ p if basis else p)) for p in corners]
		for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
			self.face([ids[i] for i in f], mat, lambda q: q - c)

	def extend(self, other):
		base = len(self.v)
		self.v += other.v
		self.col += other.col
		self.f += [[i + base for i in f] for f in other.f]
		self.m += other.m

	def bvh(self):
		return BVHTree.FromPolygons(self.v, self.f)

	def emit(self, name, sharp_deg=48.0, colors=False):
		me = bpy.data.meshes.new(name)
		me.from_pydata([tuple(p) for p in self.v], [], self.f)
		names = sorted(set(self.m), key=list(MATERIALS).index)
		for n in names:
			me.materials.append(material(n))
		me.polygons.foreach_set("material_index", [names.index(n) for n in self.m])
		if colors:
			attr = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
			for i, c in enumerate(self.col):
				attr.data[i].color = (c, c, c, 1.0)
		me.update()
		me.validate()
		me.shade_smooth()
		me.set_sharp_from_angle(angle=math.radians(sharp_deg))
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob


class Projector:
	def __init__(self, mb):
		self.tree = mb.bvh()

	def hit(self, origin, direction):
		loc, nor, _, _ = self.tree.ray_cast(origin, direction)
		if loc is None:
			raise RuntimeError("projection missed the body at %s" % (origin,))
		if nor.dot(direction) > 0:
			nor = -nor
		return loc, nor

	def star(self, mb, outline, proj, mat, offset=0.003, bulge=0.0, rings=3, skirt=0.005, samples=6):
		outline = resample(outline, samples)
		c = sum((Vector(p) for p in outline), Vector((0.0, 0.0))) / len(outline)
		grid = []
		normals = []
		for k in range(1, rings + 1):
			row = []
			for p in outline:
				q = c + (Vector(p) - c) * (k / rings)
				loc, nor = self.hit(*proj(q.x, q.y))
				row.append(loc + nor * (offset + bulge * (1 - (k / rings) ** 2)))
				normals.append(nor)
			grid.append(row)
		loc, nor = self.hit(*proj(c.x, c.y))
		centre = loc + nor * (offset + bulge)
		ref = sum(normals, Vector()).normalized()
		n = len(outline)
		ids = mb.grid(grid, mat, closed=True, out=ref)
		ci = mb.vert(centre)
		for j in range(n):
			mb.face([ci, ids[0][j], ids[0][(j + 1) % n]], mat, ref)
		if skirt:
			low = [mb.vert(mb.v[i] - normals[(rings - 1) * n + j] * (offset + skirt)) for j, i in enumerate(ids[-1])]
			for j in range(n):
				j2 = (j + 1) % n
				a, b = ids[-1][j], ids[-1][j2]
				mb.face([a, low[j], low[j2], b], mat, lambda q, c3=centre: q - c3)

	def strip(self, mb, u0, u1, v0, v1, nu, nv, proj, mat, offset=0.002):
		rows = []
		for i in range(nu + 1):
			u = lerp(u0, u1, i / nu)
			row = []
			for j in range(nv + 1):
				loc, nor = self.hit(*proj(u, lerp(v0, v1, j / nv)))
				row.append(loc + nor * offset)
			rows.append(row)
		_, ref = self.hit(*proj((u0 + u1) / 2, (v0 + v1) / 2))
		mb.grid(rows, mat, out=ref)


	def band(self, mb, us, vs, off, mat, proj, caps=False):
		"""A moulded strip over the body: rows at heights vs, columns at us, each point pushed off the surface
		by off(u, v) (so a profile can step in and out); mat(u, v) picks each face's material at its centre."""
		pts, nors = [], []
		for u in us:
			row, nrow = [], []
			for v in vs:
				loc, nor = self.hit(*proj(u, v))
				row.append(loc + nor * off(u, v))
				nrow.append(nor)
			pts.append(row)
			nors.append(nrow)
		ids = [[mb.vert(p) for p in row] for row in pts]
		for i in range(len(us) - 1):
			for j in range(len(vs) - 1):
				ref = nors[i][j] + nors[i + 1][j] + nors[i][j + 1] + nors[i + 1][j + 1]
				mb.face([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]],
					mat((us[i] + us[i + 1]) / 2, (vs[j] + vs[j + 1]) / 2), ref)
		if caps:
			for i, k in ((0, 1), (len(us) - 1, len(us) - 2)):
				inner = [pts[i][j] - nors[i][j] * 0.004 for j in range(len(vs))]
				ref = pts[i][len(vs) // 2] - pts[k][len(vs) // 2]
				mb.poly(pts[i] + list(reversed(inner)), mat(us[i], vs[len(vs) // 2]), ref)
		return pts


def resample(pts, per_seg):
	pts = [Vector(p) for p in pts]
	n = len(pts)
	out = []
	for i in range(n):
		p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
		for k in range(per_seg):
			out.append(cr(p0, p1, p2, p3, k / per_seg))
	return out


def ellipse(cu, cv, ru, rv, n=16):
	return [(cu + ru * math.cos(2 * math.pi * k / n), cv + rv * math.sin(2 * math.pi * k / n)) for k in range(n)]


def rounded_rect(u0, u1, v0, v1, r):
	pts = []
	for cu, cv, a0 in ((u1 - r, v1 - r, 0), (u0 + r, v1 - r, 90), (u0 + r, v0 + r, 180), (u1 - r, v0 + r, 270)):
		for k in range(4):
			a = math.radians(a0 + 90 * k / 3)
			pts.append((cu + r * math.cos(a), cv + r * math.sin(a)))
	return pts


def spread(a, b, step, extra=()):
	n = max(1, int(round((b - a) / step)))
	return sorted(set([round(a + (b - a) * i / n, 4) for i in range(n + 1)] + [e for e in extra if a < e < b]))


def profile(v, rows):
	"""Piecewise-linear offset profile through (height, offset) rows."""
	if v <= rows[0][0]:
		return rows[0][1]
	for (v0, o0), (v1, o1) in zip(rows, rows[1:]):
		if v <= v1:
			return lerp(o0, o1, (v - v0) / (v1 - v0))
	return rows[-1][1]



def lamp_bulb(mb, pj, proj, u, v, r, bulb_mat):
	"""A real bulb in a reflector cup: a chrome rim, a dark floor, a socket and a domed glass bulb standing proud."""
	loc, n = pj.hit(*proj(u, v))
	helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
	bx = n.cross(helper).normalized()
	basis = Matrix((bx, n.cross(bx), n)).transposed()
	mb.ring(loc + n * 0.0095, r * 0.74, r, "Chrome", normal=n, segs=24)
	mb.disc(loc + n * 0.0055, r * 0.78, "Seat", normal=n, segs=24)
	mb.tube(loc + n * 0.0055, loc + n * 0.0095, r * 0.2, "Chrome", segs=10)
	mb.blob(loc + n * 0.0098, (r * 0.5, r * 0.5, r * 0.3), bulb_mat, e=0.9, basis=basis, nu=6, nv=14)



def text_polys(text, width):
	"""Outline-filled text as (x, y) polygons centred on the origin, scaled to the given width."""
	cu = bpy.data.curves.new("txt", "FONT")
	cu.body = text
	cu.align_x = "CENTER"
	cu.align_y = "CENTER"
	cu.resolution_u = 3
	cu.fill_mode = "FRONT"
	ob = bpy.data.objects.new("txt", cu)
	bpy.context.scene.collection.objects.link(ob)
	me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
	xs = [v.co.x for v in me.vertices]
	k = width / max(1e-6, max(xs) - min(xs))
	polys = [[(me.vertices[i].co.x * k, me.vertices[i].co.y * k) for i in p.vertices] for p in me.polygons if p.normal.z > 0]
	bpy.data.objects.remove(ob)
	return polys



def text_decal(pj, mb, proj, text, cu, cv, width, mat, off, flip):
	"""Lettering laid on the body at (cu, cv) of proj, reading along u (flip -1 mirrors it for the other side)."""
	for poly in text_polys(text, width):
		locs = [pj.hit(*proj(cu + flip * x, cv + y)) for x, y in poly]
		ref = sum((n for _, n in locs), Vector())
		mb.poly([l + n * off for l, n in locs], mat, ref)



def _nz(p, a):
	# the dents' irregularity: half-metre waves (shorter ones folded thin panels over themselves at a full dent)
	return math.sin(p.x * 9.0 + p.y * 7.0 + a) * math.sin(p.y * 11.0 - p.z * 8.0 + a * 1.7)



def add_damage_keys(ob, delta_fn, sites=()):
	"""The dent_front/rear/left/right blend shapes the game's RaceCarVisual animates: delta_fn(key, point) is how far
	a crash moves a point (Blender coordinates) at full damage on that side; the same function should deform the
	body, lamps, stripes and liveries so they stay together."""
	ob.shape_key_add(name="Basis")
	for key in ("front", "rear", "left", "right"):
		sk = ob.shape_key_add(name="dent_" + key, from_mix=False)
		sk.value = 0.0
		for i, v in enumerate(ob.data.vertices):
			sk.data[i].co = v.co + delta_fn(key, v.co)
	if sites:
		add_crush_keys(ob, sites)


DECALS = ("Stripes", "Martini", "Abarth", "Marlboro")
LAMP_MATS = ("Headlight", "LampGlass", "LampBezel", "Taillight", "TailGlass", "TailBulb", "Glass")
# the loose panels RaceCarVisual animates (each with its "<name>Details" and "<name><decal>" pieces) and the glass it breaks
PARTS = ("Bonnet", "DoorL", "DoorR", "BumperF", "BumperR", "Boot")
GLASS = ("Windscreen", "WindowL", "WindowR", "RearWindow")
# Local crumple sites (crush_* blend shapes, layered over the dent_* ones; RaceCarVisual.CRUSH_SITES mirrors this table):
# name: (along the car 0 nose .. 1 tail, across -1 left .. 1 right of the half width, height in m, the way the ray finds the
# skin and the crush pushes in: "f" from the front, "r" from the rear, "s" from the side; radius m, depth m)
CRUSH = {
	"fl": (0.0, -0.62, 0.50, "f", 0.42, 0.17), "fc": (0.0, 0.0, 0.50, "f", 0.45, 0.15), "fr": (0.0, 0.62, 0.50, "f", 0.42, 0.17),
	"rl": (1.0, -0.62, 0.55, "r", 0.42, 0.15), "rc": (1.0, 0.0, 0.55, "r", 0.45, 0.13), "rr": (1.0, 0.62, 0.55, "r", 0.42, 0.15),
	"l1": (0.20, -1.0, 0.72, "s", 0.40, 0.12), "l2": (0.40, -1.0, 0.62, "s", 0.45, 0.13),
	"l3": (0.60, -1.0, 0.62, "s", 0.45, 0.13), "l4": (0.82, -1.0, 0.72, "s", 0.40, 0.12),
	"r1": (0.20, 1.0, 0.72, "s", 0.40, 0.12), "r2": (0.40, 1.0, 0.62, "s", 0.45, 0.13),
	"r3": (0.60, 1.0, 0.62, "s", 0.45, 0.13), "r4": (0.82, 1.0, 0.72, "s", 0.40, 0.12),
}


def crush_sites(body):
	"""The CRUSH sites on this Body (call before cutting panels out of it): [(name, centre on the skin, inward direction,
	radius, depth)], found by rays from outside the car at each site's station, offset and height."""
	vs = [v.co for v in body.data.vertices]
	y_hi, y_lo = max(v.y for v in vs), min(v.y for v in vs)
	half = max(abs(v.x) for v in vs if v.z > 0.3)
	bm = bmesh.new()
	bm.from_mesh(body.data)
	tree = BVHTree.FromBMesh(bm)
	bm.free()
	out = []
	for name, (u, w, z, way, r, depth) in CRUSH.items():
		if way == "s":
			y = y_hi - u * (y_hi - y_lo)
			o, d = Vector((w * (half + 1.0), y, z)), Vector((-w, 0.0, 0.0))
		else:
			x = w * half * 0.95
			o, d = (Vector((x, y_hi + 1.0, z)), Vector((0.0, -1.0, 0.0))) if way == "f" else (Vector((x, y_lo - 1.0, z)), Vector((0.0, 1.0, 0.0)))
		loc = None
		for dz in (0.0, 0.08, 0.16, -0.08):  # past a wheel arch: a little higher
			loc, nor, _, _ = tree.ray_cast(o + Vector((0.0, 0.0, dz)), d, 3.0)
			if loc is not None and (way != "s" or abs(loc.x) > 0.5 * half):
				break
			loc = None
		if loc is None:
			raise RuntimeError("crush site %s: the ray from %s misses the body" % (name, tuple(o)))
		push = d.copy()
		if way != "s" and w != 0.0:  # a corner folds back and in
			push = (d * 0.8 + Vector((-math.copysign(0.5, w), 0.0, 0.0))).normalized()
		out.append((name, loc.copy(), push, r, depth))
	return out


def crush_delta(site, p):
	"""How far a full crush at one site moves the point p: in along the push, falling off over the radius (shallower
	into the car than across its skin), with buckled folds round the middle and a little sag."""
	_, c, push, r, depth = site
	d = p - c
	along = d.dot(push)
	lat = (d - push * along).length
	q = (lat / r) ** 2 + (along / (r * 1.4)) ** 2
	if q > 2.6:
		return Vector()
	w = math.exp(-1.6 * q) * (1.0 - smoothstep(1.5, 2.6, q))
	fold = math.sin(lat * 26.0 + _nz(p, 6.1) * 1.2) * 4.0 * w * (1.0 - w)  # concentric buckles where the panel gave way
	out = push * depth * (w * (1.0 + 0.2 * _nz(p, 7.3)) + 0.14 * fold)
	out.z -= 0.2 * depth * w
	return out


def add_crush_keys(ob, sites):
	"""crush_<site> blend shapes on ob (after its dent_* keys, which made the Basis)."""
	if ob.data.shape_keys is None:
		ob.shape_key_add(name="Basis")
	for site in sites:
		sk = ob.shape_key_add(name="crush_" + site[0], from_mix=False)
		sk.value = 0.0
		for i, v in enumerate(ob.data.vertices):
			sk.data[i].co = v.co + crush_delta(site, v.co)


def keyed(objs):
	"""The objects that crumple (take the dent_* and crush_* keys): every one but the wheel and the cabin."""
	return [k for k in objs if k not in ("Wheel", "Cabin")]


def _names(me):
	return [m.name if m else "" for m in me.materials]


def _faces_to_object(src, keep, name):
	"""A new object holding the faces of src whose indices are in keep (its materials, colours and sharp edges), and a
	BVH of them."""
	bm = bmesh.new()
	bm.from_mesh(src.data)
	bm.faces.ensure_lookup_table()
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
	tree = BVHTree.FromBMesh(bm)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for m in src.data.materials:
		me.materials.append(m)
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	return ob, tree


def _drop_faces(ob, drop):
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.faces.ensure_lookup_table()
	bmesh.ops.delete(bm, geom=[bm.faces[i] for i in drop], context="FACES")
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()


def _mat_index(me, mat):
	if mat.name not in _names(me):
		me.materials.append(mat)
	return _names(me).index(mat.name)


def _key(co):
	return (round(co.x, 5), round(co.y, 5), round(co.z, 5))


def _recess(ob, sel, push, floor_mat):
	"""Pushes the faces sel of ob in by push(co, normal) as a cavity in floor_mat, joined to the hole's edge by walls."""
	fi = _mat_index(ob.data, floor_mat)
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.faces.ensure_lookup_table()
	faces = [bm.faces[i] for i in sel]
	vn = {}
	for f in faces:
		for v in f.verts:
			vn[_key(v.co)] = vn.get(_key(v.co), Vector()) + f.normal * max(f.calc_area(), 1e-6)
	before = set(bm.faces)
	ret = bmesh.ops.extrude_face_region(bm, geom=faces, use_keep_orig=False)
	moved = set(g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert))
	for v in moved:
		n = vn.get(_key(v.co), Vector((0.0, 0.0, 1.0)))
		v.co += push(v.co.copy(), n.normalized() if n.length > 1e-9 else Vector((0.0, 0.0, 1.0)))
	for f in bm.faces:
		if f not in before or any(v in moved for v in f.verts):
			f.material_index = fi
			f.smooth = False
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()


def _inner_skin(ob, gap, mat):
	"""The panel's inside: its faces again, turned inwards and gap in, in mat (an open door or a raised lid shows it)."""
	fi = _mat_index(ob.data, mat)
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.normal_update()
	vn = {v: v.normal.copy() for v in bm.verts}
	faces = list(bm.faces)
	ret = bmesh.ops.duplicate(bm, geom=faces)
	vmap = ret["vert_map"]
	new_faces = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
	for old, new in vmap.items():
		if isinstance(old, bmesh.types.BMVert) and old in vn:
			new.co = old.co - vn[old] * gap
	bmesh.ops.reverse_faces(bm, faces=new_faces)
	for f in new_faces:
		f.material_index = fi
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()


def _decal_pieces(objs, name, tree, decals):
	"""Moves the stripe and livery faces lying on a cut-out panel (tree) into objs[name + decal]."""
	for k in decals:
		dob = objs.get(k)
		if dob is None:
			continue
		on = set()
		for p in dob.data.polygons:  # the decal faces lying on the panel (a few mm off it), round its curved edges too
			loc, _, _, dist = tree.find_nearest(p.center, 0.03)
			if loc is not None and dist < 0.02:
				on.add(p.index)
		if not on:
			continue
		objs[name + k], _ = _faces_to_object(dob, on, name + k)
		_drop_faces(dob, on)


def split_part(objs, name, picks, floor_mat, push=None, inner=0.012, decals=DECALS):
	"""Cuts a loose panel out of the car: picks maps a source object name ("Body", "Details") to pick(centre, normal,
	material name) choosing its faces (Blender coordinates). The Body's go into objs[name] (Paint and all, the same
	vertices, so no seam while it is fitted) with an inner skin, and are left behind pushed in by push(co, normal) as a
	dark cavity (floor_mat); the other sources' go into objs[name + source]; stripe and livery faces on the panel into
	objs[name + decal]."""
	tree = None
	for src_name, pick in picks.items():
		src = objs.get(src_name)
		if src is None:
			continue
		names = _names(src.data)
		sel = [p.index for p in src.data.polygons if pick(p.center.copy(), p.normal.copy(), names[p.material_index])]
		if not sel:
			continue
		pname = name if src_name == "Body" else name + src_name
		objs[pname], t = _faces_to_object(src, set(sel), pname)
		if src_name == "Body":
			tree = t
			if push:
				_recess(src, sel, push, floor_mat)
			else:
				_drop_faces(src, sel)
			if inner:
				_inner_skin(objs[pname], inner, floor_mat)
		else:
			_drop_faces(src, sel)
	if tree is None:
		raise RuntimeError("split_part found no %s faces on the Body" % name)
	_decal_pieces(objs, name, tree, decals)
	print("%s: %s" % (name, ", ".join("%s %d" % (k, len(objs[k].data.polygons)) for k in objs if k.startswith(name))))


def split_damage_parts(objs, y0, front_axle_s, rear_axle_s, arch_r, door, s_deck, floor_mat, recess=0.05):
	"""The front doors, both bumpers and the boot lid or tailgate cut out of the Body (and the Details on them) as
	DoorL DoorR BumperF BumperR Boot, then the Body's glass split into Windscreen WindowL WindowR RearWindow (RaceCarVisual
	swings, drops and throws the panels and breaks the glass). door: the front door's leading and trailing stations
	(s, metres from the nose); s_deck: where the boot lid or tailgate starts behind the roof. Call after split_bonnet,
	before the damage keys."""
	body, details = objs["Body"], objs.get("Details")
	bn = _names(body.data)
	gi = bn.index("Glass") if "Glass" in bn else -1

	def s_of(c):
		return y0 - c.y

	paint_side = [(p.center.copy(), p.normal.copy()) for p in body.data.polygons if bn[p.material_index] == "Paint" and abs(p.normal.x) > 0.3]
	vs = [v.co.copy() for v in body.data.vertices]

	def half_at(s, dz=(0.3, 1.2)):
		xs = [abs(v.x) for v in vs if abs(s_of(v) - s) < 0.06 and dz[0] < v.z < dz[1]]
		return max(xs) if xs else 0.8
	lamp_v = []
	if details is not None:
		dn = _names(details.data)
		for p in details.data.polygons:
			if dn[p.material_index] in LAMP_MATS:
				lamp_v.append((dn[p.material_index], [details.data.vertices[i].co.copy() for i in p.vertices]))
	head_z = [c.z for m, cs in lamp_v if m in ("Headlight", "LampGlass", "LampBezel") for c in cs if c.y > 0.0]
	# the tail lamp clusters (not a high-level brake light on the centre line, nor reflectors and fog lamps in the bumper)
	tail = [c for m, cs in lamp_v if m in ("Taillight", "TailGlass", "TailBulb") for c in cs
		if c.y < 0.0 and abs(c.x) > 0.25 and 0.5 < c.z < 1.05]
	z_fb = (min(head_z) if head_z else 0.62) - 0.012
	z_rb = min(max(min(c.z for c in tail) - 0.012, 0.45), 0.66) if tail else 0.55
	s_fb, s_rb = front_axle_s - arch_r - 0.01, rear_axle_s + arch_r + 0.01
	other = ("Glass",)

	# front doors: the side's paint between the door's shut lines, from above the sill up to the side glass
	s0, s1 = door[0], door[1]
	for side, name in ((-1.0, "DoorL"), (1.0, "DoorR")):
		glass_z = [body.data.vertices[i].co.z for p in body.data.polygons if p.material_index == gi and p.center.x * side > 0.0
			and abs(p.normal.x) > 0.5 and s0 < s_of(p.center) < s1 for i in p.vertices]
		belt = min(glass_z) if glass_z else 0.9
		low = min((c.z for c, _ in paint_side if c.x * side > 0.0 and s0 < s_of(c) < s1), default=0.25) + 0.07
		half = half_at((s0 + s1) / 2.0)

		def in_door(c, sd=side, lo=low, hi=belt):
			return c.x * sd > 0.0 and s0 + 0.003 < s_of(c) < s1 - 0.003 and lo < c.z < hi + 0.004
		split_part(objs, name, {
			"Body": lambda c, n, m, f=in_door, sd=side: m not in other and f(c) and n.x * sd > 0.3,
			"Details": lambda c, n, m, f=in_door, h=half, sd=side: m not in LAMP_MATS and f(c) and c.x * sd > h - 0.09},
			floor_mat)  # (the hole shows the cabin, through the door's frame)

	# bumpers: everything below the lamps ahead of the front arches and behind the rear ones
	def front_zone(c):
		return s_of(c) < s_fb and c.z < z_fb

	def rear_zone(c):
		return s_of(c) > s_rb and c.z < z_rb
	for name, zone in (("BumperF", front_zone), ("BumperR", rear_zone)):
		split_part(objs, name, {
			"Body": lambda c, n, m, z=zone: m not in other and z(c),
			"Details": lambda c, n, m, z=zone: m not in LAMP_MATS and z(c)},
			floor_mat, push=lambda co, n: -n * recess)

	# the boot lid or tailgate: the paint behind s_deck above the rear bumper, between the tail lamps below their tops
	lamp_in = min((abs(c.x) for c in tail if c.z > z_rb), default=None)
	lamp_top = max((c.z for c in tail), default=0.0)
	print("parts: bumper tops %.3f / %.3f, tail lamps inside %s up to %.3f, deck %.2f" % (z_fb, z_rb, lamp_in, lamp_top, s_deck))

	def in_boot(c):
		if s_of(c) < s_deck + 0.004 or c.z < z_rb + 0.004:
			return False
		lim = lamp_in - 0.012 if lamp_in is not None and c.z < lamp_top + 0.01 else 0.9 * half_at(s_of(c), (z_rb, 2.0))
		return abs(c.x) < lim
	split_part(objs, "Boot", {
		"Body": lambda c, n, m: m == "Paint" and in_boot(c) and (n.y < -0.2 or n.z > 0.45),
		"Details": lambda c, n, m: m not in LAMP_MATS and in_boot(c) and c.z < 1.6},
		floor_mat, push=lambda co, n: -n * recess)
	split_glass(objs, y0)


def split_glass(objs, y0):
	"""The Body's Glass faces as Windscreen, WindowL, WindowR and RearWindow (RaceCarVisual cracks and shatters them)."""
	body = objs["Body"]
	bn = _names(body.data)
	if "Glass" not in bn:
		return
	gi = bn.index("Glass")
	groups = {k: set() for k in GLASS}
	for p in body.data.polygons:
		if p.material_index != gi:
			continue
		if abs(p.normal.x) > 0.55:
			groups["WindowL" if p.center.x < 0.0 else "WindowR"].add(p.index)
		else:
			groups["Windscreen" if p.center.y > 0.0 else "RearWindow"].add(p.index)
	drop = set()
	for k, sel in groups.items():
		if sel:
			objs[k], _ = _faces_to_object(body, sel, k)
			drop |= sel
	_drop_faces(body, drop)
	print("glass: %s" % ", ".join("%s %d" % (k, len(v)) for k, v in groups.items()))


def pose_wreck(objs, sites):
	"""--wreck previews: a few crush keys at full, the left door hanging open, the front bumper sagging, the boot popped,
	the right door and window gone."""
	for ob in objs.values():
		sk = ob.data.shape_keys
		if sk is None:
			continue
		for kb in sk.key_blocks:
			if kb.name in ("crush_fl", "crush_l2", "crush_rr"):
				kb.value = 1.0
			elif kb.name == "dent_front":
				kb.value = 0.5

	def swing(prefix, pivot, axis, angle):
		m = Matrix.Translation(pivot) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-pivot)
		for k, ob in objs.items():
			if k == prefix or (k.startswith(prefix) and k[len(prefix):] in DECALS + ("Details",)):
				ob.matrix_world = m
	for prefix, how in (("DoorL", "door"), ("BumperF", "sag"), ("Boot", "lid")):
		ob = objs.get(prefix)
		if ob is None:
			continue
		vs = [v.co for v in ob.data.vertices]
		if how == "door":
			ymax = max(v.y for v in vs)
			swing(prefix, Vector((min(v.x for v in vs) + 0.05, ymax, 0.0)), "Z", math.radians(-48.0))
		elif how == "sag":
			swing(prefix, Vector((max(v.x for v in vs), 0.0, max(v.z for v in vs))), "Y", math.radians(-14.0))
		else:
			top = max(vs, key=lambda v: v.z)
			swing(prefix, Vector((0.0, top.y, top.z)), "X", math.radians(-40.0))
	for k, ob in objs.items():
		if k == "DoorR" or k.startswith("DoorR") or k == "WindowR":
			ob.hide_render = True


def split_bonnet(objs, y0, s_rear, floor_mat, s_front=0.04, up=0.55, frac=0.84, recess=0.07, decals=DECALS):
	"""Cuts the bonnet panel out of objs["Body"] into objs["Bonnet"] (its Paint faces, the same vertices, so no seam or
	z-fighting while it is shut), leaves a dark recessed engine bay (floor_mat) under it in the Body, and moves the stripe
	and livery faces lying on the bonnet into objs["Bonnet" + name]. s = y0 - y is metres from the nose; the bonnet is the
	upward-facing paint between s_front and s_rear (the scuttle) within frac of the shell's half width there. The game's
	RaceCarVisual hinges it at its rear edge and can throw it off. Call before add_damage_keys (the pieces take the same
	dent_* keys, so they crumple with the Body)."""
	body = objs["Body"]
	me = body.data
	paint = next(i for i, m in enumerate(me.materials) if m.name == "Paint")
	region = [v.co for v in me.vertices if s_front < y0 - v.co.y < s_rear]
	half = max(abs(c.x) for c in region)
	top = max(c.z for c in region)
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.faces.ensure_lookup_table()

	def on_bonnet(f):
		c = f.calc_center_median()
		return (f.material_index == paint and f.normal.z > up and s_front < y0 - c.y < s_rear and abs(c.x) < frac * half
			and c.z > top - 0.3)
	sel = [f.index for f in bm.faces if on_bonnet(f)]
	if not sel:
		raise RuntimeError("split_bonnet found no bonnet faces")
	keep = set(sel)
	# the bonnet: a copy of the Body with everything else deleted
	bb = bm.copy()
	bb.faces.ensure_lookup_table()
	bmesh.ops.delete(bb, geom=[f for f in bb.faces if f.index not in keep], context="FACES")
	tree = BVHTree.FromBMesh(bb)
	bon = bpy.data.meshes.new("Bonnet")
	bb.to_mesh(bon)
	bb.free()
	for m in me.materials:
		bon.materials.append(m)
	ob = bpy.data.objects.new("Bonnet", bon)
	bpy.context.scene.collection.objects.link(ob)
	objs["Bonnet"] = ob
	_inner_skin(ob, 0.012, floor_mat)  # its underside, seen when it is up
	# the Body: the bonnet's faces pushed down into a recess with walls, in the bay's dark material
	if floor_mat.name not in [m.name for m in me.materials if m]:
		me.materials.append(floor_mat)
	fi = [m.name if m else "" for m in me.materials].index(floor_mat.name)
	before = set(bm.faces)
	faces = [bm.faces[i] for i in sel]
	ret = bmesh.ops.extrude_face_region(bm, geom=faces, use_keep_orig=False)
	moved = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
	bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, -recess)), verts=moved)
	for f in bm.faces:
		if f not in before or any(v in moved for v in f.verts):
			f.material_index = fi
			f.smooth = False
	bm.to_mesh(me)
	bm.free()
	me.update()
	# stripes and liveries that lie on the bonnet go with it
	_decal_pieces(objs, "Bonnet", tree, decals)
	print("bonnet: %d faces, %s" % (len(sel), ", ".join(k for k in objs if k.startswith("Bonnet"))))
	return ob


def sparsify_glb(path, eps=2e-4):
	"""Rewrites the GLB's dense morph-target accessors (Blender's exporter writes the NORMAL deltas dense, though a crush
	moves a few hundred of a panel's vertices) as sparse ones holding only the deltas over eps, and packs the buffer.
	Godot reads sparse accessors as the same blend shapes; the crush_* keys made a car's GLB four times the size without."""
	import json
	import struct
	with open(path, "rb") as fh:
		data = fh.read()
	jlen = struct.unpack("<I", data[12:16])[0]
	j = json.loads(data[20:20 + jlen])
	blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
	bin_ = data[28 + jlen:28 + jlen + blen]
	acc, views = j["accessors"], j["bufferViews"]
	chunks = []  # new buffer contents, as (bytes) per view index
	new_views = []

	def view_bytes(vi):
		v = views[vi]
		return bin_[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]

	def add_view(blob, target=None):
		new_views.append({"buffer": 0, "byteLength": len(blob), **({"target": target} if target else {})})
		chunks.append(blob)
		return len(new_views) - 1
	remap = {}
	made = set()  # accessors made sparse here (their views are new already)
	targets = set()
	for m in j["meshes"]:
		for p in m["primitives"]:
			for t in p.get("targets", []):
				targets.update(t.values())
	for ai, a in enumerate(acc):
		if ai in targets and "bufferView" in a and "sparse" not in a and a["componentType"] == 5126 and a["type"] == "VEC3" \
				and views[a["bufferView"]].get("byteStride", 12) == 12:
			raw = view_bytes(a["bufferView"])[a.get("byteOffset", 0):a.get("byteOffset", 0) + 12 * a["count"]]
			vals = struct.unpack("<%df" % (3 * a["count"]), raw)
			idx = [i for i in range(a["count"]) if max(abs(vals[3 * i]), abs(vals[3 * i + 1]), abs(vals[3 * i + 2])) > eps]
			if len(idx) * 16 < a["count"] * 12:
				del a["bufferView"]
				a.pop("byteOffset", None)
				if not idx:  # glTF wants at least one sparse entry: a zero one
					idx = [0]
				iv = add_view(struct.pack("<%dI" % len(idx), *idx))
				vv = add_view(b"".join(struct.pack("<3f", *vals[3 * i:3 * i + 3]) for i in idx))
				a["sparse"] = {"count": len(idx), "indices": {"bufferView": iv, "componentType": 5125}, "values": {"bufferView": vv}}
				made.add(ai)
				lo = [min(vals[3 * i + k] for i in idx) for k in range(3)]
				hi = [max(vals[3 * i + k] for i in idx) for k in range(3)]
				if "min" in a:
					a["min"], a["max"] = [min(x, 0.0) for x in lo], [max(x, 0.0) for x in hi]
				continue
	# every view still referenced keeps its bytes (accessors, sparse parts, images), in a fresh packed buffer
	used = []
	for ai, a in enumerate(acc):
		if "bufferView" in a:
			used.append(("acc", a))
		if "sparse" in a and ai not in made:  # Blender's own sparse accessors
			used.append(("idx", a["sparse"]["indices"]))
			used.append(("val", a["sparse"]["values"]))
	for im in j.get("images", []):
		if "bufferView" in im:
			used.append(("img", im))
	for kind, ob in used:
		vi = ob["bufferView"]
		if vi not in remap:
			v = dict(views[vi])
			blob = view_bytes(vi)
			v.pop("byteOffset", None)
			v.pop("buffer", None)
			new_views.append({"buffer": 0, **v})
			chunks.append(blob)
			remap[vi] = len(new_views) - 1
		ob["bufferView"] = remap[vi]
	out = bytearray()
	for v, blob in zip(new_views, chunks):
		while len(out) % 4:
			out.append(0)
		v["byteOffset"] = len(out)
		v["byteLength"] = len(blob)
		out += blob
	while len(out) % 4:
		out.append(0)
	j["bufferViews"] = new_views
	j["buffers"] = [{"byteLength": len(out)}]
	js = json.dumps(j, separators=(",", ":")).encode()
	js += b" " * ((4 - len(js) % 4) % 4)
	glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack("<I", len(js)) + b"JSON" + js \
		+ struct.pack("<I", len(out)) + b"BIN\x00" + bytes(out)
	with open(path, "wb") as fh:
		fh.write(glb)
	print("sparsified", path, "(%d KB)" % (len(glb) // 1024))


def setup_preview(paint, size=(1200, 800)):
	"""kit's preview scene (40 m grey ground), with the Paint tint set to the livery colour."""
	cam = kit.setup_preview(size=size, ground=40.0, ground_colour=(0.25, 0.25, 0.25))
	tint = bpy.data.materials["Paint"].node_tree.nodes["Tint"]
	next(s for s in tint.inputs if s.identifier == "A_Color").default_value = (*paint, 1)
	return cam


def render_views(cam, out_dir, views, aim_default):
	"""views: {name: (eye, lens_deg, aim or None)}; names side, side_l, front, rear and top render orthographic."""
	os.makedirs(out_dir, exist_ok=True)
	for ob in bpy.data.objects:  # the panels' stripe and livery pieces show with their parent mesh
		for part in PARTS:
			if ob.name.startswith(part) and ob.name[len(part):] in DECALS and ob.name[len(part):] in bpy.data.objects:
				ob.hide_render = ob.hide_render or bpy.data.objects[ob.name[len(part):]].hide_render
		if ob.name.startswith("Bonnet") and "--no-bonnet" in sys.argv:  # a look at the engine bay under it
			ob.hide_render = True
	for name, (pos, lens_deg, aim) in views.items():
		cam.location = pos
		target = Vector(aim) if aim else Vector(aim_default)
		cam.rotation_euler = (target - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
		cam.data.angle = math.radians(lens_deg)
		if name in ("side", "side_l", "front", "rear", "top"):
			cam.data.type = "ORTHO"
			cam.data.ortho_scale = 4.8 if name != "top" else 4.6
			if name == "top":
				cam.rotation_euler = (0, 0, math.pi / 2)
		else:
			cam.data.type = "PERSP"
		bpy.context.scene.render.filepath = os.path.join(out_dir, name + ".png")
		bpy.ops.render.render(write_still=True)
