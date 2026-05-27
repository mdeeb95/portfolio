shader_type sky;

// Godot docs: cubemap skies need source_color on the sampler (Compatibility / GLES).
uniform samplerCube sky_cube : filter_linear, source_color, hint_default_black;
uniform float exposure : hint_range(0.1, 4.0, 0.01) = 1.35;

void sky() {
	COLOR = texture(sky_cube, EYEDIR).rgb * exposure;
}
