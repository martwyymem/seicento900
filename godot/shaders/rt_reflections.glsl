#[compute]
#version 450

// Ray-traced reflections (rt_reflections.gd). For every glossy pixel the reflected ray is traced through a
// two-level BVH of the scene (instances -> per-mesh triangle trees, built by rt_bvh.gd), the hit is lit by
// the sun (with a traced shadow ray) and the sky ambient, and it replaces the sky that Godot reflected there.
// Runs in software on any GPU with compute shaders: no ray-tracing hardware or driver support is needed.

#define STACK_SIZE 48
#define INF 1e30

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;
layout(set = 0, binding = 2) uniform sampler2D normal_roughness_texture;
// one traced sample per 2x2 block: rgb what the reflection adds over the sky Godot reflected, a the
// distance to the surface (negative: nothing traced there)
layout(rgba16f, set = 0, binding = 4) uniform restrict image2D half_image;
layout(set = 0, binding = 3, std140) uniform Params {
	mat4 inv_projection; // depth-buffer NDC -> view space
	mat4 cam_to_world;
	vec4 sun_dir; // towards the light; w > 0.5 traces shadow rays from the hits
	vec4 sun_color; // linear, energy included
	vec4 ambient; // linear
	vec4 sky_zenith; // linear
	vec4 sky_horizon; // linear
	vec4 fog; // rgb colour, w density
	ivec4 roots; // x static top-level root (-1 none), y dynamic root (-1 none), z first dynamic instance, w debug view
	vec4 settings; // x strength, y roughness cut-off, z max ray length
} params;

// x: 0 trace every pixel, 1 trace the glossiest pixel of each 2x2 block into half_image, 2 composite every
// pixel from half_image (tracing it itself only where no traced neighbour matches it)
layout(push_constant, std430) uniform PassInfo {
	ivec4 mode;
} pass_info;

// BVH nodes: vec4(min, first) vec4(max, count), see rt_bvh.gd
layout(set = 1, binding = 0, std430) restrict readonly buffer BlasNodes {
	vec4 data[];
} blas_nodes;
// triangles: vec4(v0, colour) vec4(edge1, 0) vec4(edge2, 0), in the order their tree's leaves reference
layout(set = 1, binding = 1, std430) restrict readonly buffer Triangles {
	vec4 data[];
} triangles;
// instances: three rows of the world-to-local transform, then ivec4(root node, first triangle, tint, 0)
layout(set = 1, binding = 2, std430) restrict readonly buffer Instances {
	vec4 data[];
} instances;
layout(set = 1, binding = 3, std430) restrict readonly buffer TopNodes {
	vec4 data[];
} top_nodes;

float hit_t;
uint hit_color;
uint hit_tint;
vec3 hit_normal;

vec3 safe_inverse(vec3 d) {
	return vec3(d.x >= 0.0 ? 1.0 : -1.0, d.y >= 0.0 ? 1.0 : -1.0, d.z >= 0.0 ? 1.0 : -1.0) / max(abs(d), vec3(1e-9));
}

float box_hit(vec3 ro, vec3 inv_rd, vec3 lo, vec3 hi, float t_max) {
	vec3 t0 = (lo - ro) * inv_rd;
	vec3 t1 = (hi - ro) * inv_rd;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float t_enter = max(max(tn.x, tn.y), max(tn.z, 0.0));
	float t_exit = min(min(tf.x, tf.y), min(tf.z, t_max));
	return t_enter <= t_exit ? t_enter : INF;
}

float triangle_hit(vec3 ro, vec3 rd, vec3 v0, vec3 e1, vec3 e2) {
	vec3 p = cross(rd, e2);
	float det = dot(e1, p);
	if (abs(det) < 1e-14) {
		return INF;
	}
	float inv_det = 1.0 / det;
	vec3 s = ro - v0;
	float u = dot(s, p) * inv_det;
	if (u < 0.0 || u > 1.0) {
		return INF;
	}
	vec3 q = cross(s, e1);
	float v = dot(rd, q) * inv_det;
	if (v < 0.0 || u + v > 1.0) {
		return INF;
	}
	float t = dot(e2, q) * inv_det;
	return t > 0.0 ? t : INF;
}

