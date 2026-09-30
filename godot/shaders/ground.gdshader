// Grass, gravel and terrain. The colour comes from the circuit palette (or the terrain's vertex colours);
// noise breaks up tiling at several scales and optional photo textures add close-up detail.
// For run-off, UV.x is the lateral offset from the centreline so the edge of the road can wear bare.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 base_color : source_color = vec3(0.4, 0.55, 0.3);
uniform bool use_vertex_color = false;
uniform bool is_runoff = false;
uniform float track_half = 6.0;
uniform vec3 worn_color : source_color = vec3(0.42, 0.38, 0.3);
uniform float roughness_dry = 0.95;
uniform float wet = 0.0;
uniform float tuft = 1.0; // grass-like colour variation; lower for gravel and paved run-off
uniform float slope_rock = 1.0;
uniform vec3 rock_color : source_color = vec3(0.42, 0.4, 0.37);

uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform bool use_textures = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_rough_tex = false;
uniform float tex_scale = 0.35;
uniform float tex_color_mix = 0.3;

// The land map from OpenStreetMap (surroundings.gd): per texel how much is paved (R), farmland (G), bare
// ground (B) and forest (A), over a rectangle of the world's x/z.
uniform bool use_land = false;
uniform sampler2D land_map : filter_linear, repeat_disable;
uniform vec2 land_origin = vec2(0.0);
uniform vec2 land_size = vec2(1.0);
uniform vec3 paved_color : source_color = vec3(0.34, 0.34, 0.33);
uniform vec3 farm_color_a : source_color = vec3(0.62, 0.58, 0.33); // ripe crops
uniform vec3 farm_color_b : source_color = vec3(0.4, 0.5, 0.24); // green crops
uniform vec3 farm_color_c : source_color = vec3(0.42, 0.33, 0.24); // ploughed
uniform vec3 bare_color : source_color = vec3(0.5, 0.43, 0.32);
uniform vec3 forest_floor_color : source_color = vec3(0.2, 0.22, 0.13);

varying vec3 world_pos;
varying vec3 world_normal;

// vertex colours are stored as sRGB
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 base = use_vertex_color ? to_linear(COLOR.rgb) : base_color;
	float macro = texture(grain, p * 0.0045).r;
	float broad = texture(grain, p * 0.031 + 0.5).r;
	float fine = texture(grain, p * 0.47).r;
	float micro = texture(grain, p * 2.9).r;

	vec3 col;
	float rough = roughness_dry;
	vec3 nmap = texture(grain_normal, p * 0.35).rgb;
	if (use_textures) {
		// two rotated samples hide the tile repeat
		vec2 tuv = p * tex_scale;
		vec2 tuv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * tex_scale * 0.37 + 0.31;
		vec3 photo = mix(texture(albedo_tex, tuv).rgb, texture(albedo_tex, tuv2).rgb, smoothstep(0.35, 0.65, broad));
		col = mix(base * photo / max(textureLod(albedo_tex, vec2(0.5), 12.0).rgb, vec3(0.004)), photo, tex_color_mix);
		nmap = texture(normal_tex, tuv).rgb;
		if (has_rough_tex) {
			rough = texture(rough_tex, tuv).r;
		}
	} else {
		col = base * (0.74 + 0.42 * fine + 0.2 * micro);
	}
	// patchy colour: sun-bleached and lush areas
	vec3 dry_tint = vec3(1.08, 1.04, 0.84);
	vec3 lush_tint = vec3(0.86, 0.96, 0.86);
	col *= mix(vec3(1.0), mix(lush_tint, dry_tint, smoothstep(0.3, 0.7, macro)), tuft) * (0.8 + 0.4 * broad);

	float paved = 0.0;
	if (use_land) {
		vec2 luv = (p - land_origin) / land_size;
		if (luv.x > 0.0 && luv.y > 0.0 && luv.x < 1.0 && luv.y < 1.0) {
			vec4 lm = texture(land_map, luv);
			// farmland: G is 0.35-1 in a field, its value the field's crop; rows in the tractor's direction
			float field = smoothstep(0.12, 0.3, lm.g);
			float crop = clamp((lm.g - 0.35) / 0.65, 0.0, 1.0);
			vec3 farm = crop < 0.45 ? farm_color_b : (crop < 0.75 ? farm_color_a : farm_color_c);
			farm *= 0.9 + 0.15 * fract(crop * 7.3);
			farm *= 0.88 + 0.16 * step(0.5, fract(dot(p, vec2(0.6, 0.8)) * 0.9)) * (0.4 + fine);
			col = mix(col, farm * (0.88 + 0.2 * broad), field);
			col = mix(col, forest_floor_color * (0.7 + 0.5 * fine), lm.a * 0.9);
			col = mix(col, bare_color * (0.8 + 0.3 * fine + 0.15 * micro), lm.b);
			paved = smoothstep(0.25, 0.75, lm.r);
			col = mix(col, paved_color * (0.88 + 0.16 * fine + 0.08 * micro), paved);
			rough = mix(rough, 0.82, paved);
		}
	}

	// steep ground turns to bare earth and rock
	if (!is_runoff) {
		float steep = smoothstep(0.8, 0.62, abs(world_normal.y)) * slope_rock * (1.0 - paved); // abs: the terrain is two-sided
		col = mix(col, rock_color * (0.8 + 0.4 * fine), steep);
		rough = mix(rough, 0.85, steep);
	} else {
		// tyre-worn strip along the road edge
		float from_edge = abs(UV.x) - track_half;
		float worn = smoothstep(1.6, 0.2, from_edge) * step(0.0, from_edge) * (0.5 + 0.5 * broad);
		col = mix(col, worn_color * (0.85 + 0.3 * fine), worn * tuft * 0.8);
	}

	col *= mix(1.0, 0.72, wet);
	ALBEDO = col;
	ROUGHNESS = clamp(mix(rough, rough * 0.62, wet), 0.05, 1.0);
	SPECULAR = 0.35;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = use_textures ? 1.0 : 0.45;
}
