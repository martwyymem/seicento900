"""Shared helpers for the Blender build scripts: a small mesh builder, materials, glTF export and preview
renders. Import it from a script run with `blender -b -P tools/blender/<script>.py`:

    sys.path.insert(0, os.path.dirname(__file__))
    import kit

Blender frame: +X right, +Y forward (away from the viewer), +Z up. glTF export turns it into Godot's frame
(+X right, -Z forward, +Y up), so a Blender +Y offset becomes Godot -Z.
"""
import bpy
import math
import os
import sys
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name):
	return ARGS[ARGS.index(name) + 1] if name in ARGS and ARGS.index(name) + 1 < len(ARGS) else None


def lerp(a, b, t):
	return a + (b - a) * t


# ---------------------------------------------------------------- materials
# name: (base colour (linear), roughness, metallic, extra); extra keys: emit ((r, g, b), strength), alpha
MATERIALS = {}


def srgb(hex_colour):
	"""'#rrggbb' -> linear RGB tuple (Blender and glTF store linear colour factors)."""
	h = hex_colour.lstrip("#")
	out = []
	for i in (0, 2, 4):
		c = int(h[i:i + 2], 16) / 255.0
		out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
	return tuple(out)


def material(name):
	m = bpy.data.materials.get(name)
	if m:
		return m
	col, rough, metal, extra = MATERIALS[name]
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	m.use_backface_culling = not extra.get("double", False) and "alpha" not in extra
	nt = m.node_tree
	bsdf = nt.nodes.get("Principled BSDF")
	bsdf.inputs["Roughness"].default_value = rough
	bsdf.inputs["Metallic"].default_value = metal
	if "emit" in extra:
		bsdf.inputs["Emission Color"].default_value = (*extra["emit"][0], 1.0)
		bsdf.inputs["Emission Strength"].default_value = extra["emit"][1]
	if "alpha" in extra:
		bsdf.inputs["Alpha"].default_value = extra["alpha"]
		if hasattr(m, "surface_render_method"):
			m.surface_render_method = "BLENDED"
		else:
			m.blend_method = "BLEND"
	# base colour x vertex colour, the pattern the glTF exporter writes as baseColorFactor + COLOR_0
	attr = nt.nodes.new("ShaderNodeVertexColor")
	attr.layer_name = "Col"
	mix = nt.nodes.new("ShaderNodeMix")
	mix.data_type = "RGBA"
	mix.blend_type = "MULTIPLY"
	mix.name = "Tint"
	sock = {s.identifier: s for s in mix.inputs}
	sock["Factor_Float"].default_value = 1.0
	sock["A_Color"].default_value = (*col, 1.0)
	nt.links.new(attr.outputs["Color"], sock["B_Color"])
	out = {s.identifier: s for s in mix.outputs}
	nt.links.new(out["Result_Color"], bsdf.inputs["Base Color"])
	return m


# ---------------------------------------------------------------- mesh builder
def newell(pts):
	n = Vector((0.0, 0.0, 0.0))
	for i in range(len(pts)):
		a, b = pts[i], pts[(i + 1) % len(pts)]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	return n


def _rgb(c):
	if isinstance(c, str):
		return srgb(c)
	if isinstance(c, (int, float)):
		return (c, c, c)
	return tuple(c)


