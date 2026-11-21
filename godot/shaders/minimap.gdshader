// The open world's satnav map (data/world/<key>_map.png) seen round the car: a disc turning with the car's
// heading (heading up), or the whole map when radius_m covers it and rotate is off. map_origin and map_size
// are the picture's rectangle in map metres; centre is the car's map position.
shader_type canvas_item;

uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform vec2 map_size = vec2(1000.0);
uniform vec2 centre = vec2(0.0);
uniform float heading = 0.0; // radians from +x towards +y (south)
uniform float radius_m = 250.0;
uniform bool rotate = true;
uniform bool disc = true;
uniform vec4 edge_color : source_color = vec4(0.0, 0.92, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.18, 0.62, 1.0);
uniform float aspect = 1.0; // width / height of the control (the full map isn't square)

void fragment() {
	vec2 o = (UV - 0.5) * 2.0;
	o.x *= aspect;
	float r = length(o);
	if (disc && r > 1.0) {
		discard;
	}
	vec2 world;
	if (rotate) {
		vec2 f = vec2(cos(heading), sin(heading));
		vec2 rt = vec2(-f.y, f.x);
		world = centre + (rt * o.x - f * o.y) * radius_m;
	} else {
		world = centre + o * radius_m;
	}
	vec2 uv = (world - map_origin) / map_size;
	vec4 c = texture(map_tex, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		c = vec4(0.05, 0.07, 0.11, 1.0);
	}
	if (disc) {
		// richer dark-glass radar contrast so neon GPS & icons pop over bright sky and night
		c.rgb = pow(max(c.rgb, vec3(0.0)), vec3(1.08)) * 1.12;
		// soft vignette & inner neon glow toward the ring
		float inner_vignette = smoothstep(0.68, 0.90, r);
		c.rgb = mix(c.rgb, c.rgb * 0.65, inner_vignette * 0.55);
		// angular gradient from primary cyan around to hot magenta accent on the thick neon ring
		float ang_t = 0.5 + 0.5 * sin(atan(o.y, o.x) + 0.8);
		vec3 ring_col = mix(edge_color.rgb, glow_color.rgb, ang_t * 0.42);
		float inner_glow = smoothstep(0.76, 0.895, r) * (1.0 - smoothstep(0.895, 0.92, r));
		c.rgb += ring_col * inner_glow * 0.42;
		// dark inner bezel separation
		float bezel = smoothstep(0.875, 0.892, r) * (1.0 - smoothstep(0.902, 0.916, r));
		c.rgb = mix(c.rgb, vec3(0.02, 0.03, 0.06), bezel * 0.85);
		// thick glowing neon ring + bright core + soft outer bloom halo
		float ring_core = smoothstep(0.900, 0.918, r) * (1.0 - smoothstep(0.952, 0.970, r));
		float ring_hot = smoothstep(0.918, 0.932, r) * (1.0 - smoothstep(0.938, 0.952, r));
		float outer_bloom = smoothstep(0.945, 0.962, r) * (1.0 - smoothstep(0.962, 1.0, r));
		c.rgb = mix(c.rgb, ring_col * 1.15, ring_core);
		c.rgb = mix(c.rgb, mix(ring_col, vec3(1.0), 0.58), ring_hot);
		float base_a = 0.94 * (1.0 - smoothstep(0.956, 0.972, r));
		float bloom_a = outer_bloom * 0.65;
		c.rgb = mix(ring_col * 1.1, c.rgb, clamp(base_a / max(base_a + bloom_a, 0.001), 0.0, 1.0));
		c.a = max(base_a, bloom_a);
	} else {
		c.rgb *= 1.08;
	}
	COLOR = c;
}
