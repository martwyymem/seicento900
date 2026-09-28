// City blocks: rows of windows with shutters, floor bands and a darker roof, drawn from the box's own
// coordinates, so one material serves every building. Windows light up at random after dark.
// Per-building values are instance uniforms set with set_instance_shader_parameter().
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

instance uniform vec4 wall_color : source_color = vec4(0.83, 0.77, 0.66, 1.0);
instance uniform vec4 shutter_color : source_color = vec4(0.25, 0.38, 0.3, 1.0);
instance uniform vec4 dims = vec4(12.0, 18.0, 10.0, 0.0); // width, height, depth, seed
uniform float night = 0.0;
uniform float wet = 0.0;
uniform float floor_height = 3.1;
uniform float bay_width = 2.6;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wall = wall_color.rgb * (0.9 + 0.2 * texture(grain, world_pos.xy * 0.13 + world_pos.zy * 0.11).r);
	float seed = dims.w;
	if (local_normal.y > 0.5) {
		ALBEDO = wall * vec3(0.55, 0.52, 0.5);
		ROUGHNESS = 0.9;
	} else if (local_normal.y < -0.5) {
		ALBEDO = wall * 0.4;
		ROUGHNESS = 0.9;
	} else {
		float along = abs(local_normal.x) > 0.5 ? local_pos.z * sign(local_normal.x) : local_pos.x * sign(-local_normal.z);
		float face_w = abs(local_normal.x) > 0.5 ? dims.z : dims.x;
		float y = local_pos.y + dims.y * 0.5;
		float bays = max(1.0, floor(face_w / bay_width));
		float bx = (along + face_w * 0.5) / face_w * bays;
		float row = floor(y / floor_height);
		vec2 f = vec2(fract(bx), fract(y / floor_height));
		vec2 id = vec2(floor(bx) + seed * 17.0 + local_normal.x * 5.0 + local_normal.z * 11.0, row + seed * 3.0);
		bool top_band = y > dims.y - 0.9;
		bool in_window = f.x > 0.24 && f.x < 0.76 && f.y > 0.22 && f.y < 0.8 && row >= 1.0 && !top_band && bx > 0.35 && bx < bays - 0.35;
		bool ground_shop = row < 1.0 && f.x > 0.12 && f.x < 0.88 && f.y > 0.08 && f.y < 0.78;
		vec3 col = wall;
		float rough = 0.88;
		float metal = 0.0;
		vec3 glow = vec3(0.0);
		// cornice at the top and a thin band at every floor
		if (top_band || f.y < 0.05) {
			col = wall * 1.12;
		}
		if (in_window || ground_shop) {
			float h = hash12(id);
			bool shut = in_window && h < 0.28;
			if (shut) {
				// louvred shutters
				col = shutter_color.rgb * (0.8 + 0.25 * step(0.5, fract(f.y * 14.0)));
				rough = 0.7;
			} else {
				col = vec3(0.05, 0.07, 0.08);
				rough = 0.08;
				metal = 0.4;
				float lit = step(hash12(id + 19.7), ground_shop ? 0.7 : 0.42);
				vec3 warm = mix(vec3(1.0, 0.72, 0.42), vec3(0.95, 0.9, 0.8), hash12(id + 3.3));
				glow = warm * lit * night * (ground_shop ? 2.6 : 1.5);
			}
			// window sill shadow
			if (in_window && f.y < 0.26) {
				col *= 0.6;
			}
		}
		ALBEDO = col * mix(1.0, 0.75, wet);
		ROUGHNESS = mix(rough, rough * 0.5, wet);
		METALLIC = metal;
		EMISSION = glow;
	}
}
