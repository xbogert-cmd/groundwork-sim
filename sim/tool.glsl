#[compute]
#version 450
// Bucket: dig removes ground, dump adds it. Volumes are summed (fixed point) into the counters buffer.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict image2D state;
layout(set = 0, binding = 1, std430) restrict buffer Counters {
	uint removed;
	uint added;
} cnt;

layout(push_constant, std430) uniform Params {
	float cx;
	float cy;
	float radius;  // cells
	float amount;  // metres at the brush centre (always positive)
	float floor_h;
	float cell;
	float n;
	float mode;    // 0 dig, 1 dump
} p;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	int n = int(p.n);
	if (c.x >= n || c.y >= n) return;
	float d = length(vec2(c) - vec2(p.cx, p.cy)) / p.radius;
	if (d >= 1.0) return;
	float w = (1.0 - d * d);
	w *= w;

	vec4 s = imageLoad(state, c);
	float vol_scale = p.cell * p.cell * 1e7;
	if (p.mode < 0.5) {
		float ng = max(p.floor_h, s.r - p.amount * w);
		float rem = s.r - ng;
		if (rem > 0.0) {
			atomicAdd(cnt.removed, uint(rem * vol_scale + 0.5));
			s.r = ng;
			s.b = max(s.b, w);
		}
	} else {
		float add = p.amount * w;
		s.r += add;
		s.g = max(0.0, s.g - add); // soil displaces water
		s.b = max(s.b, w);
		atomicAdd(cnt.added, uint(add * vol_scale + 0.5));
	}
	imageStore(state, c, s);
}
