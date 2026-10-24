## Sun lens flare in the manner of CMR 2.0 and Firebrand's WRC (scripts/config/sunflare.lua there): a soft
## glow and a wide warm halo on the sun, a faint streak, and a chain of pale hexagonal ghosts along the line
## from the sun through the middle of the picture. Lives in the race viewport (a child of race_world), so it
## goes through the retro styles and stays under the HUD. It shows only while the race camera looks towards a
## sun that is up and not behind cloud, rain or fog; the shader hides it when something in the picture covers
## the sun. The shapes are drawn here once, so it costs a dozen small quads a frame and nothing when unseen.
class_name LensFlare
extends CanvasLayer

const SHADER := preload("res://shaders/lens_flare.gdshader")

const GLOW := 0
const HALO := 1
const HEX := 2
const RING := 3
const STREAK := 4

## [shape, place along the sun-to-centre line (0 the sun, 1 the middle, 2 the mirror point), size as a fraction
## of the picture height, colour]. The colours follow WRC's warm 76/51/25 and 51/51/25 ghosts, a little cooler
## towards the far side as a real lens's coatings tint them.
const ELEMENTS := [
	[HALO, 0.0, 1.25, Color(0.30, 0.20, 0.10)],
	[GLOW, 0.0, 0.32, Color(0.60, 0.54, 0.44)],
	[STREAK, 0.0, 0.9, Color(0.34, 0.27, 0.18)],
	[HEX, -0.18, 0.035, Color(0.20, 0.15, 0.08)],
	[HEX, 0.22, 0.045, Color(0.22, 0.15, 0.07)],
	[HEX, 0.4, 0.075, Color(0.15, 0.15, 0.07)],
	[HEX, 0.58, 0.1, Color(0.13, 0.13, 0.07)],
	[RING, 0.9, 0.06, Color(0.16, 0.12, 0.06)],
	[HEX, 1.22, 0.13, Color(0.09, 0.12, 0.08)],
	[HEX, 1.5, 0.08, Color(0.16, 0.11, 0.06)],
	[RING, 1.85, 0.2, Color(0.06, 0.08, 0.11)],
	[HEX, 2.15, 0.055, Color(0.15, 0.11, 0.07)],
]

static var _textures: Array[Texture2D] = []

var strength := 0.0 ## 0..1 after the weather, the hour and the view; eased so it does not pop
var _sun_px := Vector2.ZERO
var _height := 1.0
var _canvas: Node2D
var _copy: BackBufferCopy
var _material: ShaderMaterial

func _ready() -> void:
	layer = 0 # inside the race viewport: over the 3D, which is all this canvas holds
	if _textures.is_empty():
		_textures = [_disc(128, 2.2), _disc(128, 1.0), _hex(64), _ring(64), _disc(64, 1.4)]
	_copy = BackBufferCopy.new()
	_copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
	add_child(_copy)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_canvas = Node2D.new()
	_canvas.material = _material
	_canvas.draw.connect(_draw_flare)
	add_child(_canvas)
	_canvas.visible = false

func _process(delta: float) -> void:
	var want := _target()
	strength += (want - strength) * (1.0 - exp(-(6.0 if want < strength else 3.0) * delta))
	var on := strength > 0.01
	_canvas.visible = on
	_copy.visible = on
	if on:
		_canvas.queue_redraw()

## How strong the flare should be now (0 when it should not show), setting _sun_px on the way.
func _target() -> float:
	var world := get_parent()
	var camera: Camera3D = world.get("camera")
	var sky: ShaderMaterial = world.get("sky_material")
	var race = world.get("race")
	if not camera or not sky or not race or world.get("overview") or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return 0.0
	var sun_dir: Vector3 = sky.get_shader_parameter("sun_dir")
	if sun_dir == null or sun_dir.length_squared() < 0.01:
		return 0.0
	sun_dir = sun_dir.normalized()
	# up over the horizon and the hills' line, out of the dark, through clear air
	var amount := smoothstep(-0.01, 0.06, sun_dir.y) * (1.0 - smoothstep(0.1, 0.5, float(world.get("night"))))
	var overcast := float(sky.get_shader_parameter("overcast"))
	amount *= 1.0 - smoothstep(0.12, 0.45, overcast)
	var weather = race.weather
	amount *= 1.0 - smoothstep(0.03, 0.25, maxf(weather.rain, maxf(weather.snow, weather.hail)))
	amount *= 1.0 - smoothstep(0.05, 0.3, weather.fog)
	if weather.mode == "fog" or amount < 0.01:
		return 0.0
	var eye := camera.global_position
	var far := eye + sun_dir * 1000.0
	if camera.is_position_behind(far):
		return 0.0
	var size := get_viewport().get_visible_rect().size
	_sun_px = camera.unproject_position(far)
	_height = size.y
	# fades out as the sun nears the edge of the picture rather than snapping off there
	var margin := size.y * 0.08
	var inside := minf(minf(_sun_px.x, size.x - _sun_px.x), minf(_sun_px.y, size.y - _sun_px.y))
	amount *= smoothstep(-margin * 0.5, margin, inside)
	var tap_px := maxf(3.0, size.y * 0.007)
	_material.set_shader_parameter("sun_uv", _sun_px / size)
	_material.set_shader_parameter("tap", Vector2(tap_px / size.x, tap_px / size.y))
	_copy.rect = Rect2(_sun_px - Vector2(tap_px, tap_px) * 2.0, Vector2(tap_px, tap_px) * 4.0)
	return amount

func _draw_flare() -> void:
	var size := get_viewport().get_visible_rect().size
	var centre := size * 0.5
	var axis := centre - _sun_px
	# ghosts brighten as the sun comes towards the middle of the lens, as a real one's do
	var ghosts := strength * lerpf(0.55, 1.0, 1.0 - clampf(axis.length() / (size.y * 0.9), 0.0, 1.0))
	for e in ELEMENTS:
		var shape: int = e[0]
		var at: Vector2 = _sun_px + axis * float(e[1])
		var h: float = float(e[2]) * _height
		var c: Color = e[3]
		var k := ghosts if shape in [HEX, RING] else strength
		c = Color(c.r * k, c.g * k, c.b * k, 1.0) # additive: the colour alone sets the strength
		var r := Rect2(at - Vector2(h, h) * 0.5, Vector2(h, h))
		if shape == STREAK:
			r = Rect2(at - Vector2(h, h * 0.035) * 0.5, Vector2(h, h * 0.035))
		_canvas.draw_texture_rect(_textures[shape], r, false, c)

## A round soft spot, falling off with exponent `power` (higher is tighter).
static func _disc(n: int, power: float) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var v := pow(maxf(0.0, 1.0 - d), power)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)

## A hexagonal aperture ghost: an even fill, a slightly brighter rim and a soft edge.
static func _hex(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).abs() / (n * 0.5)
			var d := maxf(p.x * 0.866 + p.y * 0.5, p.y) # distance to the hexagon's sides, 1 on them
			var v := (0.55 + 0.45 * smoothstep(0.7, 0.92, d)) * (1.0 - smoothstep(0.9, 0.98, d))
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)

## A thin soft ring, like the halo a lens throws far across the picture.
static func _ring(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var v := exp(-pow((d - 0.82) / 0.07, 2.0)) + 0.12 * (1.0 - smoothstep(0.0, 0.85, d))
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)
