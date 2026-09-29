// Circuit asphalt: aggregate grain, repair patches, a rubbered racing line and dusty edges, drying
// from the racing line outwards and gathering puddles with rain ripples when wet.
// UV.x is the lateral offset from the centreline and UV.y the distance along the lap (metres);
// UV2.x is the lateral distance from the racing line.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.15, 0.16, 0.17);
uniform float half_width = 6.0;
uniform float roughness_dry = 0.86;
uniform float wet = 0.0;
uniform float rain = 0.0;
uniform float rubber = 1.0;
uniform float edge_dust = 1.0;
uniform float patches = 1.0;

uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform bool use_textures = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_rough_tex = false;
uniform float tex_scale = 0.25; // texture repeats per metre
uniform float tex_color_mix = 0.25; // 0 keeps the circuit palette, 1 uses the photo colours

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = UV.x;
	float s = UV.y;
	vec2 wxz = world_pos.xz;
	float broad = texture(grain, wxz * 0.021).r;
	float mid = texture(grain, wxz * 0.13 + 0.37).r;
	float fine = texture(grain, vec2(d, s) * 0.55).r;

	vec3 col;
	float rough;
	vec3 nmap;
	if (use_textures) {
		vec2 tuv = vec2(d, s) * tex_scale;
		vec3 photo = texture(albedo_tex, tuv).rgb;
		col = mix(base_color * photo / max(textureLod(albedo_tex, vec2(0.5), 12.0).rgb, vec3(0.004)), photo, tex_color_mix);
		nmap = texture(normal_tex, tuv).rgb;
		rough = has_rough_tex ? texture(rough_tex, tuv).r : roughness_dry;
	} else {
		col = base_color * (0.78 + 0.44 * fine);
		nmap = texture(grain_normal, vec2(d, s) * 0.9).rgb;
		rough = roughness_dry;
	}
	// large blotches of older and newer surface
	col *= 0.72 + 0.5 * broad + 0.14 * mid;

	// resurfaced patches: rectangles of slightly darker, smoother tarmac
	vec2 cell = floor(vec2((d + half_width) / (half_width * 0.66), s / 11.0));
	float patch_pick = hash12(cell);
	vec2 in_cell = fract(vec2((d + half_width) / (half_width * 0.66), s / 11.0));
	float patch_mask = step(patch_pick, 0.05 * patches) * step(0.12, in_cell.x) * step(in_cell.x, 0.88) * step(0.1, in_cell.y) * step(in_cell.y, 0.9);
	col = mix(col, col * 0.78, patch_mask);
	rough = mix(rough, rough - 0.08, patch_mask);

	// rubber laid down on the racing line
	float rl = UV2.x;
	float line = exp(-rl * rl / 1.8) * rubber;
	col = mix(col, col * 0.62, line * 0.55);
	rough = mix(rough, rough * 0.8, line);

	// dust and marbles collecting at the edges
	float edge = smoothstep(half_width - 1.4, half_width - 0.2, abs(d)) * edge_dust;
	col = mix(col, col * 1.35 + vec3(0.03, 0.028, 0.02), edge * (0.55 + 0.45 * mid));

	// wet: the racing line dries first; standing water pools in the dips
	float w = clamp(wet * (1.0 - line * 0.5 * (1.0 - wet)), 0.0, 1.0);
	float pool_noise = broad * 0.7 + mid * 0.3;
	float puddle = smoothstep(0.66, 0.72, pool_noise + (w - 0.7) * 0.7 - edge * 0.05) * step(0.3, w);
	col *= mix(1.0, 0.52, w);
	col = mix(col, col * 0.8, puddle);
	rough = mix(rough, 0.16, w);
	rough = mix(rough, 0.03, puddle);
	vec3 flat_n = vec3(0.5, 0.5, 1.0);
	nmap = mix(nmap, flat_n, w * 0.55 + puddle * 0.45);
	if (rain > 0.02 && puddle > 0.0) {
		// raindrop rings on the standing water
		vec2 rp = wxz * 4.0;
		vec2 id = floor(rp);
		vec2 f = fract(rp) - 0.5;
		float t = fract(TIME * 1.3 + hash12(id) * 7.0);
		float r = length(f + (vec2(hash12(id + 3.1), hash12(id + 7.7)) - 0.5) * 0.4);
		float ring = sin((r - t * 0.4) * 60.0) * smoothstep(0.04, 0.0, abs(r - t * 0.4)) * (1.0 - t) * step(hash12(id + 1.3), 0.5);
		nmap.xy += normalize(f + 1e-4) * ring * 0.12 * rain * puddle;
	}

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.5, w);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = use_textures ? 1.0 : 0.6;
}
