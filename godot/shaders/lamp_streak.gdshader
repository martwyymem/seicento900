// A lamp's reflection in a wet road after dark, faked the way the old racers did it (NFS, CMR): a long thin
// additive streak lying on the road from under the lamp towards the camera. One MultiMesh instance per lamp
// (race_world.gd _build_lamp_streaks): its origin is the pool of light on the road, INSTANCE_CUSTOM.rgb the
// lamp's colour times its strength, .a the streak's width in metres (its length is LENGTH_PER_WIDTH times that).
// The quad turns to face the camera every frame here, so the script never touches it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

uniform float wet = 0.0;
uniform float rain = 0.0;
uniform float night = 0.0;
uniform float snow = 0.0;
uniform float length_per_width = 11.0;
uniform float fade_near = 150.0; // m from the camera where the streaks begin to fade out ...
uniform float fade_far = 230.0; // ... and are gone

varying vec3 tint;
varying float along;
varying float dist;
varying vec2 ground;

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec2 to_cam = cam.xz - o.xz;
	float d = max(length(to_cam), 0.001);
	vec2 dir = to_cam / d;
	vec2 side = vec2(-dir.y, dir.x);
	float w = INSTANCE_CUSTOM.a;
	// never past the camera: the reflection runs from under the lamp to the viewer's feet
	float len = min(w * length_per_width, d * 0.85);
	// VERTEX (the mesh's own coordinates before world_vertex_coords moved it): x across -0.5..0.5, z along 0..1
	vec3 local = (inverse(MODEL_MATRIX) * vec4(VERTEX, 1.0)).xyz;
	vec2 p = o.xz + side * local.x * w + dir * (local.z * len - 0.12 * len);
	VERTEX = vec3(p.x, o.y, p.y);
	tint = INSTANCE_CUSTOM.rgb;
	along = local.z;
	dist = d;
	ground = p;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float across = UV.x * 2.0 - 1.0;
	float core = exp(-across * across * 5.0);
	float tail = pow(clamp(1.0 - along, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.12, along + 0.12);
	// the film of water breaks the streak into flickering bands, more so while rain falls on it
	float bands = 0.65 + 0.35 * sin(along * 46.0 + hash(floor(ground * 0.5)) * 6.28 + TIME * (2.0 + 6.0 * rain));
	float k = smoothstep(0.25, 0.8, wet) * smoothstep(0.35, 0.8, night) * (1.0 - snow);
	k *= 1.0 - smoothstep(fade_near, fade_far, dist);
	k *= smoothstep(3.0, 9.0, dist); // standing under the lamp there is no streak to see
	ALBEDO = tint * core * tail * bands * k;
}
