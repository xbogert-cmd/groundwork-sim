shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform sampler2D flux_tex : filter_nearest, repeat_disable;
uniform int n = 192;
uniform float cell = 0.25;
uniform vec3 shallow_color : source_color = vec3(0.30, 0.62, 0.60);
uniform vec3 deep_color : source_color = vec3(0.03, 0.18, 0.27);

varying vec3 v_pos;
varying float v_depth;
varying vec2 v_flow;
varying float v_mud;

vec4 st(ivec2 ij) {
	return texelFetch(state_tex, clamp(ij, ivec2(0), ivec2(n - 1)), 0);
}

float eta(ivec2 ij) {
	vec4 s = st(ij);
	return s.r + s.g;
}

void vertex() {
	ivec2 ij = ivec2(round(VERTEX.xz / cell));
	vec4 s = st(ij);
	VERTEX.y = s.r + s.g + 0.004;
	v_depth = s.g;
	v_mud = s.b;
	vec4 f = texelFetch(flux_tex, clamp(ij, ivec2(0), ivec2(n - 1)), 0);
	// net outflow -> velocity (m/s), +x is east, +y is the row direction (z)
	vec2 vel = vec2(f.r - f.g, f.b - f.a) / (cell * max(s.g, 0.04));
	float sp = length(vel);
	v_flow = vel * min(1.0, 3.0 / max(sp, 0.001));
	NORMAL = normalize(vec3(eta(ij + ivec2(-1, 0)) - eta(ij + ivec2(1, 0)), 2.0 * cell, eta(ij + ivec2(0, -1)) - eta(ij + ivec2(0, 1))));
	v_pos = VERTEX;
}

// two-phase flow-advected noise so ripples stream along the current
float flow_noise(vec2 p, vec2 flow, float t) {
	float p0 = fract(t);
	float p1 = fract(t + 0.5);
	float w = abs(p0 * 2.0 - 1.0);
	float n0 = vnoise(p * 2.2 - flow * p0 * 1.6);
	float n1 = vnoise(p * 2.2 - flow * p1 * 1.6 + 17.3);
	return mix(n0, n1, w);
}

void fragment() {
	float depth = v_depth;
	if (depth < 0.004) discard;
	float cover = smoothstep(0.004, 0.05, depth);

	float t = 1.0 - exp(-depth * 1.7);
	vec3 col = mix(shallow_color, deep_color, t);
	col = mix(col, vec3(0.40, 0.30, 0.18), clamp(v_mud * 0.9, 0.0, 1.0) * (1.0 - t * 0.5) * 0.55);

	float speed = length(v_flow);
	float time = TIME * 0.45;
	float rip = flow_noise(v_pos.xz, v_flow, time);
	float rip2 = flow_noise(v_pos.xz + 3.1, v_flow * 1.3, time + 0.31);
	vec3 bump = vec3((rip - 0.5) * 0.35, 0.0, (rip2 - 0.5) * 0.35) * (0.4 + min(speed, 2.0) * 0.5);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump, 0.0)).xyz);

	// foam: thin shoreline fringe + fast, turbulent water
	float shore = (1.0 - smoothstep(0.01, 0.09, depth)) * (0.35 + 0.65 * rip);
	float fast = smoothstep(0.7, 1.6, speed) * smoothstep(0.35, 0.8, rip2);
	float foam = clamp(shore * 0.9 + fast, 0.0, 1.0);

	ALBEDO = mix(col, vec3(0.92, 0.97, 0.96), foam);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.6;
	ALPHA = cover * mix(0.55, 0.93, t) ;
	ALPHA = clamp(ALPHA + foam * 0.5 * cover, 0.0, 0.97);
}
