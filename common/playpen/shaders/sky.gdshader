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
uniform float moon : hint_range(0.0, 1.0) = 0.0;                 // moon disc + glow (night skies)
uniform vec3 moon_dir = vec3(-0.45, 0.55, -0.7);
uniform vec4 moon_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float shooting_star : hint_range(0.0, 1.0) = 0.0;       // occasional streak across the stars
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
	// stars (two sizes, twinkling) + moon + the odd shooting star
	if (stars > 0.01 && h > 0.0) {
		// stars are small round dots (a falloff from each cell's centre), never filled squares
		vec2 su = dir.xz / (h + 0.3) * 60.0;
		vec2 cf = fract(su) - 0.5;
		vec2 cj = (vec2(hash21(floor(su) + 1.0), hash21(floor(su) + 2.0)) - 0.5) * 0.6;
		float s = step(0.975, hash21(floor(su))) * smoothstep(0.16, 0.0, length(cf - cj));
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + hash21(floor(su)) * 30.0);
		col += vec3(s * tw) * stars * smoothstep(0.0, 0.2, h);
		vec2 su2 = dir.xz / (h + 0.3) * 22.0;
		vec2 cf2 = fract(su2) - 0.5;
		vec2 cj2 = (vec2(hash21(floor(su2) + 4.0), hash21(floor(su2) + 6.0)) - 0.5) * 0.5;
		float s2 = step(0.965, hash21(floor(su2) + 7.0)) * smoothstep(0.22, 0.0, length(cf2 - cj2));
		col += vec3(1.0, 0.95, 0.85) * s2 * (0.7 + 0.3 * sin(TIME * 1.3 + hash21(floor(su2)) * 20.0)) * stars * smoothstep(0.05, 0.3, h);
		col += vec3(0.04, 0.05, 0.09) * stars * smoothstep(0.0, 0.5, h) * fbm(dir.xz * 3.0 / (h + 0.4));   // faint star-dust band
	}
	if (moon > 0.01) {
		vec3 md = normalize(moon_dir);
		float md_dot = max(dot(dir, md), 0.0);
		float mdisc = smoothstep(0.9985, 0.9992, md_dot);
		col += moon_color.rgb * (mdisc * 1.6 + pow(md_dot, 220.0) * 0.5 + pow(md_dot, 28.0) * 0.18) * moon;
	}
	if (shooting_star > 0.01 && h > 0.05) {
		float period = 11.0;
		float ph = fract(TIME / period);
		float live = step(ph, 0.06);
		float u = ph / 0.06;
		vec2 a0 = vec2(-0.55, 0.62);
		vec2 a1 = vec2(0.1, 0.22);
		vec2 head = mix(a0, a1, u);
		vec2 q = dir.xz / (h + 0.3) * 0.5;
		vec2 d2 = q - head;
		vec2 tail = normalize(a1 - a0);
		float along = dot(d2, -tail);
		float across = length(d2 - (-tail) * along);
		float streak = smoothstep(0.012, 0.0, across) * smoothstep(0.0, 0.05, along) * smoothstep(0.35, 0.0, along);
		col += vec3(1.0, 0.97, 0.9) * streak * live * shooting_star * 1.4;
	}
	}
	COLOR = col;
}
