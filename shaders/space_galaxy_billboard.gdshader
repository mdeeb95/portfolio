shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Faint distant galaxy smudge on a camera-facing quad (Andromeda / Magellanic-cloud feel).
// Additive + unshaded so it only ever adds soft light. Drive per-instance look with the uniforms.

uniform vec3 tint : source_color = vec3(0.55, 0.6, 0.8);
uniform float seed = 0.0;
uniform float brightness : hint_range(0.0, 3.0, 0.01) = 0.8;
uniform float core_size : hint_range(0.02, 0.5, 0.01) = 0.16;
uniform float ellipticity : hint_range(0.2, 1.0, 0.01) = 0.55; // squash to an ellipse

float _gh(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _gn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _gh(i);
	float b = _gh(i + vec2(1.0, 0.0));
	float c = _gh(i + vec2(0.0, 1.0));
	float d = _gh(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float _gfbm(vec2 p) {
	float v = 0.0;
	float amp = 0.6;
	for (int i = 0; i < 4; i++) {
		v += amp * _gn(p);
		p = p * 2.1 + vec2(3.1, 1.7);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	// Billboard: face the camera, keep the instance's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(sx, 0.0, 0.0, 0.0), vec4(0.0, sy, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.y /= ellipticity;
	float ca = cos(seed);
	float sa = sin(seed);
	uv = mat2(vec2(ca, -sa), vec2(sa, ca)) * uv;
	float r = length(uv);
	float core = smoothstep(core_size, 0.0, r);
	float halo = smoothstep(0.5, 0.0, r);
	float clouds = _gfbm(uv * 6.0 + vec2(seed * 10.0));
	float density = core * (0.55 + 0.7 * clouds) + halo * 0.22;
	density *= smoothstep(0.5, 0.12, r);   // fade out before the quad edge
	ALBEDO = tint * brightness;
	ALPHA = clamp(density, 0.0, 1.0);
}
