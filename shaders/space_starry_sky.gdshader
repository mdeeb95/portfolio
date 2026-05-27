shader_type sky;

// Vivid procedural nebula sky — mystical purples, teals, and magentas + dense stars.

float _hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float _noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = _hash(i);
	float n100 = _hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = _hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = _hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = _hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = _hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = _hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = _hash(i + vec3(1.0, 1.0, 1.0));
	float n00 = mix(n000, n100, f.x);
	float n10 = mix(n010, n110, f.x);
	float n01 = mix(n001, n101, f.x);
	float n11 = mix(n011, n111, f.x);
	float n0 = mix(n00, n10, f.y);
	float n1 = mix(n01, n11, f.y);
	return mix(n0, n1, f.z);
}

float _fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 6; i++) {
		value += amplitude * _noise(p);
		p = p * 2.04 + vec3(1.7, 9.2, 3.4);
		amplitude *= 0.5;
	}
	return value;
}

float _stars(vec3 dir) {
	vec3 p = dir * 110.0;
	float stars = 0.0;
	for (int layer = 0; layer < 4; layer++) {
		vec3 cell = floor(p);
		vec3 f = fract(p) - 0.5;
		float h = _hash(cell + float(layer) * 19.17);
		float threshold = 0.962 - float(layer) * 0.014;
		if (h > threshold) {
			float d = length(f);
			float size = mix(0.12, 0.04, h);
			float brightness = mix(0.5, 1.4, smoothstep(threshold, 1.0, h));
			stars += smoothstep(size, 0.0, d) * brightness;
		}
		p *= 1.72;
	}
	return stars;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// Deep cosmic base (balanced between subtle and vivid).
	vec3 col = mix(vec3(0.006, 0.004, 0.02), vec3(0.045, 0.02, 0.1), pow(1.0 - abs(dir.y), 1.6));
	col += vec3(0.06, 0.025, 0.12) * pow(max(0.0, 1.0 - abs(dir.y)), 3.5);

	// Nebula clouds (warped FBM for mystical swirls).
	vec3 warp = vec3(
		_fbm(dir * 2.2 + vec3(4.1, 0.0, 2.3)),
		_fbm(dir * 2.2 + vec3(8.3, 2.7, 0.0)),
		_fbm(dir * 2.2 + vec3(0.0, 5.9, 6.1))
	) * 0.55;
	vec3 sample_dir = normalize(dir + warp);

	float n1 = _fbm(sample_dir * 2.8 + vec3(1.2, 4.5, 7.8));
	float n2 = _fbm(sample_dir * 5.5 + vec3(9.0, 2.1, 3.3));
	float n3 = _fbm(sample_dir * 11.0 - vec3(3.7, 6.2, 1.5));
	float n4 = pow(_fbm(sample_dir * 22.0 + vec3(12.0, 1.0, 8.0)), 2.2);

	// Color stacks — purple / magenta / teal / gold dust.
	vec3 neb_a = mix(vec3(0.04, 0.02, 0.12), vec3(0.55, 0.12, 0.95), smoothstep(0.25, 0.85, n1));
	vec3 neb_b = mix(vec3(0.05, 0.15, 0.35), vec3(0.15, 0.75, 0.95), smoothstep(0.3, 0.9, n2));
	vec3 neb_c = mix(vec3(0.25, 0.05, 0.35), vec3(0.95, 0.25, 0.75), smoothstep(0.35, 0.95, n3));
	vec3 neb_d = vec3(1.0, 0.65, 0.35) * smoothstep(0.55, 1.0, n4) * 0.45;

	col = col + neb_a * 0.48;
	col = col + neb_b * (0.28 + 0.18 * n1);
	col = col + neb_c * (0.2 + 0.25 * pow(n2, 1.5));
	col += neb_d * 0.5;

	// Galactic ribbon + aurora wisps.
	float ribbon = exp(-pow(abs(dir.x * 0.55 + dir.z * 0.45 + dir.y * 0.15), 2.0) * 6.5);
	col += vec3(0.35, 0.28, 0.65) * ribbon * 0.28;
	col += vec3(0.2, 0.85, 0.75) * pow(max(0.0, sin(dir.y * 8.0 + n1 * 6.0)), 4.0) * 0.06;

	// Star field with slight cool/warm tint variation.
	float star_field = _stars(dir) * 0.85;
	vec3 star_tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.75), _hash(floor(dir * 80.0)));
	col += star_tint * star_field;

	col = pow(max(col, vec3(0.0)), vec3(0.95));
	// ~50/50 between the old (×0.65) and vivid (×1.35) master scales.
	COLOR = col * 0.92;
}
