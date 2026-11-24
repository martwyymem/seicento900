## The 0.5.9 racing-line chevrons (green: on it, yellow: lift, red: brake) on any Track, as a node of their own:
## RaceWorld's arrows (race_world.gd) (the same chevron mesh, colours, spacing and reach, and the same PaceNotes.fill_arrow_zones
## braking classification) for a world drawn in the track's own metres with real heights, which is the open world's
## (an event's EventTrack). brake_cue() is the HUD's BRAKE call from the same zones (PaceNotes.track_brake_cue).
## Allocation-free per frame: a fixed MultiMesh pool.
class_name RacingArrows
extends MultiMeshInstance3D

const WORLD := preload("res://scripts/ui/race_world.gd")
const LIFT := 0.1 ## m over the road's height along the line (clear of the camber and the road's own lift)

var track: Track
var mode := "full" ## DifficultyProfile line: full (every chevron), braking (yellow and red only), off
var brake_k := 1.0
var brake_aero := 0.0
var start_s := 0.0 ## the chevrons run from here ...
var end_s := INF ## ... to here (a point-to-point route's start and finish)
var _corner_v := PackedFloat64Array()
var _d := PackedFloat64Array() ## the racing line's offsets, smoothed
var _y := PackedFloat64Array() ## its heights, smoothed
var _zones := PackedInt32Array()
var _buf := PackedFloat32Array()
var _mm: MultiMesh

func _init() -> void:
	name = "RacingArrows"
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = WORLD._build_chevron_mesh()
	_mm.instance_count = WORLD.ARROW_POOL
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-50000.0, -5000.0, -50000.0), Vector3(100000.0, 10000.0, 100000.0))
	multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.albedo_color = Color(1.05, 1.05, 1.05, 0.90)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zones.resize(WORLD.ARROW_POOL)
	_buf.resize(WORLD.ARROW_POOL * 16)

## A track to draw on (null clears it). loose: the race's loose spans grip as they look (Race._loose).
func set_track(tr: Track, from_s := 0.0, to_s := INF, k := 1.0, aero := 0.0, loose := false) -> void:
	track = tr
	start_s = from_s
	end_s = to_s
	brake_k = k
	brake_aero = aero
	_mm.visible_instance_count = 0
	if tr == null:
		_corner_v = PackedFloat64Array()
		return
	_corner_v = PaceNotes.corner_profile(tr, k, aero, loose)
	var win := maxi(2, int(round(6.0 / tr.step)))
	_d = _smooth(tr.RLD, win)
	_y = _smooth(tr.H, win)

## The chevrons ahead of a car at s doing v m/s on grip mu.
func update(s: float, v: float, mu: float) -> void:
	if track == null or mode == "off" or not visible:
		_mm.visible_instance_count = 0
		return
	var tr := track
	var reach := minf(WORLD.ARROW_REACH, maxf(end_s - s, 0.0))
	var spacing := WORLD.ARROW_SPACING
	var first_k := ceilf((s + WORLD.ARROW_START) / spacing)
	var s0 := first_k * spacing
	var first_ahead := s0 - s
	var count := clampi(int(floorf((reach - first_ahead) / spacing)) + 1, 0, WORLD.ARROW_POOL)
	if count <= 0:
		_mm.visible_instance_count = 0
		return
	PaceNotes.fill_arrow_zones(tr, _corner_v, s0, spacing, count, maxf(v, 0.0), brake_k, brake_aero, mu, _zones)
	var braking_only := mode == "braking"
	var fade_start := WORLD.ARROW_REACH * 0.65
	var used := 0
	for k in count:
		var zone := _zones[k]
		if braking_only and zone == PaceNotes.BrakeZone.GREEN:
			continue
		var ahead := first_ahead + float(k) * spacing
		var sk := s0 + float(k) * spacing
		var pos := _point(sk)
		var fwd := _point(sk + 1.5) - _point(sk - 1.5)
		var flen := fwd.length()
		if flen < 1e-4:
			continue
		fwd /= flen
		var right := fwd.cross(Vector3.UP)
		var rlen := right.length()
		if rlen < 1e-4:
			continue
		right /= rlen
		var up := right.cross(fwd).normalized()
		var col := WORLD.ARROW_RED if zone == PaceNotes.BrakeZone.RED else (WORLD.ARROW_YELLOW if zone == PaceNotes.BrakeZone.YELLOW else WORLD.ARROW_GREEN)
		var alpha := clampf(smoothstep(WORLD.ARROW_START - 1.0, WORLD.ARROW_START + 5.0, ahead) * (1.0 - smoothstep(fade_start, WORLD.ARROW_REACH, ahead)), 0.0, 1.0)
		if alpha <= 0.01:
			continue
		var o := used * 16
		_buf[o] = right.x; _buf[o + 1] = up.x; _buf[o + 2] = -fwd.x; _buf[o + 3] = pos.x
		_buf[o + 4] = right.y; _buf[o + 5] = up.y; _buf[o + 6] = -fwd.y; _buf[o + 7] = pos.y
		_buf[o + 8] = right.z; _buf[o + 9] = up.z; _buf[o + 10] = -fwd.z; _buf[o + 11] = pos.z
		_buf[o + 12] = col.r; _buf[o + 13] = col.g; _buf[o + 14] = col.b; _buf[o + 15] = alpha
		used += 1
	if used > 0:
		_mm.buffer = _buf
	_mm.visible_instance_count = used

## How many chevrons are up (tests).
func shown() -> int:
	return _mm.visible_instance_count

## The HUD's BRAKE call for a car at s doing v m/s on grip mu, its brake pedal at brake (0..1).
func brake_cue(s: float, v: float, mu: float, brake := 0.0) -> bool:
	if track == null or mode == "off" or s >= end_s:
		return false
	return bool(PaceNotes.track_brake_cue(track, _corner_v, s, v, brake_k, brake_aero, mu, brake).brake)

## The smoothed racing line's point at s, in the world (x, height, y).
func _point(s: float) -> Vector3:
	var tr := track
	var u := tr.wrap_s(s) / tr.step
	var fu := floorf(u)
	var i := int(fu) % tr.n
	var j := (i + 1) % tr.n
	var f := u - fu
	var d := _d[i] + (_d[j] - _d[i]) * f
	var nx := tr.NX[i] + (tr.NX[j] - tr.NX[i]) * f
	var ny := tr.NY[i] + (tr.NY[j] - tr.NY[i]) * f
	return Vector3(tr.X[i] + (tr.X[j] - tr.X[i]) * f + nx * d, _y[i] + (_y[j] - _y[i]) * f + LIFT, tr.Y[i] + (tr.Y[j] - tr.Y[i]) * f + ny * d)

static func _smooth(src: PackedFloat64Array, win: int) -> PackedFloat64Array:
	var n := src.size()
	var cur := src
	for pass_i in 2:
		var out := PackedFloat64Array()
		out.resize(n)
		var acc := 0.0
		for k in range(-win, win + 1):
			acc += cur[posmod(k, n)]
		for i in n:
			out[i] = acc / float(2 * win + 1)
			acc += cur[posmod(i + win + 1, n)] - cur[posmod(i - win, n)]
		cur = out
	return cur