class MB:
	"""Collects vertices (with colours), faces (with material names and optional UVs) for one object.

	`colour` is the vertex colour applied to new vertices ('#hex', grey level or linear RGB); `uv` a
	callable(point) -> (u, v) used for new faces when set.
	"""

	def __init__(self):
		self.v = []
		self.c = []
		self.f = []
		self.m = []
		self.uv = []
		self.colour = (1.0, 1.0, 1.0)
		self.uv_fn = None

	def vert(self, p, col=None):
		self.v.append(Vector(p))
		self.c.append(_rgb(col) if col is not None else self.colour)
		return len(self.v) - 1

	def face(self, idx, mat, out=None, uvs=None):
		"""out: outward reference (Vector or callable(centre)) to fix the winding."""
		idx = list(idx)
		if out is not None:
			pts = [self.v[i] for i in idx]
			ref = out(sum(pts, Vector()) / len(pts)) if callable(out) else Vector(out)
			if newell(pts).dot(ref) < 0:
				idx.reverse()
				if uvs:
					uvs = list(reversed(uvs))
		if uvs is None and self.uv_fn:
			uvs = [self.uv_fn(self.v[i]) for i in idx]
		self.f.append(idx)
		self.m.append(mat)
		self.uv.append(uvs)

	def poly(self, pts, mat, out=None, uvs=None, col=None):
		return self.face([self.vert(p, col) for p in pts], mat, out, uvs)

	def quad(self, a, b, c, d, mat, out=None, uvs=None, col=None):
		self.poly([a, b, c, d], mat, out, uvs, col)

	def grid(self, rows, mat, closed=False, out=None):
		"""rows[i][j]: points; quads between consecutive rows (j wraps when closed)."""
		ids = [[self.vert(p) for p in row] for row in rows]
		n = len(rows[0])
		for i in range(len(rows) - 1):
			for j in range(n if closed else n - 1):
				j2 = (j + 1) % n
				self.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], mat, out)
		return ids

	def box(self, lo, hi, mat, skip=(), col=None, basis=None, origin=None):
		"""Axis-aligned box from corner lo to corner hi. skip: faces to leave out ('-x', '+x', '-y', ...).
		With basis/origin the box is built in that local frame."""
		lo, hi = Vector(lo), Vector(hi)
		c = (lo + hi) / 2

		def P(x, y, z):
			p = Vector((x, y, z))
			return (origin or Vector()) + (basis @ p if basis else p)
		faces = {
			"-x": ((lo.x, lo.y, lo.z), (lo.x, lo.y, hi.z), (lo.x, hi.y, hi.z), (lo.x, hi.y, lo.z)),
			"+x": ((hi.x, lo.y, lo.z), (hi.x, hi.y, lo.z), (hi.x, hi.y, hi.z), (hi.x, lo.y, hi.z)),
			"-y": ((lo.x, lo.y, lo.z), (hi.x, lo.y, lo.z), (hi.x, lo.y, hi.z), (lo.x, lo.y, hi.z)),
			"+y": ((lo.x, hi.y, lo.z), (lo.x, hi.y, hi.z), (hi.x, hi.y, hi.z), (hi.x, hi.y, lo.z)),
			"-z": ((lo.x, lo.y, lo.z), (lo.x, hi.y, lo.z), (hi.x, hi.y, lo.z), (hi.x, lo.y, lo.z)),
			"+z": ((lo.x, lo.y, hi.z), (hi.x, lo.y, hi.z), (hi.x, hi.y, hi.z), (lo.x, hi.y, hi.z)),
		}
		cw = P(*c)
		for key, pts in faces.items():
			if key in skip:
				continue
			self.poly([P(*p) for p in pts], mat, lambda q: q - cw, col=col)

	def prism(self, profile, x0, x1, mat, col=None, caps=True, out_ref=None):
		"""Extrude a closed (y, z) profile along x from x0 to x1."""
		ring0 = [Vector((x0, y, z)) for y, z in profile]
		ring1 = [Vector((x1, y, z)) for y, z in profile]
		cy = sum(y for y, _ in profile) / len(profile)
		cz = sum(z for _, z in profile) / len(profile)
		n = len(profile)
		for j in range(n):
			j2 = (j + 1) % n
			self.poly([ring0[j], ring0[j2], ring1[j2], ring1[j]], mat,
				lambda q: Vector((0.0, q.y - cy, q.z - cz)), col=col)
		if caps:
			self.poly(ring0, mat, (-1, 0, 0), col=col)
			self.poly(ring1, mat, (1, 0, 0), col=col)

	def tube(self, a, b, r, mat, segs=8, caps=True, col=None):
		a, b = Vector(a), Vector(b)
		axis = (b - a).normalized()
		helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
		u = axis.cross(helper).normalized()
		v = axis.cross(u)
		rings = [[p + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r
			for k in range(segs)] for p in (a, b)]
		mid = (a + b) / 2
		ids = [[self.vert(p, col) for p in ring] for ring in rings]
		for k in range(segs):
			k2 = (k + 1) % segs

			def out(q):
				d = q - mid
				return d - axis * d.dot(axis)
			self.face([ids[0][k], ids[0][k2], ids[1][k2], ids[1][k]], mat, out)
		if caps:
			self.face(ids[0], mat, -axis)
			self.face(ids[1], mat, axis)

	def beam(self, a, b, w, h, mat, up=(0, 0, 1), col=None):
		"""Rectangular bar w x h from a to b; `up` orients the h side."""
		a, b = Vector(a), Vector(b)
		axis = (b - a).normalized()
		side = axis.cross(Vector(up))
		if side.length < 1e-6:
			side = axis.cross(Vector((1, 0, 0)))
		side.normalize()
		upv = side.cross(axis)
		corners = [side * sx * w / 2 + upv * sz * h / 2 for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
		mid = (a + b) / 2
		ra = [self.vert(a + c, col) for c in corners]
		rb = [self.vert(b + c, col) for c in corners]
		for k in range(4):
			k2 = (k + 1) % 4
			self.face([ra[k], ra[k2], rb[k2], rb[k]], mat, lambda q: (q - mid) - axis * (q - mid).dot(axis))
		self.face(ra, mat, -axis)
		self.face(rb, mat, axis)

	def lathe(self, profile, segs, mat, centre=(0, 0, 0), col=None):
		"""Revolve (height z, radius) points around the Z axis. The outside is on the right of the profile
		walked in order (bottom to top for a solid)."""
		c = Vector(centre)
		rows = [[c + Vector((r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs), z))
			for k in range(segs)] for z, r in profile]
		ids = [[self.vert(p, col) for p in row] for row in rows]
		for i in range(len(rows) - 1):
			dz = profile[i + 1][0] - profile[i][0]
			dr = profile[i + 1][1] - profile[i][1]
			for k in range(segs):
				k2 = (k + 1) % segs

				def out(q, dz=dz, dr=dr):
					radial = Vector((q.x - c.x, q.y - c.y, 0.0))
					radial = radial.normalized() if radial.length > 1e-9 else Vector((1, 0, 0))
					return radial * dz + Vector((0, 0, -dr))
				self.face([ids[i][k], ids[i][k2], ids[i + 1][k2], ids[i + 1][k]], mat, out)
		return ids

	def disc(self, centre, r, mat, normal=(0, 0, 1), segs=12, col=None):
		c, n = Vector(centre), Vector(normal).normalized()
		helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
		u = n.cross(helper).normalized()
		v = n.cross(u)
		self.poly([c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r
			for k in range(segs)], mat, n, col=col)

	def extend(self, other, offset=(0, 0, 0), basis=None):
		base = len(self.v)
		o = Vector(offset)
		self.v += [o + (basis @ p if basis else p) for p in other.v]
		self.c += other.c
		self.f += [[i + base for i in f] for f in other.f]
		self.m += other.m
		self.uv += other.uv

	def tris(self):
		return sum(len(f) - 2 for f in self.f)

	def emit(self, name, sharp_deg=35.0, collection=None):
		me = bpy.data.meshes.new(name)
		me.from_pydata([tuple(p) for p in self.v], [], self.f)
		order = list(MATERIALS)
		names = sorted(set(self.m), key=order.index)
		for n in names:
			me.materials.append(material(n))
		me.polygons.foreach_set("material_index", [names.index(n) for n in self.m])
		# linear float colours reach glTF (and Godot's COLOR) unchanged
		attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
		attr.data.foreach_set("color", [x for c in self.c for x in (*c, 1.0)])
		me.color_attributes.active_color = attr
		if any(self.uv):
			layer = me.uv_layers.new(name="UVMap")
			k = 0
			for fi, f in enumerate(self.f):
				uvs = self.uv[fi]
				for j in range(len(f)):
					layer.data[k].uv = uvs[j] if uvs else (0.0, 0.0)
					k += 1
		me.update()
		me.validate()
		me.shade_smooth()
		me.set_sharp_from_angle(angle=math.radians(sharp_deg))
		ob = bpy.data.objects.new(name, me)
		(collection or bpy.context.scene.collection).objects.link(ob)
		return ob


