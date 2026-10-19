#[compute]
#version 450
// Pass 2: update water depth from the fluxes (what leaves one cell enters its neighbour).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict image2D state;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D flux;

layout(push_constant, std430) uniform Params {
	float dt;
	float cell;
	float n;
	float rain;
} p;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	int n = int(p.n);
	if (c.x >= n || c.y >= n) return;

	vec4 out_f = imageLoad(flux, c);
	float outv = out_f.r + out_f.g + out_f.b + out_f.a;
	float inv = 0.0;
	if (c.x + 1 < n) inv += imageLoad(flux, c + ivec2(1, 0)).g;
	if (c.x - 1 >= 0) inv += imageLoad(flux, c + ivec2(-1, 0)).r;
	if (c.y + 1 < n) inv += imageLoad(flux, c + ivec2(0, 1)).a;
	if (c.y - 1 >= 0) inv += imageLoad(flux, c + ivec2(0, -1)).b;

	vec4 s = imageLoad(state, c);
	s.g = max(0.0, s.g + p.dt * (inv - outv) / (p.cell * p.cell) + p.rain * p.dt);
	imageStore(state, c, s);
}
