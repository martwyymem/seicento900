// Headlamp inner reflector housing/bezel ("LampBezel" surface of the Details mesh on twin-bowl cars): clean satin
// metallic housing by day, catching warm reflected bounce light from the lit bulbs at night so the whole lamp unit
// reads as an illuminated headlamp assembly rather than isolated white dots.
shader_type spatial;
#include "res://shaders/car_damage.gdshaderinc"

instance uniform float lit : instance_index(2) = 0.0;
uniform vec2 centre = vec2(0.55, 0.68);
uniform vec2 lamp_half = vec2(0.16, 0.055);
uniform vec3 base_color : source_color = vec3(0.16, 0.17, 0.185);
uniform vec3 beam : source_color = vec3(1.0, 0.93, 0.78);
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float nv = clamp(dot(n, v), 0.0, 1.0);

	// Distance to the horizontal span covering both reflector bowls inside the housing
	vec2 p = vec2(abs(lp.x), lp.y);
	float dx = max(abs(p.x - centre.x) - lamp_half.x * 0.52, 0.0) / max(lamp_half.x * 0.85, 0.05);
	float dy = (p.y - centre.y) / max(lamp_half.y * 1.25, 0.04);
	float d2 = dx * dx + dy * dy;

	// By day: refined satin gunmetal-chrome bezel with gentle depth shading
	ALBEDO = base_color * (0.85 + 0.30 * nv);
	METALLIC = 0.78;
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;

	// At night: warm internal light spill across the housing, brightest around the bowls and fading softly into the swept corners
	float spill = exp(-d2 * 1.65);
	float ambient_fill = exp(-d2 * 0.42);
	vec3 warm = mix(beam * vec3(1.0, 0.86, 0.64), beam, spill);
	EMISSION = warm * lit * (0.17 * spill + 0.032 * ambient_fill) * (0.72 + 0.28 * nv) * (1.0 - lamp_smashed(lp));
}
