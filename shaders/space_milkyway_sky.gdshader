shader_type sky;

// Animated, realistic Milky Way sky — a dusty tilted galactic band, stellar-temperature
// stars, per-star twinkle, slow dust drift, and occasional shooting stars.
// Fully procedural (no textures). It re-renders every frame because of TIME, so the
// expensive nebula FBM is gated to band pixels to stay cheap on single-threaded WebGL2.

uniform float master_brightness : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float nebula_drift_speed : hint_range(0.0, 0.2, 0.001) = 0.012; // 0 freezes the drift
uniform float twinkle_speed : hint_range(0.0, 8.0, 0.1) = 2.2;
uniform float twinkle_amount : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float star_density : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float meteor_rate : hint_range(0.0, 2.0, 0.05) = 0.6;   // shooting-star frequency
uniform float band_tilt : hint_range(-1.5, 1.5, 0.01) = 0.5;    // galactic plane tilt (radians)

float _hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float _hash1(float n) {
	return fract(sin(n) * 43758.5453);
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

// 5-octave fractal noise (one fewer than the vivid shader, since this runs per frame).
float _fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 5; i++) {
		value += amplitude * _noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.4);
		amplitude *= 0.5;
	}
	return value;
}

// Map a 0..1 hash to a realistic stellar colour: mostly blue-white / white / yellow,
// a minority amber, a few red.
vec3 _star_color(float t) {
	if (t < 0.45) {
		return mix(vec3(0.75, 0.84, 1.0), vec3(1.0, 1.0, 1.0), t / 0.45);
	} else if (t < 0.8) {
		return mix(vec3(1.0, 1.0, 1.0), vec3(1.0, 0.93, 0.78), (t - 0.45) / 0.35);
	} else if (t < 0.94) {
		return mix(vec3(1.0, 0.93, 0.78), vec3(1.0, 0.78, 0.55), (t - 0.8) / 0.14);
	}
	return mix(vec3(1.0, 0.78, 0.55), vec3(1.0, 0.55, 0.42), (t - 0.94) / 0.06);
}

// Multi-layer star field. Density rises inside the galactic band; bright stars twinkle.
vec3 _starfield(vec3 dir, float band, float time) {
	vec3 acc = vec3(0.0);
	vec3 p = dir * 90.0;
	for (int layer = 0; layer < 4; layer++) {
		vec3 cell = floor(p);
		vec3 f = fract(p) - 0.5;
		float h = _hash(cell + float(layer) * 19.17);
		float thresh = (0.955 - float(layer) * 0.012) - band * 0.03;
		thresh = mix(0.985, thresh, clamp(star_density, 0.0, 1.0));
		if (h > thresh) {
			float d = length(f);
			float size = mix(0.10, 0.035, h);
			float core = smoothstep(size, 0.0, d);
			float mag = pow(smoothstep(thresh, 1.0, h), 2.0);   // few bright, many faint
			float brightness = mix(0.35, 1.6, mag);
			float phase = _hash(cell + 3.3) * 6.2831853;
			float tw = 1.0 - twinkle_amount * (0.5 + 0.5 * sin(time * twinkle_speed + phase));
			brightness *= mix(1.0, tw, smoothstep(0.0, 0.6, mag));
			acc += _star_color(_hash(cell + 7.7)) * core * brightness;
		}
		p *= 1.71;
	}
	return acc;
}

// A couple of analytic shooting stars sweeping along random great circles.
float _meteors(vec3 dir, float time) {
	float m = 0.0;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float cycle = 4.5;
		float t = time / cycle + fi * 31.7;
		float seg = floor(t);
		float local = fract(t);
		if (_hash1(seg * 2.7 + fi * 13.0) > 1.0 - meteor_rate * 0.5) {
			float a = _hash1(seg + fi * 3.0) * 6.2831853;
			float z = _hash1(seg + fi * 9.0) * 1.6 - 0.8;
			float rr = sqrt(max(0.0, 1.0 - z * z));
			vec3 s = vec3(rr * cos(a), z, rr * sin(a));
			vec3 u = normalize(cross(s, vec3(0.13, 1.0, 0.13)));
			vec3 n = cross(s, u);
			float window = 0.18;
			float w = local / window;
			float life = step(local, window) * smoothstep(0.0, 0.1, w) * smoothstep(1.0, 0.7, w);
			if (life > 0.001) {
				float head_ang = -0.4 + w * 0.9;
				float perp = abs(dot(dir, n));
				float dir_ang = atan(dot(dir, u), dot(dir, s));
				float delta = head_ang - dir_ang;
				float head = smoothstep(0.02, 0.0, abs(delta));
				float tail = smoothstep(0.16, 0.0, delta) * step(0.0, delta);
				float line = smoothstep(0.01, 0.0, perp);
				m += line * (head + tail * 0.6) * life;
			}
		}
	}
	return m;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float time = TIME;

	// Base space: near-black with a faint cool/warm vertical shift.
	vec3 col = mix(vec3(0.012, 0.014, 0.022), vec3(0.004, 0.005, 0.010), abs(dir.y));

	// Tilted galactic plane: band == 1 on the plane, falling off to the poles.
	vec3 band_normal = normalize(vec3(0.0, cos(band_tilt), sin(band_tilt)));
	float bd = dot(dir, band_normal);
	float band = exp(-bd * bd * 7.0);

	// Dusty nebula glow — only computed near the band (coherent branch keeps phones happy).
	if (band > 0.01) {
		vec3 drift = vec3(time * nebula_drift_speed, 0.0, time * nebula_drift_speed * 0.6);
		vec3 sp = dir * 3.0 + drift;
		float dust = _fbm(sp);
		float fine = _fbm(sp * 2.7 + vec3(5.0, 1.0, 9.0));
		float glow = band * smoothstep(0.28, 0.92, dust) * (0.6 + 0.5 * fine);
		vec3 milky = mix(vec3(0.10, 0.10, 0.13), vec3(0.40, 0.35, 0.32), smoothstep(0.3, 1.0, dust));
		col += milky * glow * 0.8;
		// Faint always-on haze concentrated on the plane, so the band is clearly visible.
		col += vec3(0.06, 0.065, 0.085) * band * band * 0.6;
		col += vec3(0.05, 0.06, 0.09) * smoothstep(0.5, 1.0, dust) * band * 0.25;
		// Dark dust lanes cutting across the band (subtractive).
		float lane = smoothstep(0.45, 0.75, _fbm(sp * 1.6 + vec3(2.0, 7.0, 0.0)));
		col *= mix(1.0, 0.45, lane * band);
	}

	col += _starfield(dir, band, time) * (0.9 * star_density + 0.1);
	col += vec3(0.85, 0.9, 1.0) * _meteors(dir, time);

	COLOR = max(col * master_brightness, vec3(0.0));
}
