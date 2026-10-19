#[compute]
#version 450
// Pass 1: water flux out of each cell towards E, W, S(+y), N(-y), in m^3/s.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D state; // r ground, g water, b dirt
layout(rgba32f, set = 0, binding = 1) uniform restrict image2D flux;

layout(push_constant, std430) uniform Params {
	float dt;
	float g;
	float cell;
	float damp;
	float n;
	float open_east;
	float outlet_drop;
	float pad;
} p;

// Neighbour (ground, water). False = wall.
bool neighbour(ivec2 c, ivec2 me, out vec2 gw) {
	int n = int(p.n);
	if (c.x >= n && p.open_east > 0.5) {
		gw = vec2(imageLoad(state, ivec2(n - 1, me.y)).r - p.outlet_drop, 0.0);
		return true;
	}
	if (c.x < 0 || c.y < 0 || c.x >= n || c.y >= n) {
		gw = vec2(0.0);
		return false;
	}
	gw = imageLoad(state, c).rg;
	return true;
}

float edge_flux(float f, vec2 a, vec2 b) {
	float eta_a = a.x + a.y;
	float eta_b = b.x + b.y;
	float h = max(eta_a, eta_b) - max(a.x, b.x); // water depth over the sill between the two cells
	if (h <= 1e-5) return 0.0;
	f = f * (1.0 - p.damp * p.dt) + p.dt * p.g * h * (eta_a - eta_b);
	return max(f, 0.0);
}

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	int n = int(p.n);
	if (c.x >= n || c.y >= n) return;

	vec2 me = imageLoad(state, c).rg;
	vec4 f = imageLoad(flux, c);
	vec4 nf = vec4(0.0);
	vec2 o;
	if (neighbour(c + ivec2(1, 0), c, o)) nf.r = edge_flux(f.r, me, o);
	if (neighbour(c + ivec2(-1, 0), c, o)) nf.g = edge_flux(f.g, me, o);
	if (neighbour(c + ivec2(0, 1), c, o)) nf.b = edge_flux(f.b, me, o);
	if (neighbour(c + ivec2(0, -1), c, o)) nf.a = edge_flux(f.a, me, o);

	// never send out more water than the cell holds
	float total = nf.r + nf.g + nf.b + nf.a;
	float avail = me.y * p.cell * p.cell / p.dt;
	if (total > avail) nf *= avail / total;
	imageStore(flux, c, nf);
}
