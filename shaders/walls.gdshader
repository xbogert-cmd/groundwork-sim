shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform int n = 192;
uniform float cell = 0.25;
uniform float bottom = -2.0;

varying float v_y;
varying vec2 v_xz;

void vertex() {
	ivec2 ij = clamp(ivec2(round(VERTEX.xz / cell)), ivec2(0), ivec2(n - 1));
	float top = texelFetch(state_tex, ij, 0).r;
	VERTEX.y = UV.y < 0.5 ? top : bottom;
	v_y = VERTEX.y;
	v_xz = VERTEX.xz;
}

void fragment() {
	float band = floor(v_y * 3.0 + vnoise(v_xz * 0.8) * 1.5);
	vec3 a = vec3(0.34, 0.24, 0.15);
	vec3 b = vec3(0.45, 0.31, 0.19);
	vec3 c = vec3(0.28, 0.20, 0.14);
	float k = fract(band * 0.37);
	vec3 col = k < 0.33 ? a : (k < 0.66 ? b : c);
	col *= 0.9 + 0.2 * vnoise(vec2(v_xz.x + v_xz.y, v_y) * 6.0);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
