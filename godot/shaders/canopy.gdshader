// The top of a wood seen from a distance (surroundings.gd): a lumpy sheet of crowns over the forest
// polygons from OpenStreetMap, beyond the trees drawn one by one near the circuit. Faceted lighting from the
// mesh's own lumps; colour patches from noise, conifers darker and bluer than broadleaves.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec3 conifer_color : source_color = vec3(0.13, 0.22, 0.14);
uniform vec3 broadleaf_color : source_color = vec3(0.24, 0.34, 0.16);
uniform float conifer_share = 0.5;
uniform float wet = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
	if (n.y < 0.0) {
		n = -n;
	}
	// crowns: fine bumps on top of the mesh's lumps
	vec2 p = world_pos.xz;
	float fine = texture(grain, p * 0.21).r;
	float crowns = texture(grain, p * 0.07 + 0.3).r;
	float stands = texture(grain, p * 0.006 + 0.7).r;
	n = normalize(n + vec3(fine - 0.5, 0.0, crowns - 0.5) * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float conifer = step(stands, conifer_share);
	vec3 col = mix(broadleaf_color, conifer_color, conifer);
	col *= 0.62 + 0.55 * crowns * (0.7 + 0.6 * fine);
	ALBEDO = col * mix(1.0, 0.8, wet);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.12, 0.16, 0.08);
}
