shader_type canvas_item;
// Subtle screen blur applied while moving with the sniper scope up (CS:GO
// movement blur). 25-tap disc sampled from the backbuffer; u_strength is the
// blur radius in pixels and is lerped from CSHud.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float u_strength = 0.0;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb * 0.20;
	if (u_strength > 0.05) {
		vec2 r = SCREEN_PIXEL_SIZE * u_strength;
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 0.5235988; // 2*PI/12
			vec2 dir = vec2(cos(a), sin(a));
			col += texture(screen_tex, SCREEN_UV + dir * r).rgb * 0.0333;
			col += texture(screen_tex, SCREEN_UV + dir * r * 0.5).rgb * 0.0333;
		}
	}
	COLOR = vec4(col, 1.0);
}
