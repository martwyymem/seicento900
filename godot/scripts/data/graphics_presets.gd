## The four graphics presets (Low, Medium, High, Ultra) and the logic that recognises them again.
## A preset sets the world's rendering level (race_world.gd apply_graphics) plus the settings the Options page
## also exposes one by one (upscaler, anti-aliasing, ambient occlusion, shadows, reflections). Change any of those
## by hand and the settings no longer match a preset: Options shows "Custom".
## Only portable upscaling is used (FSR 1 or none): MetalFX exists on Macs only and stays a manual choice, as do
## FSR 2 and ray-traced reflections. High equals the game's defaults.
class_name GraphicsPresets
extends RefCounted

const NAMES := ["Low", "Medium", "High", "Ultra"]
const CUSTOM := 4 ## index the picker uses for settings that match no preset

## upscaler: index into game.gd UPSCALERS (0 off, 1 FSR 1); upscale_preset: index into UPSCALE_PRESETS (1 Quality 67%,
## 3 Performance 50%); antialiasing: 0 SMAA, 1 FXAA, 2 off; reflections: 0 off, 1 screen-space
## ow_shadow_distance / ow_shadow_splits: the open world's sun shadows; ow_draw_scale: how far its trees and small
## props draw (TownBuilder.set_draw_scale, High's ranges = 1); volumetric_fog: open-world and race fog and sun
## shafts, only where the preset can afford them; car_reflections: a reflection probe follows the player's car
## (CarReflections), so its paint mirrors the street, not only the sky; ssil: screen-space light bounce.
## Medium keeps two shadow cascades and no car reflections (2026-11-10): the open world is bound by draw calls, not
## pixels, so a lower render resolution saves little; the probe's extra cube faces and two more cascades cost more.
const PRESETS := [
	{"quality": 0, "upscaler": 1, "upscale_preset": 3, "antialiasing": 1, "ssao": false, "shadows": true, "reflections": 0,
		"ow_shadow_distance": 120.0, "ow_shadow_splits": 2, "ow_draw_scale": 0.6, "volumetric_fog": false,
		"car_reflections": false, "ssil": false,
		"blurb": "Smoothest on older machines: 50% render resolution with FSR 1, FXAA, no ambient occlusion, short shadows."},
	{"quality": 1, "upscaler": 1, "upscale_preset": 1, "antialiasing": 0, "ssao": true, "shadows": true, "reflections": 0,
		"ow_shadow_distance": 160.0, "ow_shadow_splits": 2, "ow_draw_scale": 0.8, "volumetric_fog": false,
		"car_reflections": false, "ssil": false,
		"blurb": "Balanced: 67% render resolution with FSR 1, SMAA, ambient occlusion."},
	{"quality": 2, "upscaler": 0, "upscale_preset": 1, "antialiasing": 0, "ssao": true, "shadows": true, "reflections": 0,
		"ow_shadow_distance": 260.0, "ow_shadow_splits": 4, "ow_draw_scale": 1.0, "volumetric_fog": false,
		"car_reflections": true, "ssil": false,
		"blurb": "The default: native resolution, SMAA, ambient occlusion, full shadows."},
	{"quality": 3, "upscaler": 0, "upscale_preset": 1, "antialiasing": 0, "ssao": true, "shadows": true, "reflections": 1,
		"ow_shadow_distance": 400.0, "ow_shadow_splits": 4, "ow_draw_scale": 1.25, "volumetric_fog": true,
		"car_reflections": true, "ssil": true,
		"blurb": "Everything on: MSAA, soft sun shadows, screen-space reflections, ambient light bounce and volumetric fog."},
]

static func preset(index: int) -> Dictionary:
	return PRESETS[clampi(index, 0, PRESETS.size() - 1)]

## The preset index whose values equal `s` (a dictionary with the keys quality, upscaler, upscale_preset, antialiasing,
## ssao, shadows, reflections), or CUSTOM. The render-resolution step only counts while an upscaler is on.
static func match_index(s: Dictionary) -> int:
	for i in PRESETS.size():
		var p: Dictionary = PRESETS[i]
		var same := true
		for key in ["quality", "upscaler", "antialiasing", "ssao", "shadows", "reflections"]:
			if s.get(key) != p[key]:
				same = false
				break
		if same and int(p.upscaler) != 0 and s.get("upscale_preset") != p.upscale_preset:
			same = false
		if same:
			return i
	return CUSTOM

static func describe(index: int) -> String:
	return preset(index).blurb if index < PRESETS.size() else "Your own mix of the settings below."

## First run (no graphics.cfg yet): the preset for this machine, from its GPU's name and kind
## (RenderingServer.get_video_adapter_name / get_video_adapter_type, a RenderingDevice.DeviceType) and its CPU cores.
## Never Ultra (a choice for the player); a GPU it does not recognise gets the default, High.
## Software renderers and tiny machines get Low; Intel UHD/HD graphics Low, Iris Medium; other integrated GPUs
## Medium; Apple M1/M2 base chips Medium, every other Apple chip and any discrete GPU High.
static func auto_pick(adapter: String, device_type: int, cores: int) -> int:
	var gpu := adapter.to_lower()
	if device_type == RenderingDevice.DEVICE_TYPE_CPU or device_type == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU \
			or gpu.contains("llvmpipe") or gpu.contains("swiftshader") or gpu.contains("software"):
		return 0
	if cores > 0 and cores < 4:
		return 0
	var apple := RegEx.create_from_string("apple m(\\d+)\\s*(pro|max|ultra)?")
	var m := apple.search(gpu)
	if m:
		var tier := m.get_string(2)
		return 1 if tier == "" and int(m.get_string(1)) <= 2 else 2
	if gpu.contains("intel") and not gpu.contains("arc"):
		if gpu.contains("iris"):
			return 1
		if gpu.contains("uhd") or gpu.contains("hd graphics"):
			return 0
	if device_type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return 1
	return 2