// The ray is taken into the instance's space unnormalised, so t stays a world-space ray parameter.
bool trace_instance(int instance, vec3 ro, vec3 rd, bool any_hit) {
	vec4 r0 = instances.data[instance * 4];
	vec4 r1 = instances.data[instance * 4 + 1];
	vec4 r2 = instances.data[instance * 4 + 2];
	ivec4 meta = floatBitsToInt(instances.data[instance * 4 + 3]);
	vec3 lro = vec3(dot(r0, vec4(ro, 1.0)), dot(r1, vec4(ro, 1.0)), dot(r2, vec4(ro, 1.0)));
	vec3 lrd = vec3(dot(r0.xyz, rd), dot(r1.xyz, rd), dot(r2.xyz, rd));
	vec3 inv = safe_inverse(lrd);
	bool found = false;
	int stack[STACK_SIZE];
	int sp = 0;
	stack[sp++] = 0;
	while (sp > 0) {
		int node = meta.x + stack[--sp];
		vec4 a = blas_nodes.data[node * 2];
		vec4 b = blas_nodes.data[node * 2 + 1];
		int first = floatBitsToInt(a.w);
		int count = floatBitsToInt(b.w);
		if (count > 0) {
			for (int i = 0; i < count; i++) {
				int tri = (meta.y + first + i) * 3;
				vec4 v0 = triangles.data[tri];
				vec3 e1 = triangles.data[tri + 1].xyz;
				vec3 e2 = triangles.data[tri + 2].xyz;
				float t = triangle_hit(lro, lrd, v0.xyz, e1, e2);
				if (t < hit_t) {
					hit_t = t;
					hit_color = floatBitsToUint(v0.w);
					hit_tint = uint(meta.z);
					vec3 n = cross(e1, e2);
					hit_normal = n.x * r0.xyz + n.y * r1.xyz + n.z * r2.xyz;
					found = true;
					if (any_hit) {
						return true;
					}
				}
			}
			continue;
		}
		int c0 = meta.x + first;
		float d0 = box_hit(lro, inv, blas_nodes.data[c0 * 2].xyz, blas_nodes.data[c0 * 2 + 1].xyz, hit_t);
		float d1 = box_hit(lro, inv, blas_nodes.data[c0 * 2 + 2].xyz, blas_nodes.data[c0 * 2 + 3].xyz, hit_t);
		// nearer child on top of the stack
		int near_child = d0 <= d1 ? first : first + 1;
		int far_child = d0 <= d1 ? first + 1 : first;
		if (max(d0, d1) < INF && sp < STACK_SIZE) {
			stack[sp++] = far_child;
		}
		if (min(d0, d1) < INF && sp < STACK_SIZE) {
			stack[sp++] = near_child;
		}
	}
	return found;
}

bool trace_top(int root, int instance_base, vec3 ro, vec3 rd, vec3 inv, bool any_hit) {
	if (root < 0) {
		return false;
	}
	bool found = false;
	int stack[STACK_SIZE];
	int sp = 0;
	stack[sp++] = 0;
	while (sp > 0) {
		int node = root + stack[--sp];
		vec4 a = top_nodes.data[node * 2];
		vec4 b = top_nodes.data[node * 2 + 1];
		if (box_hit(ro, inv, a.xyz, b.xyz, hit_t) >= INF) {
			continue;
		}
		int first = floatBitsToInt(a.w);
		int count = floatBitsToInt(b.w);
		if (count > 0) {
			for (int i = 0; i < count; i++) {
				if (trace_instance(instance_base + first + i, ro, rd, any_hit)) {
					found = true;
					if (any_hit) {
						return true;
					}
				}
			}
			continue;
		}
		int c0 = root + first;
		float d0 = box_hit(ro, inv, top_nodes.data[c0 * 2].xyz, top_nodes.data[c0 * 2 + 1].xyz, hit_t);
		float d1 = box_hit(ro, inv, top_nodes.data[c0 * 2 + 2].xyz, top_nodes.data[c0 * 2 + 3].xyz, hit_t);
		int near_child = d0 <= d1 ? first : first + 1;
		int far_child = d0 <= d1 ? first + 1 : first;
		if (max(d0, d1) < INF && sp < STACK_SIZE) {
			stack[sp++] = far_child;
		}
		if (min(d0, d1) < INF && sp < STACK_SIZE) {
			stack[sp++] = near_child;
		}
	}
	return found;
}

