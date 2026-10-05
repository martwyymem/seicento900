## The translucent car that drives the player's record lap on this circuit (LapRecords) whenever the player is on
## a flying lap, starting with them at the line. G shows or hides it; the choice is remembered separately for
## driving alone (qualifying, or no opponents) and for racing. It lives outside the world's cars_root, so it
## takes no part in ray-traced reflections.
class_name LapGhost
extends Node3D

const CAR_SCENE := preload("res://scripts/ui/race_car_visual.tscn")
const WORLD := preload("res://scripts/ui/race_world.gd")
const TICK := 1.0 / 120.0
const SEE_THROUGH := 0.55 ## transparency of the ghost at a distance
const SEE_THROUGH_NEAR := 0.85 ## and when it is on top of the player's car
const NEAR := 2.0 ## m between the cars where it is faintest
const FAR := 10.0 ## m from where it is at its plainest

var world: Node3D
var records: LapRecords
var enabled := true
var _visual: Node3D
var _parts: Array[GeometryInstance3D] = []
var _see_through := -1.0
var _car := RaceCar.new() ## the pose handed to the visual each frame

func _ready() -> void:
	visible = false
	_visual = CAR_SCENE.instantiate()
	add_child(_visual)
	for gi in _visual.find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parts.append(gi)
	_car.control = "rail"

## Follow a race on screen. Pass null to stop.
func start(world_: Node3D, records_: LapRecords) -> void:
	world = world_
	records = records_
	visible = false
	if not records:
		return
	var p := records.race.player
	_visual.set_paint(p.color)
	_visual.car_number = p.number
	_visual.set_stripes(p.stripes)
	enabled = LapRecords.ghost_shown(solo())

## Qualifying, or a race without opponents.
func solo() -> bool:
	return records != null and (records.race.s.qualifying or records.race.cars.size() == 1)

## Shows or hides the ghost and remembers the choice; returns a line for the event feed.
func toggle() -> String:
	if not records:
		return ""
	enabled = not enabled
	LapRecords.set_ghost_shown(solo(), enabled)
	if not enabled:
		return "Ghost car off"
	if records.ghost_time == null:
		return "Ghost car on: set a %s lap record here and it will chase you" % records.conditions
	return "Ghost car on: your %s record, %s" % [records.conditions, Race.fmt_time(records.ghost_time)]

func _process(delta: float) -> void:
	var race: Race = records.race if records else null
	var pose := []
	if enabled and race and world and world.race == race and not world.overview and records.chasing():
		var lap_t: float = race.race_time - race.player.lap_start - (1.0 - clampf(world.render_alpha, 0.0, 1.0)) * TICK
		pose = records.pose(lap_t)
	visible = not pose.is_empty()
	if not visible:
		return
	var tr: Track = world.track
	var heading: float = pose[2]
	var s: float = pose[3]
	var d: float = pose[4]
	var p: Vector3 = world._world_pos(pose[0], pose[1], s, d)
	_visual.position = p
	var grade := atan(tr.sample(tr.GRADE, s) * WORLD.ALTITUDE_SCALE * cos(heading - tr.heading(s)))
	_visual.grade_pitch += (grade - _visual.grade_pitch) * minf(1.0, delta * 8.0)
	_visual.basis = world._surface_tilt(s, d) * Basis(Vector3.UP, -heading - PI / 2.0) * Basis(Vector3.RIGHT, _visual.grade_pitch)
	_car.v = pose[5]
	_car.speed = pose[5]
	_car.brake_on = pose[6] > 0.5
	_car.throttle = 0.0 if _car.brake_on else 1.0
	_visual.sync(_car, delta, tr.curvature(s), world.night, false)

	# fade out further as it closes on the player's own car, so it never hides the road ahead
	var me := race.player
	var gap := Vector2(pose[0] - me.x, pose[1] - me.y).length()
	var see := lerpf(SEE_THROUGH_NEAR, SEE_THROUGH, clampf((gap - NEAR) / (FAR - NEAR), 0.0, 1.0))
	if absf(see - _see_through) > 0.01:
		_see_through = see
		for gi in _parts:
			gi.transparency = see
