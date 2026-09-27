## Track geometry: centreline, racing line, speed profile and pit lane (port of js/track.js).
## Coordinates are the JS/2D frame (x east, y south); the renderer maps them to Godot X/Z.
class_name Track
extends RefCounted

const G := 9.81

var cfg: TrackDef
var key := ""
var name := ""
var width := 0.0
var half := 0.0
var n := 0
var step := 0.0
var L := 0.0
var grid = null ## start-line grid info from the OSM data, if any
var tunnels: Array = []
var h_min := 0.0
var h_max := 0.0

var X := PackedFloat64Array()
var Y := PackedFloat64Array()
var H := PackedFloat64Array() ## elevation above sea level (m)
var GRADE := PackedFloat64Array() ## road gradient along the direction of travel (rise over run)
var TX := PackedFloat64Array()
var TY := PackedFloat64Array()
var NX := PackedFloat64Array()
var NY := PackedFloat64Array()
var ANG := PackedFloat64Array()
var KC := PackedFloat64Array() ## centreline curvature (+ = turning right on screen)
var KP := PackedFloat64Array() ## peak curvature around each sample
var RLD := PackedFloat64Array() ## racing line: lateral offset from the centreline
var RX := PackedFloat64Array()
var RY := PackedFloat64Array()
var RDS := PackedFloat64Array() ## path length from sample i to i+1 along the racing line
var RK := PackedFloat64Array() ## racing-line curvature
var CORNER := PackedFloat64Array() ## cornering speed limit at mu = 1
var PROF := PackedFloat64Array() ## max speed at mu = 1: cornering limit + braking envelope
var rl_length := 0.0
var sectors: Array = [] ## [[sample index, name]] sorted by index
var bounds := PackedFloat64Array() ## [min_x, min_y, max_x, max_y]
var cal: Dictionary = {} ## strategy calibration, filled lazily by Strategy

static func load_def(track_key: String) -> TrackDef:
	return load("res://data/tracks/%s.tres" % track_key)

func _init(def: TrackDef) -> void:
	cfg = def
	key = def.key
	name = def.display_name
	width = def.width
	half = width / 2
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/%s.json" % key))
	var pts: Array = raw.pts
	n = pts.size() / 2
	step = raw.step
	L = n * step
	var off := SimUtil.js_round(def.start_offset / step)
	var elev = raw.get("elev")
	X.resize(n)
	Y.resize(n)
	H.resize(n)
	for i in n:
		var j := (i + off) % n
		X[i] = pts[2 * j]
		Y[i] = pts[2 * j + 1]
		H[i] = elev[j] if elev else 0.0
	grid = raw.get("grid")
	tunnels = raw.get("tunnels", [])
	h_min = INF
	h_max = -INF
	for h in H:
		h_min = minf(h_min, h)
		h_max = maxf(h_max, h)
	GRADE.resize(n)
	var gw := 5
	for i in n:
		GRADE[i] = (H[(i + gw) % n] - H[(i - gw + n) % n]) / (2 * gw * step)
	# section names: [index, name, insertion order] so equal indices keep the JS (stable) order
	var sec := []
	if def.osm_names:
		for e in raw.names:
			sec.append([posmod(int(e[0]) - off, n), e[1], sec.size()])
	for c in def.corners:
		sec.append([posmod(SimUtil.js_round(c.distance / step) - off, n), c.name, sec.size()])
	sec.sort_custom(func(p, q): return p[0] < q[0] or (p[0] == q[0] and p[2] < q[2]))
	for e in sec:
		sectors.append([e[0], e[1]])

	build_frames()
	build_corner_envelope()
	build_racing_line()
	build_profile()
	build_bounds()

func build_frames() -> void:
	TX.resize(n)
	TY.resize(n)
	NX.resize(n)
	NY.resize(n)
	ANG.resize(n)
	KC.resize(n)
	for i in n:
		var a := (i - 1 + n) % n
		var b := (i + 1) % n
		var tx := X[b] - X[a]
		var ty := Y[b] - Y[a]
		var l := sqrt(tx * tx + ty * ty)
		if l == 0.0:
			l = 1.0
		tx /= l
		ty /= l
		TX[i] = tx
		TY[i] = ty
		NX[i] = -ty
		NY[i] = tx
		ANG[i] = atan2(ty, tx)
	var m := 4
	for i in n:
		var da := SimUtil.wrap_angle(ANG[(i + m) % n] - ANG[(i - m + n) % n])
		KC[i] = da / (2 * m * step)

