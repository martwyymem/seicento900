// The Polish number plates on the Seicento's bumpers (the "Plate" surface of the Details mesh). The model has no UVs,
// so the plate is found by its place in the car (a flat rectangle at each end, centred, 512 mm wide) and mapped
// from the vertex position; every other Plate surface (the door panels, under the decals) stays plain white.
// plate_id (a per-car instance uniform) picks a row of textures/car/plate_pl.png (tools/build_car_textures.py).
shader_type spatial;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float rows = 8.0;
instance uniform float plate_id = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	bool is_plate = abs(lp.x) < 0.262 && abs(lp.z) > 1.4 && lp.y < 0.5;
	vec3 col = vec3(0.92, 0.91, 0.87);
	float rough = 0.5;
	if (is_plate) {
		bool front = lp.z < 0.0;
		float y0 = front ? 0.3086 : 0.3666;
		float u = lp.x / 0.2559 * 0.5;
		u = front ? 0.5 - u : 0.5 + u; // each end is read from outside
		float v = 1.0 - (lp.y - y0) / 0.1047;
		vec2 uv = vec2(clamp(u, 0.0, 1.0), (floor(plate_id + 0.5) + clamp(v, 0.0, 1.0)) / rows);
		col = texture(atlas, uv).rgb;
		rough = 0.34;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.6;
	CLEARCOAT = is_plate ? 0.35 : 0.0;
	CLEARCOAT_ROUGHNESS = 0.1;
}
