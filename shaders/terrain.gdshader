shader_type spatial;
render_mode diffuse_burley, specular_disabled;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform int n = 192;
uniform float cell = 0.25;

varying vec3 v_pos;
varying vec3 v_normal;
varying vec4 v_state;
varying float v_near_water;

vec4 st(ivec2 ij) {
	return texelFetch(state_tex, clamp(ij, ivec2(0), ivec2(n - 1)), 0);
}

void vertex() {
	ivec2 ij = ivec2(round(VERTEX.xz / cell));
	vec4 s = st(ij);
	VERTEX.y = s.r;
	float hl = st(ij + ivec2(-1, 0)).r;
	float hr = st(ij + ivec2(1, 0)).r;
	float hu = st(ij + ivec2(0, -1)).r;
	float hd = st(ij + ivec2(0, 1)).r;
	NORMAL = normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
	v_normal = NORMAL;
	v_state = s;
	v_pos = VERTEX;
	v_near_water = max(max(st(ij + ivec2(-1, 0)).g, st(ij + ivec2(1, 0)).g), max(st(ij + ivec2(0, -1)).g, st(ij + ivec2(0, 1)).g));
	v_near_water = max(v_near_water, s.g);
}

void fragment() {
	float slope = 1.0 - normalize(v_normal).y;
	float big = vnoise(v_pos.xz * 0.35);
	float mid = vnoise(v_pos.xz * 1.7);
	float fine = vnoise(v_pos.xz * 7.0);

	vec3 grass_a = vec3(0.30, 0.52, 0.17);
	vec3 grass_b = vec3(0.50, 0.68, 0.24);
	vec3 grass = mix(grass_a, grass_b, big * 0.8 + mid * 0.25);
	grass *= 0.9 + 0.2 * fine;
	vec3 dirt = mix(vec3(0.48, 0.31, 0.18), vec3(0.58, 0.40, 0.24), mid) * (0.9 + 0.15 * fine);

	float dirt_mask = max(smoothstep(0.13, 0.30, slope), smoothstep(0.05, 0.5, v_state.b));
	vec3 col = mix(grass, dirt, dirt_mask);

	// damp soil next to / under water goes dark and muddy
	float damp_amt = smoothstep(0.0, 0.02, v_near_water);
	col = mix(col, col * vec3(0.50, 0.45, 0.40), damp_amt * 0.85);
	// pond bed
	col = mix(col, vec3(0.20, 0.17, 0.11), smoothstep(0.05, 0.4, v_state.g) * 0.7);

	ALBEDO = col;
	ROUGHNESS = 0.95;
}