## Peak curvature around each sample, so side offsets can be kept inside the corner radius.
func build_corner_envelope() -> void:
	KP.resize(n)
	var w := 8
	for i in n:
		var best := 0.0
		for q in range(-w, w + 1):
			var k := KC[(i + q + n) % n]
			if absf(k) > absf(best):
				best = k
		KP[i] = best

## Lateral offset pulled in on the inside of tight corners so offset lines (run-off edges, barriers)
## never fold back through the track.
func clamp_d(s: float, d: float) -> float:
	var k := KP[int(floorf(wrap_s(s) / step)) % n]
	if k * d <= 0.0:
		return d
	var lim := maxf(half + 1.2, 0.8 / absf(k))
	return signf(d) * lim if absf(d) > lim else d

## Iterative relaxation towards a short, low-curvature line inside the track limits.
func build_racing_line() -> void:
	var d := PackedFloat64Array()
	d.resize(n)
	d.fill(0.0)
	var lim := half - 1.25
	for pass_ in [[30, 120], [12, 120], [5, 80]]:
		var k: int = pass_[0]
		for it in pass_[1]:
			for i in n:
				var a := (i - k + n) % n
				var b := (i + k) % n
				var px := (X[a] + NX[a] * d[a] + X[b] + NX[b] * d[b]) / 2
				var py := (Y[a] + NY[a] * d[a] + Y[b] + NY[b] * d[b]) / 2
				var dn := (px - X[i]) * NX[i] + (py - Y[i]) * NY[i]
				var v := d[i] + (dn - d[i]) * 0.6
				d[i] = lim if v > lim else (-lim if v < -lim else v)
	RLD = d
	RX.resize(n)
	RY.resize(n)
	for i in n:
		RX[i] = X[i] + NX[i] * d[i]
		RY[i] = Y[i] + NY[i] * d[i]
	RDS.resize(n)
	var ang := PackedFloat64Array()
	ang.resize(n)
	for i in n:
		var j := (i + 1) % n
		var dx := RX[j] - RX[i]
		var dy := RY[j] - RY[i]
		RDS[i] = sqrt(dx * dx + dy * dy)
		ang[i] = atan2(dy, dx)
	var k := PackedFloat64Array()
	k.resize(n)
	var m := 3
	for i in n:
		var len := 0.0
		for q in range(-m, m):
			len += RDS[(i + q + n) % n]
		k[i] = SimUtil.wrap_angle(ang[(i + m) % n] - ang[(i - m + n) % n]) / len
	for pass_ in 2:
		var k2 := PackedFloat64Array()
		k2.resize(n)
		for i in n:
			k2[i] = (k[(i - 1 + n) % n] + k[i] + k[(i + 1) % n]) / 3
		k = k2
	RK = k
	rl_length = 0.0
	for x in RDS:
		rl_length += x

## Max speed at mu = 1 along the racing line: cornering limit + braking envelope.
func build_profile() -> void:
	var vcap := 60.0
	var p := PackedFloat64Array()
	p.resize(n)
	for i in n:
		p[i] = minf(vcap, sqrt(G / maxf(absf(RK[i]), 1e-5)))
	CORNER = p.duplicate()
	for pass_ in 2:
		for q in range(n - 1, -1, -1):
			var j := (q + 1) % n
			var a_brake := G * maxf(0.5, 0.92 + GRADE[q]) # braking uphill is easier
			var lim := sqrt(p[j] * p[j] + 2 * a_brake * RDS[q])
			if p[q] > lim:
				p[q] = lim
	PROF = p

func build_bounds() -> void:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for i in n:
		min_x = minf(min_x, X[i])
		max_x = maxf(max_x, X[i])
		min_y = minf(min_y, Y[i])
		max_y = maxf(max_y, Y[i])
	bounds = PackedFloat64Array([min_x, min_y, max_x, max_y])

# ---------- lookups ----------

func wrap_s(s: float) -> float:
	return fmod(fmod(s, L) + L, L)

## Signed distance in (-L/2, L/2].
func rel(s: float) -> float:
	return fmod(fmod(s + L / 2, L) + L, L) - L / 2

func sample(arr: PackedFloat64Array, s: float) -> float:
	var u := wrap_s(s) / step
	var fu := floorf(u)
	var i := int(fu) % n
	return arr[i] + (arr[(i + 1) % n] - arr[i]) * (u - fu)

