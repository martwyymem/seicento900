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
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
	if (dot(n, CAMERA_POSITION_WORLD - world_pos) < 0.0) {
		n = -n;
	}
	// crowns: fine bumps on top of the mesh's lumps (y offset prevents vertical streaking on the rim skirt)
	vec2 p = world_pos.xz + world_pos.y * vec2(0.37, 0.23);
	float fine = texture(grain, p * 0.21).r;
	float crowns = texture(grain, p * 0.07 + 0.3).r;
	float stands = texture(grain, world_pos.xz * 0.006 + 0.7).r;
	n = normalize(n + vec3(fine - 0.5, (crowns - 0.5) * (1.0 - abs(n.y)), crowns - 0.5) * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float conifer = step(stands, conifer_share);
	vec3 col = mix(broadleaf_color, conifer_color, conifer);
	col *= 0.62 + 0.55 * crowns * (0.7 + 0.6 * fine);
	float w = clamp(max(wet, rain * 0.65), 0.0, 1.0);
	col *= mix(1.0, 0.8, w);
	float rough = mix(0.95, 0.55, w);
	float spec = mix(0.2, 0.32, w);
	float back_k = 1.0;
	if (snow > 0.001) {
		float sn = crowns * 0.6 + fine * 0.4;
		float snow_cover = clamp(snow * smoothstep(0.25, 0.75, n.y + (sn - 0.5) * 0.45), 0.0, 1.0);
		col = mix(col, vec3(0.90, 0.93, 0.98) * (0.90 + 0.16 * sn), snow_cover * 0.88);
		rough = mix(rough, 0.85, snow_cover);
		spec = mix(spec, 0.22, snow_cover);
		back_k *= 1.0 - snow_cover * 0.85;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	BACKLIGHT = vec3(0.12, 0.16, 0.08) * back_k;
}
