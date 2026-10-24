// Town streets of the open world (town_builder.gd): asphalt with Polish markings, granite setts or concrete
// slabs, or a gravel track, worn wheel tracks and tar repairs, darker and glossy in the rain.
// Vertex data: UV.x = metres right of the centreline, UV.y = metres along the road;
// UV2.x = half the road's width, UV2.y = marking style (0 none, 1 dashed centre, 2 centre + edge lines,
// 3 carriageway: lane lines + edge lines); COLOR.r = how much of the marking shows (0 at junctions),
// COLOR.g = surface (0 asphalt, 0.5 setts or slabs, 1 gravel), COLOR.b = lanes / 8, COLOR.a = 1 one way.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 asphalt_color : source_color = vec3(0.19, 0.195, 0.205);
uniform vec3 asphalt_old_color : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 sett_color : source_color = vec3(0.42, 0.4, 0.38);
uniform vec3 gravel_color : source_color = vec3(0.5, 0.45, 0.36);
uniform vec3 paint_color : source_color = vec3(0.93, 0.93, 0.9);
uniform float wet = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.25;

varying vec3 world_pos;
varying flat float v_style;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_style = UV2.y;
}

// a painted band of width w centred on x = c, anti-aliased
float band(float x, float c, float w) {
	float d = abs(x - c);
	float aa = fwidth(x) * 0.8 + 0.004;
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, d);
}

void fragment() {
	float x = UV.x;
	float s = UV.y;
	float half_w = UV2.x;
	float show = COLOR.r;
	float surf = COLOR.g;
	float lanes = max(1.0, floor(COLOR.b * 8.0 + 0.5));
	bool oneway = COLOR.a > 0.5;
	vec2 p = world_pos.xz;
	float g1 = texture(grain, p * 0.37).r;
	float g2 = texture(grain, p * 0.043).r;
	float g3 = texture(grain, p * 2.9).r;
	vec3 col;
	float rough = 0.88;
	vec3 nmap = texture(grain_normal, p * 0.9).xyz;
	float nmap_depth = 0.35;
	if (surf < 0.25) {
		col = asphalt_color;
		if (use_textures) {
			col = mix(col, texture(albedo_tex, p * tex_scale).rgb * 0.75, 0.55);
			nmap = texture(normal_tex, p * tex_scale).xyz;
			nmap_depth = 0.6;
		}
		col *= 0.86 + 0.24 * g1 + 0.1 * (g3 - 0.5);
		// sun-bleached older surface in patches, darker tar repairs and the wheel tracks
		float old = smoothstep(0.55, 0.75, g2);
		col = mix(col, asphalt_old_color * (0.85 + 0.2 * g1), old * 0.45);
		float patch_id = hash12(floor(vec2(s / 7.0, x / 2.2 + 13.0)));
		float patch_m = step(0.93, patch_id) * step(abs(x), half_w - 0.4);
		col = mix(col, asphalt_color * 0.62, patch_m * 0.8);
		float track_l = band(x, half_w * 0.5 - 0.0, 0.9) + band(x, -half_w * 0.5, 0.9);
		col *= 1.0 - 0.07 * track_l;
		// crumbling, dusty edges
		float edge = smoothstep(half_w - 0.6, half_w, abs(x));
		col = mix(col, gravel_color * 0.75, edge * smoothstep(0.35, 0.75, g3) * 0.6);
	} else if (surf < 0.75) {
		// setts in courses (ul. Dworcowa's old cobbles, the yards): stones about 0.12 x 0.18 m
		vec2 q = vec2(s / 0.18, x / 0.12);
		q.x += step(1.0, mod(floor(q.y), 2.0)) * 0.5;
		vec2 f = fract(q);
		float joint = smoothstep(0.0, 0.12, f.x) * smoothstep(1.0, 0.88, f.x) * smoothstep(0.0, 0.14, f.y) * smoothstep(1.0, 0.86, f.y);
		float stone = hash12(floor(q));
		col = sett_color * (0.75 + 0.4 * stone) * mix(0.45, 1.0, joint);
		rough = 0.8;
		nmap_depth = 0.8;
	} else {
		col = gravel_color * (0.7 + 0.45 * g1 + 0.2 * g3);
		// the two wheel ruts and the grass between them
		float rut = band(x, half_w * 0.45, 0.7) + band(x, -half_w * 0.45, 0.7);
		col *= 1.0 - 0.15 * rut;
		float middle = band(x, 0.0, 0.6) * smoothstep(0.4, 0.7, g3);
		col = mix(col, vec3(0.2, 0.3, 0.12), middle * 0.7);
		float verge = smoothstep(half_w - 0.5, half_w + 0.1, abs(x));
		col = mix(col, vec3(0.22, 0.32, 0.13), verge * 0.8);
		rough = 0.95;
		nmap_depth = 1.0;
	}

	// markings (asphalt only), worn where wheels cross them
	if (surf < 0.25 && v_style > 0.5) {
		float wear = 0.78 + 0.22 * smoothstep(0.25, 0.6, g1);
		float m = 0.0;
		if (v_style < 1.5) {
			// a dashed centre line: 3 m dashes, 6 m gaps
			m = band(x, 0.0, 0.12) * step(fract(s / 9.0), 0.333);
		} else if (v_style < 2.5) {
			m = band(x, 0.0, 0.12) * step(fract(s / 12.0), 0.333);
			m = max(m, band(abs(x), half_w - 0.35, 0.18));
		} else {
			// carriageway: dashed lane lines, a solid line on either edge
			float lane_w = (2.0 * half_w - 1.2) / lanes;
			for (float k = 1.0; k < 4.0; k += 1.0) {
				if (k < lanes) {
					m = max(m, band(x, -half_w + 0.6 + k * lane_w, 0.15) * step(fract(s / 18.0), 0.333));
				}
			}
			m = max(m, band(abs(x), half_w - 0.45, 0.25));
		}
		col = mix(col, paint_color * (0.9 + 0.1 * g3), m * show * wear);
		rough = mix(rough, 0.6, m * show);
	}

	// rain: darker, glossier, with standing water in the dips of the wheel tracks
	float puddle = wet * smoothstep(0.62, 0.8, g2) * (1.0 - smoothstep(half_w - 1.0, half_w, abs(x)));
	col *= mix(1.0, 0.55, wet);
	rough = mix(rough, 0.18, wet * 0.75);
	rough = mix(rough, 0.03, puddle);
	if (snow > 0.01) {
		float wheel = band(x, half_w * 0.5, 1.2) + band(x, -half_w * 0.5, 1.2);
		col = mix(col, vec3(0.9, 0.92, 0.96), snow * (0.95 - 0.55 * clamp(wheel, 0.0, 1.0)));
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = 0.4 + 0.3 * wet;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = nmap_depth * (1.0 - 0.6 * puddle);
}
