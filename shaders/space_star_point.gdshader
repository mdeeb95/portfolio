shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Camera-facing soft round star for the MultiMesh star shell. Per-instance colour (and
// brightness baked into that colour) comes from the MultiMesh instance colour buffer (COLOR).

void vertex() {
	// Billboard each instance toward the camera, preserving its per-instance scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(sx, 0.0, 0.0, 0.0), vec4(0.0, sy, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv);
	float a = pow(smoothstep(0.5, 0.0, r), 1.6);   // soft round falloff
	ALBEDO = COLOR.rgb;
	ALPHA = a * COLOR.a;
}
