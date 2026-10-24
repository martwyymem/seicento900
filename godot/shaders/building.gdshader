// Buildings from OpenStreetMap footprints (surroundings.gd): windows, doors and cladding drawn from each
// face's own measurements, so one material serves every building round the circuit.
// Vertex data: COLOR = wall (or roof) colour; UV = metres along the wall and up from its foot;
// UV2.x = the building's seed, UV2.y = kind + 10 * face (face 0 wall, 1 roof). Kinds (build_surroundings.py):
// 0 house, 1 flats/town, 2 industrial or large, 3 shed/garage, 4 farm, 5 church, 6 grandstand.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float night = 0.0;
uniform float wet = 0.0;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec3 glass_color : source_color = vec3(0.24, 0.32, 0.42);
uniform vec3 frame_color : source_color = vec3(0.92, 0.91, 0.88);

varying vec3 world_pos;
varying flat float v_seed;
varying flat float v_kind;
varying flat float v_face;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_seed = UV2.x;
	v_face = floor(UV2.y / 10.0 + 0.01);
	v_kind = UV2.y - v_face * 10.0;
}

// A window grid on a wall: returns (inside window 0/1, the window's id hash, frame 0/1).
vec3 windows(vec2 uv, float bay, float storey, float w, float h, float sill, float first_row) {
	float bx = uv.x / bay;
	float row = floor((uv.y - first_row) / storey);
	vec2 f = vec2(fract(bx), fract((uv.y - first_row) / storey));
	float hw = w / bay * 0.5;
	float lo = sill / storey;
	float hi = (sill + h) / storey;
	float inside = step(0.5 - hw, f.x) * step(f.x, 0.5 + hw) * step(lo, f.y) * step(f.y, hi) * step(0.0, row)
		* step(first_row, uv.y);
	float fw = 0.08 / bay;
	float fh = 0.08 / storey;
	float frame = inside * (1.0 - step(0.5 - hw + fw, f.x) * step(f.x, 0.5 + hw - fw) * step(lo + fh, f.y) * step(f.y, hi - fh));
	return vec3(inside, hash12(vec2(floor(bx), row) + v_seed * 7.13), frame);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec2 uv = UV;
	float g = texture(grain, world_pos.xz * 0.11 + world_pos.y * 0.07).r;
	vec3 col = base * (0.9 + 0.2 * g);
	float rough = 0.88;
	float metal = 0.0;
	vec3 glow = vec3(0.0);
	bool is_window = false;
	int kind = int(v_kind + 0.5);
	if (v_face > 0.5) {
		// roofs: tiles or slates in courses, flat roofs with a little grime
		if (kind == 0 || kind == 4 || kind == 5) {
			col *= 0.85 + 0.15 * step(0.5, fract(uv.y * 3.2)) + 0.1 * hash12(floor(uv * vec2(3.0, 3.2)) + v_seed);
		} else {
			col *= 0.8 + 0.25 * texture(grain, world_pos.xz * 0.05).r;
		}
		rough = 0.9;
	} else if (kind == 2 || kind == 6) {
		// sheds and halls: ribbed metal cladding, a band of high windows, roller doors on the ground
		col *= 0.93 + 0.07 * step(0.5, fract(uv.x * 1.25));
		metal = 0.15;
		rough = 0.6;
		float top = floor(uv.y / 1.0);
		vec3 w = windows(uv, 6.0, 100.0, 4.6, 1.1, 0.0, 5.2);
		if (w.x > 0.5 && uv.y < 6.3) {
			is_window = w.z < 0.5;
			col = mix(glass_color, frame_color * 0.6, w.z);
			rough = 0.15;
			glow = vec3(1.0, 0.92, 0.75) * step(w.y, 0.45) * night * 1.2 * (1.0 - w.z);
		}
		float door_x = fract(uv.x / 18.0 + v_seed);
		if (uv.y < 4.2 && door_x > 0.35 && door_x < 0.6) {
			col = base * 0.7 * (0.85 + 0.15 * step(0.5, fract(uv.y * 4.0)));
		}
	} else if (kind == 3) {
		// garages and sheds: plain, a dark door
		float door_x = fract(uv.x / 7.0 + v_seed);
		if (uv.y < 2.3 && door_x > 0.2 && door_x < 0.62) {
			col = base * 0.55;
		}
	} else {
		float storey = kind == 1 ? 3.0 : (kind == 5 ? 12.0 : 2.8);
		float bay = kind == 1 ? 2.8 : (kind == 5 ? 4.5 : 3.4);
		float ww = kind == 5 ? 1.4 : 1.2;
		float wh = kind == 5 ? 6.0 : 1.35;
		vec3 w = windows(uv, bay, storey, ww, wh, kind == 5 ? 3.0 : 0.9, kind == 4 ? 1.0 : 0.0);
		// a floor band on town buildings
		if (kind == 1 && fract(uv.y / storey) < 0.06) {
			col *= 1.08;
		}
		if (w.x > 0.5 && (kind != 4 || w.y < 0.5)) {
			is_window = w.z < 0.5;
			bool shutter = kind != 1 && w.y > 0.78;
			vec3 win_glass = glass_color * (0.85 + 0.35 * w.y);
			float sky_fade = smoothstep(0.0, 1.0, fract((uv.y - 0.9) / storey));
			win_glass = mix(win_glass, win_glass * 1.35 + vec3(0.05, 0.09, 0.15), sky_fade * 0.45);
			col = shutter ? base * vec3(0.55, 0.62, 0.55) : mix(win_glass, frame_color, w.z);
			rough = shutter ? 0.8 : 0.12;
			glow = shutter ? vec3(0.0) : vec3(1.0, 0.85, 0.6) * step(w.y, 0.35) * night * 1.6 * (1.0 - w.z);
		} else if (v_face < 0.5) {
			float courses = 0.96 + 0.08 * step(0.05, fract(uv.y * (kind == 1 ? 3.0 : 4.0)));
			col *= courses;
		}
		// the front door on houses and farms
		float door_x = fract(uv.x / 11.0 + v_seed);
		if (kind != 1 && uv.y < 2.2 && door_x > 0.46 && door_x < 0.55) {
			col = base * 0.4;
		}
	}
	// a darker plinth and rain streaks near the ground
	col *= mix(0.78, 1.0, smoothstep(0.0, 0.6, uv.y));
	col *= mix(1.0, 0.7, wet);
	ALBEDO = col;
	ROUGHNESS = mix(rough, rough * 0.5, wet);
	METALLIC = metal;
	SPECULAR = is_window ? 0.8 : 0.35;
	EMISSION = glow;
}