## World position at centreline distance s and lateral offset d: [x, y].
func pos(s: float, d: float) -> PackedFloat64Array:
	var u := wrap_s(s) / step
	var fu := floorf(u)
	var i := int(fu) % n
	var j := (i + 1) % n
	var f := u - fu
	var nx := NX[i] + (NX[j] - NX[i]) * f
	var ny := NY[i] + (NY[j] - NY[i]) * f
	return PackedFloat64Array([X[i] + (X[j] - X[i]) * f + nx * d, Y[i] + (Y[j] - Y[i]) * f + ny * d])

func heading(s: float) -> float:
	var u := wrap_s(s) / step
	var fu := floorf(u)
	var i := int(fu) % n
	var j := (i + 1) % n
	return ANG[i] + SimUtil.wrap_angle(ANG[j] - ANG[i]) * (u - fu)

func curvature(s: float) -> float:
	return sample(KC, s)

## Speed along the centreline parameter for a path offset d (Frenet: ds/dt = v / (1 - k d)).
func s_rate(s: float, d: float) -> float:
	var f := 1.0 - curvature(s) * d
	return 1.0 / maxf(0.5, minf(1.5, f))

## Nearest centreline point: [s, d, dist]. hint_s (>= 0) limits the search window so crossings never
## jump sections; pass NAN to search the whole track.
func project(x: float, y: float, hint_s := NAN) -> PackedFloat64Array:
	var bi := 0
	var bd := INF
	if is_nan(hint_s):
		for i in n:
			var dd := (X[i] - x) * (X[i] - x) + (Y[i] - y) * (Y[i] - y)
			if dd < bd:
				bd = dd
				bi = i
	else:
		var c := SimUtil.js_round(wrap_s(hint_s) / step)
		for k in range(-40, 41):
			var i := posmod(c + k, n)
			var dd := (X[i] - x) * (X[i] - x) + (Y[i] - y) * (Y[i] - y)
			if dd < bd:
				bd = dd
				bi = i
	# refine on the neighbouring segments
	var best_s := bi * step
	var best_d := 0.0
	var best_dist := INF
	for i in [(bi - 1 + n) % n, bi]:
		var j: int = (i + 1) % n
		var sx := X[j] - X[i]
		var sy := Y[j] - Y[i]
		var l2 := sx * sx + sy * sy
		var t := ((x - X[i]) * sx + (y - Y[i]) * sy) / l2
		t = maxf(0.0, minf(1.0, t))
		var px := X[i] + sx * t
		var py := Y[i] + sy * t
		var dist := sqrt((x - px) * (x - px) + (y - py) * (y - py))
		if dist < best_dist:
			var nx := NX[i] + (NX[j] - NX[i]) * t
			var ny := NY[i] + (NY[j] - NY[i]) * t
			best_s = (i + t) * step
			best_d = (x - px) * nx + (y - py) * ny
			best_dist = dist
	return PackedFloat64Array([best_s, best_d, best_dist])

func sector_name(s: float) -> String:
	var i := int(floorf(wrap_s(s) / step))
	var nm: String = sectors[-1][1] if sectors.size() else ""
	for e in sectors:
		if e[0] <= i:
			nm = e[1]
		else:
			break
	return nm

# ---------- pit lane ----------

var lane_start: float:
	get: return cfg.pit_entry + cfg.pit_ramp
var lane_end: float:
	get: return cfg.pit_exit - cfg.pit_ramp
var wall_d: float:
	get: return (half + absf(cfg.pit_offset) - 2.5) / 2

func pit_blend(s: float) -> float:
	var p := rel(s)
	var c := cfg
	if p < c.pit_entry or p > c.pit_exit:
		return 0.0
	if p < c.pit_entry + c.pit_ramp:
		return SimUtil.smooth01((p - c.pit_entry) / c.pit_ramp)
	if p > c.pit_exit - c.pit_ramp:
		return SimUtil.smooth01((c.pit_exit - p) / c.pit_ramp)
	return 1.0

func box_s(i: int) -> float:
	return cfg.box_start + i * cfg.box_spacing

## Lateral barrier limits for a free-driving car at s: [lo, hi].
func limits(s: float) -> PackedFloat64Array:
	var p := rel(s)
	var c := cfg
	var lo := clamp_d(s, -(half + c.runoff))
	var hi := clamp_d(s, half + c.runoff)
	var in_wall := p > c.pit_entry + c.pit_ramp * 0.55 and p < c.pit_exit - c.pit_ramp * 0.55
	if in_wall:
		if c.pit_offset > 0.0:
			hi = minf(hi, wall_d - 0.3)
		else:
			lo = maxf(lo, -wall_d + 0.3)
	return PackedFloat64Array([lo, hi])