def text_mesh(mb, text, origin, size, mat, axis_u=(1, 0, 0), axis_v=(0, 0, 1), align="CENTER", col=None,
		depth=0.0, font=None):
	"""Flat (or extruded) lettering: a Blender text object converted to polygons and added to mb.
	origin is the text's anchor (centre of the baseline row for align CENTER); the letters lie in the
	plane of axis_u (reading direction) and axis_v (up), facing axis_u x axis_v."""
	cu = bpy.data.curves.new("txt", "FONT")
	cu.body = text
	cu.size = size
	cu.align_x = align
	cu.align_y = "CENTER"
	cu.extrude = depth / 2
	cu.resolution_u = 2
	cu.fill_mode = "BOTH"
	if font:
		cu.font = bpy.data.fonts.load(font)
	ob = bpy.data.objects.new("txt", cu)
	bpy.context.scene.collection.objects.link(ob)
	dg = bpy.context.evaluated_depsgraph_get()
	me = ob.evaluated_get(dg).to_mesh()
	u, v = Vector(axis_u), Vector(axis_v)
	n = u.cross(v)
	o = Vector(origin)
	ids = [mb.vert(o + u * p.co.x + v * p.co.y + n * p.co.z, col) for p in me.vertices]
	for p in me.polygons:
		fn = u * p.normal.x + v * p.normal.y + n * p.normal.z
		mb.face([ids[i] for i in p.vertices], mat, fn)
	ob.evaluated_get(dg).to_mesh_clear()
	bpy.data.objects.remove(ob)
	bpy.data.curves.remove(cu)


