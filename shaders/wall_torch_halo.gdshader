shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Billboarded radial glow quad — fakes bloom around the torch's emissive parts,
// since environment glow is disabled (too costly for web/mobile GL Compatibility).
// Flickers in sync with wall_torch_glow.gdshader (same value-noise over TIME).

uniform vec3 accent_color : source_color = vec3(0.25, 0.84, 1.0);
uniform float brightness : hint_range(0.0, 4.0, 0.01) = 0.9;
uniform float flicker_amount : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float flicker_speed : hint_range(0.0, 20.0, 0.1) = 6.0;

float _h(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void vertex() {
	// Spherical billboard that keeps the node's scale (same math as BaseMaterial3D's
	// BILLBOARD_ENABLED), so elongated halos stay elongated on screen.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0;
	float falloff = smoothstep(1.0, 0.0, r);
	falloff *= falloff * falloff; // tight hot core, long soft tail

	float t = TIME * flicker_speed;
	float f = fract(t);
	float n = mix(_h(floor(t)), _h(floor(t) + 1.0), f * f * (3.0 - 2.0 * f));
	float flicker = 1.0 - flicker_amount * n;

	ALBEDO = accent_color * brightness * flicker;
	ALPHA = clamp(falloff, 0.0, 1.0);
}
