shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A single glowing glyph quad orbiting the hacker terminal. All motion lives
// in the vertex shader (TIME-driven), so a placed glyph costs zero script time.
// Each quad needs its own material with a distinct `seed` (no per-instance
// uniforms on GL Compatibility) and a generous extra_cull_margin, since the
// orbit moves vertices outside the mesh AABB.

uniform vec3 glyph_color : source_color = vec3(0.12, 1.0, 0.35);
uniform float brightness : hint_range(0.0, 4.0, 0.01) = 1.6;
uniform float seed = 0.0;
uniform float orbit_radius : hint_range(0.1, 3.0, 0.01) = 0.9;
uniform float orbit_speed : hint_range(-3.0, 3.0, 0.01) = 0.5;
uniform float bob_height : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float glyph_flip_speed : hint_range(0.0, 10.0, 0.1) = 2.0;

float _h(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float _h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Same fake-glyph construction as matrix_rain.gdshader.
float glyph(vec2 cuv, float id) {
	vec2 inner = (cuv - vec2(0.15, 0.1)) / vec2(0.7, 0.8);
	if (any(lessThan(inner, vec2(0.0))) || any(greaterThan(inner, vec2(1.0)))) {
		return 0.0;
	}
	vec2 px = floor(inner * vec2(4.0, 5.0));
	return step(0.42, _h2(px + vec2(id * 17.0, id * 31.0)));
}

void vertex() {
	// Elliptical orbit around the node origin, golden-angle phase spread per seed.
	float a = TIME * orbit_speed * (0.7 + 0.6 * _h(seed)) + seed * 2.39996;
	vec3 orbit = vec3(
			cos(a) * orbit_radius,
			sin(TIME * (0.8 + _h(seed + 9.0)) + seed) * bob_height,
			sin(a) * orbit_radius * 0.7);
	mat4 model = MODEL_MATRIX;
	model[3].xyz += orbit;

	// Spherical billboard that keeps the node's scale (wall_torch_halo math).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], model[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float id = mod(floor(_h(seed * 3.7) * 64.0 + TIME * glyph_flip_speed), 64.0);
	float g = glyph(UV, id);
	float fade = 0.65 + 0.35 * sin(TIME * 1.7 + seed * 4.0);
	ALBEDO = glyph_color * brightness * g;
	ALPHA = g * fade;
}
