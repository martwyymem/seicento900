shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float soft_distance : hint_range(0.02, 3.0) = 0.55;
uniform float camera_fade_distance : hint_range(0.1, 8.0) = 3.0;
uniform float camera_fade_min : hint_range(0.0, 3.0) = 0.85;
uniform bool emissive = false;
uniform bool leaf_shape = false;
uniform vec3 ambient_color : source_color = vec3(0.52, 0.56, 0.62);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.88);
uniform vec3 sun_direction = vec3(0.42, 0.78, 0.46);
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_angle;
varying vec2 v_seed;

// Procedural hash and value noise for organic puff erosion
float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash2(i + vec2(0.0, 0.0)), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm2(vec2 p) {
	float total = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 3; i++) {
		total += amp * noise2(p);
		p = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p * 2.02 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return total;
}

void vertex() {
	vec3 view_pos = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float cam_dist = -view_pos.z;
	vec3 particle_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	// Collapse particle geometry before it intersects the camera near clipping plane
	if (cam_dist < camera_fade_min * 0.75) {
		particle_scale = vec3(0.0);
	}
	// Billboard to camera with particle rotation preserved
	float angle = atan(MODEL_MATRIX[0].y, MODEL_MATRIX[0].x);
	v_angle = angle;
	v_seed = vec2(MODEL_MATRIX[3].x * 7.13 + MODEL_MATRIX[3].z * 11.17, MODEL_MATRIX[3].y * 5.31 + angle * 2.45);
	float ca = cos(angle);
	float sa = sin(angle);
	vec3 right = (INV_VIEW_MATRIX[0].xyz * ca - INV_VIEW_MATRIX[1].xyz * sa) * particle_scale.x;
	vec3 up = (INV_VIEW_MATRIX[0].xyz * sa + INV_VIEW_MATRIX[1].xyz * ca) * particle_scale.y;
	mat4 billboard_model = mat4(
		vec4(right, 0.0),
		vec4(up, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * particle_scale.z, 0.0),
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard_model;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float r2 = dot(centered, centered);
	float radius = sqrt(r2);

	float shape = 0.0;
	if (leaf_shape) {
		float leaf_radius = length(vec2(centered.x * 1.35, centered.y * 0.68)) + abs(centered.x) * 0.1;
		shape = 1.0 - smoothstep(0.65, 1.0, leaf_radius);
	} else {
		// Rotate sample coordinates in particle's local rotation frame
		float ca = cos(v_angle);
		float sa = sin(v_angle);
		vec2 rot_uv = vec2(centered.x * ca - centered.y * sa, centered.x * sa + centered.y * ca);
		// Noise sample unique per particle
		float n = fbm2(rot_uv * 2.8 + v_seed);
		// Erode edge with noise: solid center, turbulent billowing wisps at perimeter
		float distorted_r = radius + (n - 0.5) * 0.45 * smoothstep(0.12, 0.72, radius);
		shape = smoothstep(0.88, 0.22, distorted_r);
		// Subtle density modulation across puff interior
		shape *= clamp(0.7 + 0.6 * n, 0.0, 1.0);
	}

	float scene_z = texture(scene_depth, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_z, 1.0);
	float scene_distance = -scene_view.z / max(scene_view.w, 0.0001);
	float particle_distance = -VERTEX.z;
	float intersection_fade = clamp((scene_distance - particle_distance) / max(soft_distance, 0.001), 0.0, 1.0);
	// Smoothly fade to 0.0 before reaching the camera near clipping threshold
	float near_fade = smoothstep(camera_fade_min, camera_fade_distance, particle_distance);

	// Directional + ambient lighting calculation so smoke is grounded and tinted by sun/ambient
	vec3 lit_color = COLOR.rgb;
	if (!emissive) {
		// Pseudo-spherical normal across billboard for volumetric 3D light response
		vec3 puff_normal = vec3(centered.x, -centered.y, sqrt(max(0.0, 1.0 - min(r2, 0.98))));
		vec3 world_normal = normalize(
			INV_VIEW_MATRIX[0].xyz * puff_normal.x +
			INV_VIEW_MATRIX[1].xyz * puff_normal.y +
			INV_VIEW_MATRIX[2].xyz * puff_normal.z
		);
		vec3 s_dir = normalize(sun_direction);
		float wrap_diffuse = pow(max(0.0, dot(world_normal, s_dir) * 0.5 + 0.5), 1.5);
		vec3 lighting = mix(ambient_color, sun_color, wrap_diffuse * 0.7);
		lit_color = COLOR.rgb * lighting;
	}

	ALBEDO = lit_color;
	ALPHA = COLOR.a * shape * intersection_fade * near_fade;
	if (emissive) {
		EMISSION = COLOR.rgb * COLOR.a * shape;
	}
}
