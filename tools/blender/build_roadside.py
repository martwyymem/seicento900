"""Low-poly roadside details shared by rally and circuit stages.

Run with Blender from the repository root:
    blender -b -P tools/blender/build_roadside.py -- [--renders DIR]

Writes compact, origin-centred meshes to godot/models/roadside.glb.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "roadside.glb")
kit.MATERIALS.update({
	"Wood": ((0.43, 0.25, 0.12), 0.9, 0.0, {}),
	"Leaves": ((0.72, 0.86, 0.63), 0.95, 0.0, {}),
	"Grass": ((0.8, 0.92, 0.67), 0.95, 0.0, {}),
	"Straw": ((0.9, 0.72, 0.34), 0.94, 0.0, {}),
	"Paint": ((0.95, 0.92, 0.84), 0.78, 0.0, {}),
	"Red": ((0.78, 0.12, 0.08), 0.72, 0.0, {}),
	"Concrete": ((0.58, 0.58, 0.53), 0.92, 0.0, {}),
	"Dark": ((0.15, 0.17, 0.16), 0.85, 0.0, {}),
})


def bush():
	m = MB()
	# Three interlocking, faceted crowns read as one low hedge clump at racing speed.
	for x, y, z, r in [(-0.48, 0.0, 0.62, 0.55), (0.05, 0.08, 0.78, 0.67), (0.54, -0.02, 0.6, 0.53)]:
		icosphere(m, (x, y, z), r, "Leaves", 1)
	return m


def icosphere(m, centre, radius, material, subdivisions=1):
	t = (1.0 + math.sqrt(5.0)) / 2.0
	verts = [(-1,t,0),(1,t,0),(-1,-t,0),(1,-t,0),(0,-1,t),(0,1,t),(0,-1,-t),(0,1,-t),(t,0,-1),(t,0,1),(-t,0,-1),(-t,0,1)]
	verts = [[x / math.sqrt(a*a+b*b+c*c), y / math.sqrt(a*a+b*b+c*c), z / math.sqrt(a*a+b*b+c*c)] for x,y,z in verts for a,b,c in [(x,y,z)]]
	faces = [(0,11,5),(0,5,1),(0,1,7),(0,7,10),(0,10,11),(1,5,9),(5,11,4),(11,10,2),(10,7,6),(7,1,8),(3,9,4),(3,4,2),(3,2,6),(3,6,8),(3,8,9),(4,9,5),(2,4,11),(6,2,10),(8,6,7),(9,8,1)]
	for _ in range(subdivisions):
		cache = {}
		def midpoint(i, j):
			key = tuple(sorted((i, j)))
			if key not in cache:
				v = [verts[i][k] + verts[j][k] for k in range(3)]
				n = math.sqrt(sum(x*x for x in v))
				verts.append([x / n for x in v]); cache[key] = len(verts)-1
			return cache[key]
		new_faces = []
		for a,b,c in faces:
			ab,bc,ca = midpoint(a,b),midpoint(b,c),midpoint(c,a)
			new_faces += [(a,ab,ca),(b,bc,ab),(c,ca,bc),(ab,bc,ca)]
		faces = new_faces
		for f in faces:
			m.poly([(centre[0] + verts[i][0]*radius, centre[1] + verts[i][1]*radius, centre[2] + verts[i][2]*radius) for i in f], material)


def grass():
	m = MB()
	# Nine crossed, tapered blades, all in a tight inexpensive tuft.
	for i in range(9):
		a = i * math.pi * 0.618
		x, y = math.cos(a) * 0.13, math.sin(a) * 0.13
		h = 0.42 + (i % 4) * 0.11
		m.prism([(y-0.025,0),(y+0.025,0),(y+0.015,h*0.55),(y+0.006,h)], x-0.012, x+0.012, "Grass")
	return m


def hay_bale():
	m = MB()
	m.lathe([(0.0,0.42),(0.07,0.5),(0.75,0.5),(0.82,0.42)], 10, "Straw")
	# Dark ties on the face distinguish a tied round bale without texturing.
	for angle in (0.8, 2.9, 5.0):
		x, y = math.cos(angle) * 0.505, math.sin(angle) * 0.505
		m.box((x-0.018,y-0.018,0.08),(x+0.018,y+0.018,0.74),"Wood")
	return m


def roadside_cross():
	m = MB()
	m.box((-0.055,-0.055,0.0),(0.055,0.055,1.65),"Wood")
	m.box((-0.38,-0.055,1.22),(0.38,0.055,1.34),"Wood")
	# Small pale cap and stone plinth, a simple Polish wayside cross silhouette.
	m.box((-0.11,-0.1,1.59),(0.11,0.1,1.76),"Paint")
	m.box((-0.24,-0.2,0.0),(0.24,0.2,0.16),"Concrete")
	return m


def kilometre_post():
	m = MB()
	m.box((-0.12,-0.1,0.0),(0.12,0.1,0.8),"Paint")
	m.box((-0.125,-0.105,0.53),(0.125,0.105,0.67),"Red")
	m.box((-0.126,-0.106,0.2),(0.126,0.106,0.27),"Red")
	return m


def rally_board():
	m = MB()
	for x in (-0.62, 0.62):
		m.box((x-0.035,-0.035,0.0),(x+0.035,0.035,1.7),"Wood")
	m.box((-0.7,-0.07,0.95),(0.7,0.07,1.55),"Paint")
	# Broad red bands make the gate visible at distance; deliberately no generated lettering.
	m.box((-0.7,-0.075,0.95),(-0.42,0.075,1.55),"Red")
	m.box((0.42,-0.075,0.95),(0.7,0.075,1.55),"Red")
	return m


def main():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	objects = []
	for name, builder in [("BushCluster", bush), ("TallGrass", grass), ("HayBale", hay_bale),
		("WaysideCross", roadside_cross), ("KilometrePost", kilometre_post), ("RallyBoard", rally_board)]:
		objects.append(builder().emit(name))
	kit.export_glb(OUT_GLB, objects)
	render_dir = kit.arg("--renders")
	if render_dir:
		cam = kit.setup_preview(ground=30.0)
		# A lineup makes silhouettes and relative scale easy to inspect.
		for i, ob in enumerate(objects):
			kit.place(ob, ((i - 2.5) * 3.0, 0.0, 0.0))
		kit.render(cam, os.path.join(render_dir, "roadside.png"), (9, -16, 8), (0, 0, 0), 42.0)


if __name__ == "__main__":
	main()
