shader_type sky;
// Playpen sky: vertical gradient, soft sun disc + glow, horizon haze, drifting
// procedural clouds (that also catch the sun), optional stars + moon for night.
uniform vec4 sky_top : source_color = vec4(0.18, 0.52, 0.92, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.77, 0.93, 1.0, 1.0);
uniform vec4 ground_color : source_color = vec4(0.91, 0.96, 1.0, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.94, 0.77, 1.0);
uniform float sun_size : hint_range(0.001, 0.2) = 0.045;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.85;
uniform float haze : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_speed = 0.012;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.72, 0.8, 0.92, 1.0);
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform int cloud_quality : hint_range(0, 2) = 2; // 0 = none, 1 = one cheap layer, 2 = shaded

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
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(clamp(h, 0.0, 1.0), 0.55);
		col = mix(sky_horizon.rgb, sky_top.rgb, t);
		col = mix(col, sky_horizon.rgb, (1.0 - smoothstep(0.0, 0.35, h)) * haze);
	} else {
		col = mix(sky_horizon.rgb, ground_color.rgb, smoothstep(0.0, -0.25, h));
	}
	// The sun disc, glow, clouds and stars only belong in the visible background.
	// Leaving them in the radiance (ambient-light) pass blows the whole scene out.
	if (!AT_CUBEMAP_PASS) {
	// sun
	float sd = max(dot(dir, normalize(LIGHT0_DIRECTION)), 0.0);
	float disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.7, sd);
	col += sun_color.rgb * (disc * 1.8 + pow(sd, 24.0) * sun_glow * 0.5 + pow(sd, 6.0) * sun_glow * 0.18) * LIGHT0_ENERGY;
	// clouds on a dome projection
	if (cloud_quality > 0 && h > 0.02 && cloud_cover > 0.01) {
		vec2 uv = dir.xz / (h + 0.25) * 1.6 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = fbm(uv * 1.3);
		float thr = 1.0 - cloud_cover * 0.75;
		float c = smoothstep(thr, thr + 0.22, n);
		c *= smoothstep(0.02, 0.16, h);
		float lit = 0.65;
		if (cloud_quality > 1) {
			lit = clamp(fbm(uv * 1.3 + normalize(LIGHT0_DIRECTION.xz + vec2(0.001)) * 0.12) - n + 0.5, 0.0, 1.0);
		}
		vec3 ccol = mix(cloud_shade.rgb, cloud_color.rgb, lit);
		ccol += sun_color.rgb * pow(sd, 8.0) * 0.35;
		col = mix(col, ccol, c * 0.92);
	}
	// stars + moon
	if (stars > 0.01 && h > 0.0) {
		vec2 su = dir.xz / (h + 0.3) * 40.0;
		float s = step(0.992, hash21(floor(su)));
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + hash21(floor(su)) * 30.0);
		col += vec3(s * tw) * stars * smoothstep(0.0, 0.2, h);
	}
	}
	COLOR = col;
}
