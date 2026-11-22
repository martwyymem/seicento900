// Clear polycarbonate headlamp cover ("LampGlass" surface of the Details mesh): crystal clear with a hard clearcoat
// sheen by day (car_coat.gdshader runs as next_pass for sky reflections), and a soft internal light-scatter veil on the
// front headlamps (lp.z < 0) at night so the whole lamp unit glows smoothly without affecting rear clear tail lenses.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
#include "res://shaders/car_damage.gdshaderinc"

instance uniform float lit : instance_index(2) = 0.0;
uniform vec2 centre = vec2(0.55, 0.68);
uniform vec2 lamp_half = vec2(0.16, 0.055);
uniform vec3 beam : source_color = vec3(1.0, 0.94, 0.82);
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float nv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - nv, 4.0);

	// Only front headlamps scatter headlight glow; rear clear tail-lamp lenses (lp.z > 0) stay clear
	float is_front = step(lp.z, 0.0);
	float on = clamp(lit / 3.6, 0.0, 1.0) * is_front;

	vec2 p = vec2(abs(lp.x), lp.y);
	float dx = max(abs(p.x - centre.x) - lamp_half.x * 0.50, 0.0) / max(lamp_half.x * 0.82, 0.05);
	float dy = (p.y - centre.y) / max(lamp_half.y * 1.15, 0.04);
	float spill = exp(-(dx * dx + dy * dy) * 1.65);

	ALBEDO = mix(vec3(0.86, 0.92, 1.0), beam, on * spill * 0.55);
	ALPHA = clamp(mix(0.045, 0.14, fresnel) + on * (0.13 * spill + 0.04 * fresnel), 0.0, 0.85);
	ROUGHNESS = 0.02;
	SPECULAR = 1.0;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.0;
	EMISSION = beam * lit * (0.13 * spill + 0.025 * fresnel) * is_front;
	// smashed (car_damage.gdshaderinc): the cover is crazed white round its holes and the glow goes out
	float smashed = lamp_smashed(lp);
	if (smashed > 0.0) {
		float cr = crack_lines(lp.xy + lp.z * 0.3, 34.0);
		ALBEDO = mix(ALBEDO, vec3(0.92), cr * smashed);
		ALPHA = mix(ALPHA, 0.75, cr * smashed);
		EMISSION *= 1.0 - smashed;
	}
}
