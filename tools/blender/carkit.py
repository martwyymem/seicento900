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
	return math.sin(p.x * 23.0 + p.y * 17.0 + a) * math.sin(p.y * 29.0 - p.z * 19.0 + a * 1.7)



def add_damage_keys(ob, delta_fn):
	"""The dent_front/rear/left/right blend shapes the game's RaceCarVisual animates: delta_fn(key, point) is how far
	a crash moves a point (Blender coordinates) at full damage on that side; the same function should deform the
	body, lamps, stripes and liveries so they stay together."""
	ob.shape_key_add(name="Basis")
	for key in ("front", "rear", "left", "right"):
		sk = ob.shape_key_add(name="dent_" + key, from_mix=False)
		sk.value = 0.0
		for i, v in enumerate(ob.data.vertices):
			sk.data[i].co = v.co + delta_fn(key, v.co)


def setup_preview(paint, size=(1200, 800)):
	"""kit's preview scene (40 m grey ground), with the Paint tint set to the livery colour."""
	cam = kit.setup_preview(size=size, ground=40.0, ground_colour=(0.25, 0.25, 0.25))
	tint = bpy.data.materials["Paint"].node_tree.nodes["Tint"]
	next(s for s in tint.inputs if s.identifier == "A_Color").default_value = (*paint, 1)
	return cam


def render_views(cam, out_dir, views, aim_default):
	"""views: {name: (eye, lens_deg, aim or None)}; names side, side_l, front, rear and top render orthographic."""
	os.makedirs(out_dir, exist_ok=True)
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
