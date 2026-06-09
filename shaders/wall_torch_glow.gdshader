shader_type spatial;
render_mode unshaded, shadows_disabled;

// Opaque emissive surface for wall torch tubes/bars. Flicker is TIME-driven so
// the torches animate with zero per-frame script cost (wall_torch.gd only pushes
// exported config into the material). Opaque on purpose — keeps these meshes out
// of the transparent pipeline, which matters on the GL Compatibility renderer.

uniform vec3 accent_color : source_color = vec3(0.25, 0.84, 1.0);
uniform float base_energy : hint_range(0.0, 6.0, 0.01) = 1.7;
uniform float flicker_amount : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float flicker_speed : hint_range(0.0, 20.0, 0.1) = 6.0;

float _h(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void fragment() {
	// Value noise over time: smooth wander between random levels, no texture fetch.
	float t = TIME * flicker_speed;
	float f = fract(t);
	float n = mix(_h(floor(t)), _h(floor(t) + 1.0), f * f * (3.0 - 2.0 * f));
	float flicker = 1.0 - flicker_amount * n;
	// Slight vertical gradient so the surface reads as a lit tube, not flat paint.
	float shade = 0.82 + 0.18 * (1.0 - UV.y);
	ALBEDO = accent_color * base_energy * flicker * shade;
}
