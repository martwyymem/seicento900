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
## ow_shadow_distance / ow_shadow_splits: the open world's sun shadows; volumetric_fog: open-world and race fog and sun
## shafts, only where the preset can afford them
const PRESETS := [
	{"quality": 0, "upscaler": 1, "upscale_preset": 3, "antialiasing": 1, "ssao": false, "shadows": true, "reflections": 0,
		"ow_shadow_distance": 120.0, "ow_shadow_splits": 2, "volumetric_fog": false,
		"blurb": "Smoothest on older machines: 50% render resolution with FSR 1, FXAA, no ambient occlusion, short shadows."},
	{"quality": 1, "upscaler": 1, "upscale_preset": 1, "antialiasing": 0, "ssao": true, "shadows": true, "reflections": 0,
		"ow_shadow_distance": 190.0, "ow_shadow_splits": 4, "volumetric_fog": false,
		"blurb": "Balanced: 67% render resolution with FSR 1, SMAA, ambient occlusion."},
	{"quality": 2, "upscaler": 0, "upscale_preset": 1, "antialiasing": 0, "ssao": true, "shadows": true, "reflections": 0,
		"ow_shadow_distance": 260.0, "ow_shadow_splits": 4, "volumetric_fog": false,
		"blurb": "The default: native resolution, SMAA, ambient occlusion, full shadows."},
	{"quality": 3, "upscaler": 0, "upscale_preset": 1, "antialiasing": 0, "ssao": true, "shadows": true, "reflections": 1,
		"ow_shadow_distance": 400.0, "ow_shadow_splits": 4, "volumetric_fog": true,
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
