shader_type canvas_item;
render_mode unshaded;

// Full-screen overlay: desaturates everything drawn beneath it, except inside a
// circular "spotlight" (e.g. where the player's finger entered) which stays in
// full colour. `amount` scales the whole effect for fade in/out.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5, 0.5); // spotlight centre in screen UV
uniform float radius = 0.16;          // spotlight radius (in height-normalized units)
uniform float softness = 0.05;        // edge feather
uniform float amount = 1.0;           // 0 = no effect (full colour), 1 = full grayscale outside
uniform float aspect = 1.7777;        // viewport width / height, keeps the circle round

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));

	vec2 d = SCREEN_UV - center;
	d.x *= aspect;
	float dist = length(d);

	// 1.0 inside the spotlight, 0.0 outside (feathered edge)
	float inside = 1.0 - smoothstep(radius, radius + softness, dist);
	float gray = (1.0 - inside) * clamp(amount, 0.0, 1.0);

	COLOR = vec4(mix(col, vec3(lum), gray), 1.0);
}
