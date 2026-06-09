shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Radial glow pool under the tractor beam, with a slow swirl so it reads as energy, not paint.
// Shares beam_color / intensity_mul with tractor_beam.gdshader (both driven by tractor_beam.gd).

uniform vec3 beam_color : source_color = vec3(0.25, 0.84, 1.0);
uniform float brightness : hint_range(0.0, 4.0, 0.01) = 1.2;
uniform float intensity_mul : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float swirl_speed : hint_range(-2.0, 2.0, 0.01) = 0.25;
uniform float swirl_strength : hint_range(0.0, 1.0, 0.01) = 0.35;

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

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv);
	float angle = atan(uv.y, uv.x) + TIME * swirl_speed;
	float swirl = _gn(vec2(angle * 2.0, r * 6.0 - TIME * swirl_speed * 2.0));
	float falloff = smoothstep(0.5, 0.0, r);
	falloff *= falloff;
	float density = falloff * (1.0 - swirl_strength + swirl_strength * swirl);
	ALBEDO = beam_color * brightness * intensity_mul;
	ALPHA = clamp(density, 0.0, 1.0);
}
