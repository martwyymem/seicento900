// Car headlamp reflector/projector (the "Headlight" surface of the Details mesh): clean metallic chrome parabolic dish
// by day (no concentric rings or spirals), and a warm luminous optics core at night driven by the per-car instance
// uniform "lit" (RaceCarVisual.set_lamps: 0 off, 3.6 full). On twin-bowl cars (twin_bowl = 1) the 3D concave bowl
// normals drive the reflector shading; on the Seicento (twin_bowl = 0) the dish centres smoothly on "centre".
shader_type spatial;
#include "res://shaders/car_damage.gdshaderinc"

instance uniform float lit : instance_index(2) = 0.0;
uniform vec2 centre = vec2(0.40, 0.640);
uniform vec2 lamp_half = vec2(0.18, 0.055);
uniform float twin_bowl = 0.0;
uniform vec3 beam : source_color = vec3(1.0, 0.94, 0.80);
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float nv = clamp(dot(n, v), 0.0, 1.0);
	vec2 u = (vec2(abs(lp.x), lp.y) - centre) / max(lamp_half, vec2(0.025));

	// By day: clean polished chrome reflector / projector optics with natural bowl depth (no rings or spirals)
	float bowl_depth = smoothstep(0.10, 0.92, nv);
	float optic_glint = pow(nv, 7.0);
	float single_dish = exp(-dot(u * vec2(0.85, 1.0), u * vec2(0.85, 1.0)) * 1.25);
	float sheen = mix(0.28 + 0.72 * single_dish * (0.45 + 0.55 * nv), bowl_depth, twin_bowl);

	vec3 chrome = mix(vec3(0.26, 0.28, 0.31), vec3(0.76, 0.79, 0.84), sheen);
	chrome += vec3(0.14, 0.16, 0.20) * optic_glint * mix(single_dish, 1.0, twin_bowl);

	ALBEDO = chrome;
	METALLIC = 0.92;
	ROUGHNESS = mix(0.22, 0.08, sheen);

	// At night: rich warm-white headlamp glow filling the reflector/bowl with a hot optical core
	float side_bias = mix(0.74, 1.12, smoothstep(-0.35, 0.45, u.x));
	float bowl_emit = side_bias * (0.42 + 0.68 * pow(nv, 1.25));
	float single_emit = 0.38 + 0.82 * exp(-dot(u * vec2(0.60, 0.80), u * vec2(0.60, 0.80)) * 1.05);
	float strength = mix(single_emit, bowl_emit, twin_bowl);
	float core_hot = mix(single_dish, pow(nv, 2.2), twin_bowl);
	vec3 lit_col = mix(beam * vec3(1.0, 0.90, 0.72), vec3(1.0, 0.98, 0.94), core_hot * 0.75);
	// smashed (car_damage.gdshaderinc): the bulb is out and the bowl dull, scratched and dirty
	float smashed = lamp_smashed(lp);
	ALBEDO = mix(ALBEDO, vec3(0.12, 0.12, 0.13) + 0.25 * crack_lines(lp.xy, 30.0), smashed * 0.8);
	ROUGHNESS = mix(ROUGHNESS, 0.6, smashed);
	EMISSION = lit_col * lit * strength * (1.0 - smashed);
}
