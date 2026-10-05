shader_type spatial;
// Playpen triplanar terrain blend: top (grass/sand/snow) vs side (rock/dirt) by
// slope, with procedural color variation so big surfaces never look flat.
// No texture needed; optional detail textures multiply on top.
uniform vec4 top_color : source_color = vec4(0.32, 0.68, 0.34, 1.0);
uniform vec4 top_color_b : source_color = vec4(0.45, 0.76, 0.3, 1.0);
uniform vec4 side_color : source_color = vec4(0.46, 0.38, 0.3, 1.0);
uniform vec4 side_color_b : source_color = vec4(0.36, 0.3, 0.26, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.62;
uniform float slope_blend : hint_range(0.01, 0.5) = 0.18;
uniform float variation_scale = 0.18;
uniform float detail_scale = 1.4;
uniform float detail_amount : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_detail = false;

varying vec3 v_world;
varying vec3 v_wnormal;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float up = clamp(v_wnormal.y, 0.0, 1.0);
	float topmask = smoothstep(slope_start - slope_blend, slope_start + slope_blend, up);
	float n = vnoise(v_world.xz * variation_scale) * 0.65 + vnoise(v_world.xz * variation_scale * 3.1) * 0.35;
	vec3 top = mix(top_color.rgb, top_color_b.rgb, n);
	float ns = vnoise(vec2(v_world.x + v_world.z, v_world.y) * variation_scale * 2.0);
	vec3 side = mix(side_color.rgb, side_color_b.rgb, ns);
	vec3 c = mix(side, top, topmask);
	if (use_detail) {
		vec3 b = abs(v_wnormal);
		b /= (b.x + b.y + b.z + 0.0001);
		vec3 dx = texture(detail_tex, v_world.zy * detail_scale).rgb;
		vec3 dy = texture(detail_tex, v_world.xz * detail_scale).rgb;
		vec3 dz = texture(detail_tex, v_world.xy * detail_scale).rgb;
		vec3 dt = dx * b.x + dy * b.y + dz * b.z;
		c = mix(c, c * dt * 1.6, detail_amount);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
