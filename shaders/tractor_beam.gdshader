shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Anti-grav tractor beam on an open-ended tapered cylinder. Additive + unshaded so it only
// ever adds light; the actual scene lighting comes from the sibling OmniLight3D.
// intensity_mul is pulsed from tractor_beam.gd so the mesh and the light breathe in phase.

uniform vec3 beam_color : source_color = vec3(0.25, 0.84, 1.0);
uniform float beam_height = 2.1; // must match the CylinderMesh height (synced by tractor_beam.gd)
uniform float brightness : hint_range(0.0, 4.0, 0.01) = 2.0;
uniform float intensity_mul : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float band_count : hint_range(1.0, 16.0, 0.5) = 6.0;
uniform float scroll_speed : hint_range(-4.0, 4.0, 0.05) = 0.9;
uniform float bottom_fade : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float top_fade : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float noise_strength : hint_range(0.0, 0.5, 0.01) = 0.12;

varying float v_h; // 0 at beam bottom, 1 at top

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

void vertex() {
	// CylinderMesh UVs are an atlas (sides + caps) — derive height from local Y instead.
	v_h = clamp(VERTEX.y / beam_height + 0.5, 0.0, 1.0);
}

void fragment() {
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW))); // abs(): cull_disabled back faces
	float rim = pow(1.0 - ndv, 1.5);
	float core = pow(ndv, 2.0) * 0.35;

	// Downward-scrolling energy bands, wobbled by one cheap noise octave.
	float h = v_h + (_gn(vec2(v_h * 3.0, TIME * 0.35)) - 0.5) * noise_strength;
	float bands = 0.6 + 0.4 * sin((h * band_count + TIME * scroll_speed) * TAU);

	float fades = smoothstep(0.0, bottom_fade, v_h) * smoothstep(1.0, 1.0 - top_fade, v_h);

	ALBEDO = beam_color * brightness * intensity_mul;
	ALPHA = clamp((rim + core) * bands * fades, 0.0, 1.0);
}