# ---------------------------------------------------------------- export and previews
def export_glb(path, objects):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	for ob in objects:
		ob.select_set(True)
	kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
		export_texcoords=True, export_normals=True, export_tangents=False, export_cameras=False,
		export_lights=False, export_extras=False)
	props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
	if "export_vertex_color" in props:
		kw["export_vertex_color"] = "ACTIVE"
	elif "export_colors" in props:
		kw["export_colors"] = True
	bpy.ops.export_scene.gltf(**kw)
	print("wrote", path, "(%d KB)" % (os.path.getsize(path) // 1024))


def setup_preview(size=(1400, 900), ground=200.0, ground_colour=(0.18, 0.2, 0.17)):
	scene = bpy.context.scene
	for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
		try:
			scene.render.engine = eng
			break
		except TypeError:
			continue
	scene.render.resolution_x, scene.render.resolution_y = size
	world = bpy.data.worlds.new("World")
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs["Color"].default_value = (0.55, 0.65, 0.8, 1)
	bg.inputs["Strength"].default_value = 0.8
	scene.world = world
	sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
	sun.data.energy = 4.0
	sun.data.angle = math.radians(1.0)
	sun.rotation_euler = (math.radians(48), math.radians(12), math.radians(-35))
	scene.collection.objects.link(sun)
	g = ground / 2
	me = bpy.data.meshes.new("Ground")
	me.from_pydata([(-g, -g, 0), (g, -g, 0), (g, g, 0), (-g, g, 0)], [], [(0, 1, 2, 3)])
	gm = bpy.data.materials.new("GroundMat")
	gm.use_nodes = True
	gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*ground_colour, 1)
	me.materials.append(gm)
	scene.collection.objects.link(bpy.data.objects.new("Ground", me))
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	cam.data.clip_end = 2000
	scene.collection.objects.link(cam)
	scene.camera = cam
	return cam


def render(cam, path, eye, target, fov_deg=50.0):
	cam.location = eye
	cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
	cam.data.type = "PERSP"
	cam.data.angle = math.radians(fov_deg)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.context.scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


def place(ob, loc=(0, 0, 0), rot_z=0.0, scale=(1, 1, 1), collection=None):
	"""A linked duplicate of ob for preview scenes (shares the mesh, not exported)."""
	d = bpy.data.objects.new(ob.name + ".view", ob.data)
	d.location = loc
	d.rotation_euler = (0, 0, rot_z)
	d.scale = scale
	(collection or bpy.context.scene.collection).objects.link(d)
	return d
