// The Seicento's headlamp reflector (the "Headlight" surface of the Details mesh): dark chrome in concentric facets
// round the bulb, which lights with the headlamps (the per-car instance uniform "lit", set by RaceCarVisual.set_lamps:
// 0 off, 3.6 full). Found from vertex positions because the model has no UVs: "centre" is the middle of the right-hand
// lamp in the model's frame (RaceCarVisual._lamp_centre). The clear cover over it is the LampGlass surface.
shader_type spatial;

instance uniform float lit : instance_index(2) = 0.0;
uniform vec2 centre = vec2(0.40, 0.640);
uniform vec3 beam : source_color = vec3(1.0, 0.93, 0.78);
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = (vec2(abs(lp.x), lp.y) - centre) * vec2(1.0, 2.2);
	float d = length(q);
	float w = fwidth(d) * 330.0;
	float band = sin(d * 330.0) * 0.5 + 0.5;
	band = mix(smoothstep(0.3, 0.7, band), 0.5, smoothstep(0.5, 1.5, w));
	vec3 chrome = mix(vec3(0.20, 0.205, 0.215), vec3(0.52, 0.53, 0.56), band);
	float hot = exp(-d * 7.0);
	ALBEDO = chrome;
	METALLIC = 1.0;
	ROUGHNESS = mix(0.10, 0.34, band);
	EMISSION = beam * lit * (0.25 + 0.75 * hot + 0.25 * band);
}
