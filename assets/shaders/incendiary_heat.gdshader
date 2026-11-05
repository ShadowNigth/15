shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D heat_screen : hint_screen_texture, repeat_disable, filter_linear;
uniform float seed = 0.0;
uniform float ignition = 1.0;
uniform float fade = 1.0;

void vertex() {
	// Camera-facing heat plume; flame geometry itself remains genuinely crossed.
	vec4 right = vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0);
	vec4 up = vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0);
	vec4 forward = vec4(INV_VIEW_MATRIX[2].xyz, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(right, up, forward, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 centred = (UV - vec2(0.5)) * vec2(1.0, 0.82);
	float plume = 1.0 - smoothstep(0.18, 0.53, length(centred));
	float ripple = sin(UV.y * 29.0 + TIME * 3.1 + seed) * 0.55
		+ sin(UV.x * 23.0 - TIME * 2.3 + seed * 1.7) * 0.45;
	vec2 offset = vec2(ripple, cos(ripple * 2.2 + TIME + seed)) * 0.0017 * plume * fade;
	vec3 behind = texture(heat_screen, clamp(SCREEN_UV + offset, vec2(0.002), vec2(0.998))).rgb;
	ALBEDO = behind;
	ALPHA = clamp(plume * 0.24 * ignition * fade, 0.0, 0.24);
}