bool trace(vec3 ro, vec3 rd, float t_max, bool any_hit) {
	hit_t = t_max;
	vec3 inv = safe_inverse(rd);
	bool found = trace_top(params.roots.x, 0, ro, rd, inv, any_hit);
	if (found && any_hit) {
		return true;
	}
	return trace_top(params.roots.y, params.roots.z, ro, rd, inv, any_hit) || found;
}

// colours are stored as the square root of linear RGB (alpha: emission) to keep precision in the darks
vec4 unpack_colour(uint bits) {
	vec4 c = unpackUnorm4x8(bits);
	return c * c;
}

vec3 sky(vec3 dir) {
	vec3 above = mix(params.sky_horizon.rgb, params.sky_zenith.rgb, sqrt(clamp(dir.y, 0.0, 1.0)));
	return dir.y >= 0.0 ? above : params.sky_horizon.rgb * mix(1.0, 0.5, clamp(-dir.y * 4.0, 0.0, 1.0));
}

vec3 shade_hit(vec3 ro, vec3 rd) {
	float t = hit_t;
	vec4 surface = unpack_colour(hit_color);
	vec3 albedo = surface.rgb * unpack_colour(hit_tint).rgb;
	vec3 n = normalize(hit_normal);
	if (dot(n, rd) > 0.0) {
		n = -n;
	}
	vec3 p = ro + rd * t;
	vec3 to_sun = params.sun_dir.xyz;
	float lambert = max(dot(n, to_sun), 0.0);
	if (lambert > 0.0 && params.sun_dir.w > 0.5 && trace(p + n * 0.04, to_sun, params.settings.z, true)) {
		lambert = 0.0;
	}
	vec3 lit = albedo * (params.sun_color.rgb * lambert + params.ambient.rgb * (0.55 + 0.45 * n.y)) + albedo * surface.a * 8.0;
	return mix(lit, params.fog.rgb, 1.0 - exp(-params.fog.w * t));
}

vec3 view_position(vec2 uv, float depth) {
	vec4 vp = params.inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return vp.xyz / vp.w;
}

// The surface's geometric normal (view space) from the depth buffer, taking the flatter side at edges.
vec3 depth_normal(vec2 uv, vec2 texel, vec3 p) {
	vec3 xp = view_position(uv + vec2(texel.x, 0.0), textureLod(depth_texture, uv + vec2(texel.x, 0.0), 0.0).r) - p;
	vec3 xn = p - view_position(uv - vec2(texel.x, 0.0), textureLod(depth_texture, uv - vec2(texel.x, 0.0), 0.0).r);
	vec3 yp = view_position(uv + vec2(0.0, texel.y), textureLod(depth_texture, uv + vec2(0.0, texel.y), 0.0).r) - p;
	vec3 yn = p - view_position(uv - vec2(0.0, texel.y), textureLod(depth_texture, uv - vec2(0.0, texel.y), 0.0).r);
	vec3 dx = abs(xp.z) < abs(xn.z) ? xp : xn;
	vec3 dy = abs(yp.z) < abs(yn.z) ? yp : yn;
	vec3 n = normalize(cross(dx, dy));
	return dot(n, p) > 0.0 ? -n : n;
}

// What a pixel reflects: weight 0 where it shows nothing (sky, rough or too faint), else the ray to trace
// and the distance to the surface.
struct Surface {
	float weight;
	vec3 origin;
	vec3 dir;
	float dist;
};

Surface surface_at(ivec2 pixel, ivec2 size, vec3 cam_pos) {
	Surface s;
	s.weight = 0.0;
	vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
	float depth = textureLod(depth_texture, uv, 0.0).r;
	if (depth <= 0.0) {
		return s; // sky
	}
	vec4 nr = textureLod(normal_roughness_texture, uv, 0.0);
	// Godot's packing: roughness above 0.5 marks dynamic objects
	float roughness = nr.w;
	bool dynamic_object = roughness > 0.5;
	if (dynamic_object) {
		roughness = 1.0 - roughness;
	}
	roughness /= 127.0 / 255.0;
	if (dynamic_object) {
		roughness *= 0.4; // car paint has a glossy clear coat the buffer does not record
	}
	float cut_off = params.settings.y;
	float weight = 1.0 - smoothstep(cut_off * 0.35, cut_off, roughness);
	bool debug = params.roots.w == 2;
	if (weight <= 0.001 && !debug) {
		return s;
	}
	vec3 view_pos = view_position(uv, depth);
	vec3 world_pos = (params.cam_to_world * vec4(view_pos, 1.0)).xyz;
	vec3 view_n = normalize(nr.xyz * 2.0 - 1.0);
	if (!dynamic_object) {
		// Tarmac grain and ripples in the normal map scatter single mirror rays into speckle (a rough
		// reflection would need many rays), so keep only a hint of them over the flat surface.
		view_n = normalize(mix(depth_normal(uv, 1.0 / vec2(size), view_pos), view_n, 0.25));
	}
	vec3 n = normalize(mat3(params.cam_to_world) * view_n);
	vec3 to_pixel = world_pos - cam_pos;
	float dist = length(to_pixel);
	vec3 v = to_pixel / max(dist, 1e-4);
	vec3 r = reflect(v, n);
	float cos_v = clamp(dot(-v, n), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - cos_v, 5.0);
	weight *= fresnel * params.settings.x * exp(-params.fog.w * dist);
	if (weight < 0.02 && !debug) {
		return s; // too faint to see (rough steel, matt paint face-on): skip the trace
	}
	s.weight = max(weight, 1e-6);
	s.origin = world_pos + n * (0.02 + dist * 0.0015);
	s.dir = r;
	s.dist = dist;
	return s;
}

