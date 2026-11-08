// Bushes in the open world (BushCluster in models/roadside.glb, planted by vegetation.gd). The mesh is three faceted
// crowns; drawn plain they read as pale boulders. Here they are leafy: a deep green darker low down and inside, broken
// up into clumps of leaves at the scale of a hand, lit through from behind, with the facets rounded off into one soft
// crown. INSTANCE_CUSTOM: rgb a per-bush tint (around 1). Each bush comes in through a dither between fade_far and
// fade_near from the camera, so a cell of the planted ring never pops in all at once.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 leaf_color : source_color = vec3(0.25, 0.39, 0.12);
uniform vec3 shade_color : source_color = vec3(0.06, 0.11, 0.04);
uniform vec3 sun_color : source_color = vec3(0.42, 0.52, 0.16);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float fade_near = 55.0; // m: fully there
uniform float fade_far = 80.0; // m: not yet there
uniform float translucency = 0.4;

varying vec3 v_tint;
varying vec3 v_local;
varying vec3 v_world;
varying float v_fade;
varying vec3 v_round;

void vertex() {
	v_tint = INSTANCE_CUSTOM.rgb;
	v_local = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = distance(origin.xz, (INV_VIEW_MATRIX[3].xyz).xz);
	v_fade = clamp((fade_far - d) / max(fade_far - fade_near, 0.01), 0.0, 1.0);
	// a gentle sway of the top
	float phase = dot(origin.xz, vec2(0.21, 0.13));
	VERTEX.x += sin(TIME * 1.3 + phase) * 0.03 * max(VERTEX.y, 0.0);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the crown's own roundness: out from a point low in the middle of the clump, not the facet's flat normal
	v_round = normalize((MODEL_MATRIX * vec4(VERTEX - vec3(0.0, 0.35, 0.0), 0.0)).xyz);
}

void fragment() {
	// dithered fade-in, per pixel against a fixed screen pattern
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))); // interleaved gradient noise
	if (v_fade < 0.999 && ign >= v_fade) {
		discard;
	}
	float leaf = texture(grain, v_world.xz * 2.3 + v_world.y * 1.7).r;
	float clump = texture(grain, v_world.xz * 0.6 + v_world.y * 0.8 + 0.3).r;
	float h = clamp(v_local.y / 1.3, 0.0, 1.0);
	vec3 col = mix(shade_color, leaf_color, smoothstep(0.0, 0.75, h) * (0.6 + 0.6 * clump));
	col = mix(col, sun_color, smoothstep(0.62, 0.9, leaf) * 0.5 * h);
	col *= (0.75 + 0.5 * leaf) * v_tint;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	vec3 n = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(v_round, 0.0)).xyz, 0.7));
	NORMAL = n;
	BACKLIGHT = col * translucency;
	AO = mix(0.45, 1.0, h);
	AO_LIGHT_AFFECT = 0.6;
}
