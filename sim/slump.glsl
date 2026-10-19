#[compute]
#version 450
// Soil slumps towards the angle of repose (shallower when wet). Symmetric pair transfers, so soil volume is conserved.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D state;
layout(rgba32f, set = 0, binding = 1) uniform restrict writeonly image2D result;

layout(push_constant, std430) uniform Params {
	float cell;
	float tan_dry;
	float tan_wet;
	float rate;
	float n;
	float pad0;
	float pad1;
	float pad2;
} p;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	int n = int(p.n);
	if (c.x >= n || c.y >= n) return;

	vec4 s = imageLoad(state, c);
	float net = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) continue;
			ivec2 q = c + ivec2(dx, dy);
			if (q.x < 0 || q.y < 0 || q.x >= n || q.y >= n) continue;
			vec4 t = imageLoad(state, q);
			float dist = p.cell * ((dx != 0 && dy != 0) ? 1.41421356 : 1.0);
			float md = (max(s.g, t.g) > 0.03 ? p.tan_wet : p.tan_dry) * dist;
			float diff = s.r - t.r;
			if (diff > md) net -= p.rate * (diff - md);
			else if (-diff > md) net += p.rate * (-diff - md);
		}
	}
	s.r += net;
	imageStore(result, c, s);
}
