shader_type spatial;
render_mode unshaded, shadows_disabled;

// Procedural "matrix rain" for the hacker terminal screen — columns of fake
// glyphs falling with a bright head and fading tail. Entirely TIME-driven,
// opaque (stays out of the transparent pipeline on GL Compatibility).
// Hashes are fract-based (no sin): editor/game TIME gets large and
// fract(sin(big)) collapses to 0 in fp32, blanking every glyph.

uniform vec3 rain_color : source_color = vec3(0.12, 1.0, 0.35);
uniform vec3 head_color : source_color = vec3(0.75, 1.0, 0.85);
uniform vec3 bg_color : source_color = vec3(0.0, 0.045, 0.012);
uniform float base_energy : hint_range(0.0, 6.0, 0.01) = 2.2;
uniform vec2 grid = vec2(22.0, 12.0);
uniform float fall_speed : hint_range(0.0, 4.0, 0.01) = 0.55;
uniform float tail_rows : hint_range(1.0, 20.0, 0.5) = 7.0;
uniform float glyph_flip_speed : hint_range(0.0, 20.0, 0.1) = 4.0;
uniform float flicker_amount : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float flicker_speed : hint_range(0.0, 20.0, 0.1) = 6.0;

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

// Fake glyph: a 4x5 pixel grid inside the cell, pixels lit by hashing
// against the glyph id — reads as katakana-ish code at a distance.
float glyph(vec2 cuv, float id) {
	vec2 inner = (cuv - vec2(0.15, 0.1)) / vec2(0.7, 0.8);
	if (any(lessThan(inner, vec2(0.0))) || any(greaterThan(inner, vec2(1.0)))) {
		return 0.0;
	}
	vec2 px = floor(inner * vec2(4.0, 5.0));
	return step(0.42, _h2(px + vec2(id * 17.0, id * 31.0)));
}

void fragment() {
	vec2 cell = floor(UV * grid);
	vec2 cuv = fract(UV * grid);
	float col = cell.x;

	float speed = fall_speed * (0.6 + 0.8 * _h(col));
	float head = fract(TIME * speed + _h(col + 57.0));
	float row_n = cell.y / grid.y; // QuadMesh UV.y: 0 top -> 1 bottom
	float behind = fract(head - row_n);
	float trail = clamp(1.0 - behind * grid.y / tail_rows, 0.0, 1.0);
	trail *= trail;
	float is_head = step(behind, 1.0 / grid.y);

	// Glyphs mutate over time, faster near the rain head; id wrapped to keep
	// the hash input small (fp32).
	float id = mod(floor(_h2(cell) * 64.0 + TIME * glyph_flip_speed * (0.3 + 0.7 * trail)), 64.0);
	float g = glyph(cuv, id);

	float t = TIME * flicker_speed;
	float f = fract(t);
	float n = mix(_h(floor(t)), _h(floor(t) + 1.0), f * f * (3.0 - 2.0 * f));
	float flicker = 1.0 - flicker_amount * n;

	vec3 c = mix(rain_color, head_color, is_head) * g * max(trail, is_head);
	ALBEDO = (bg_color + c) * base_energy * flicker;
}