vec3 traced(Surface s) {
	return trace(s.origin, s.dir, params.settings.z, false) ? shade_hit(s.origin, s.dir) : sky(s.dir);
}

void main() {
	ivec2 size = imageSize(color_image);
	vec3 cam_pos = params.cam_to_world[3].xyz;
	int mode = pass_info.mode.x;

	if (mode == 1) {
		ivec2 block = ivec2(gl_GlobalInvocationID.xy);
		if (any(greaterThanEqual(block, imageSize(half_image)))) {
			return;
		}
		Surface best;
		best.weight = 0.0;
		for (int k = 0; k < 4; k++) {
			ivec2 p = block * 2 + ivec2(k & 1, k >> 1);
			if (all(lessThan(p, size))) {
				Surface s = surface_at(p, size, cam_pos);
				if (s.weight > best.weight) {
					best = s;
				}
			}
		}
		imageStore(half_image, block, best.weight > 0.0 ? vec4(traced(best) - sky(best.dir), best.dist) : vec4(0.0, 0.0, 0.0, -1.0));
		return;
	}

	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(pixel, size))) {
		return;
	}
	if (params.roots.w == 1) {
		// debug: primary rays, the traced scene should line up with the rendered one
		vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
		vec4 vp = params.inv_projection * vec4(uv * 2.0 - 1.0, 0.5, 1.0);
		vec3 dir = normalize(mat3(params.cam_to_world) * (vp.xyz / vp.w));
		vec3 c = trace(cam_pos, dir, params.settings.z, false) ? shade_hit(cam_pos, dir) : sky(dir);
		imageStore(color_image, pixel, vec4(c, 1.0));
		return;
	}
	Surface s = surface_at(pixel, size, cam_pos);
	if (s.weight <= 0.0) {
		return;
	}
	vec4 colour = imageLoad(color_image, pixel);
	if (params.roots.w == 2) {
		// debug: what the reflections see
		imageStore(color_image, pixel, vec4(traced(s), colour.a));
		return;
	}
	vec3 added = vec3(0.0);
	float found = 0.0;
	if (mode == 2) {
		// the traced samples of the blocks around, by distance and only from a surface at about the same depth
		ivec2 half_size = imageSize(half_image);
		vec2 at = (vec2(pixel) + 0.5) * 0.5 - 0.5;
		ivec2 b0 = ivec2(floor(at));
		for (int k = 0; k < 4; k++) {
			ivec2 b = clamp(b0 + ivec2(k & 1, k >> 1), ivec2(0), half_size - 1);
			vec4 smp = imageLoad(half_image, b);
			if (smp.a < 0.0) {
				continue;
			}
			vec2 f = max(vec2(0.0), 1.0 - abs(at - vec2(b)));
			float w = (f.x * f.y + 0.01) * max(0.0, 1.0 - abs(smp.a - s.dist) / (0.04 * s.dist + 0.05));
			added += smp.rgb * w;
			found += w;
		}
	}
	// Godot already reflected the sky here; swap it for what the ray found
	added = found > 1e-4 ? added / found : traced(s) - sky(s.dir);
	colour.rgb = max(colour.rgb + s.weight * added, colour.rgb * (1.0 - s.weight));
	imageStore(color_image, pixel, colour);
}
