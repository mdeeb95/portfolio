shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Holographic flame on an open-ended tapered cylinder — same recipe as
// tractor_beam.gdshader (rim + scrolling bands + one cheap noise octave),
// scaled down and scrolling upward like a torch flame.

uniform vec3 accent_color : source_color = vec3(1.0, 0.62, 0.25);
uniform float flame_height = 0.26; // must match the CylinderMesh height
uniform float brightness : hint_range(0.0, 4.0, 0.01) = 2.2;
uniform float flicker_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float flicker_speed : hint_range(0.0, 20.0, 0.1) = 7.0;
uniform float band_count : hint_range(1.0, 16.0, 0.5) = 3.0;
uniform float scroll_speed : hint_range(-4.0, 4.0, 0.05) = 1.4;
uniform float noise_strength : hint_range(0.0, 0.5, 0.01) = 0.22;

varying float v_h; // 0 at flame base, 1 at tip

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
	v_h = clamp(VERTEX.y / flame_height + 0.5, 0.0, 1.0);
}

void fragment() {
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW))); // abs(): cull_disabled back faces
	float rim = pow(1.0 - ndv, 1.5);
	float core = pow(ndv, 2.0) * 0.5;

	// Upward-scrolling bands, wobbled so the flame licks instead of pulsing evenly.
	float h = v_h + (_gn(vec2(v_h * 3.0, TIME * 0.6)) - 0.5) * noise_strength;
	float bands = 0.65 + 0.35 * sin((h * band_count - TIME * scroll_speed) * TAU);

	// Bright base, soft tip.
	float body = smoothstep(0.0, 0.1, v_h) * (1.0 - smoothstep(0.45, 1.0, v_h) * 0.85);

	float t = TIME * flicker_speed;
	float f = fract(t);
	float n = mix(_gh(vec2(floor(t), 7.0)), _gh(vec2(floor(t) + 1.0, 7.0)), f * f * (3.0 - 2.0 * f));
	float flicker = 1.0 - flicker_amount * n;

	ALBEDO = accent_color * brightness * flicker;
	ALPHA = clamp((rim + core) * bands * body, 0.0, 1.0);
}
