shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

// A separate closed liquid volume sloshes inside the refractive outer bottle.
// Screen transmission keeps it liquid rather than an opaque green solid.
uniform sampler2D liquid_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 liquid_tint : source_color = vec4(0.72, 0.94, 0.58, 1.0);
uniform float brightness = 1.16;
uniform float deformation = 1.0;
uniform float opacity = 0.58;
uniform float refraction_strength = 0.008;

void vertex() {
	// Viewmodel bind pose has its liquid surface near local Y=0.062. Only the
	// upper volume moves; the bottom stays seated in the bottle. World models
	// use deformation=0 and retain the subtle fragment-space motion below.
	float surface = smoothstep(-0.035, 0.062, VERTEX.y);
	float wave_a = sin(VERTEX.x * 92.0 + TIME * 3.4);
	float wave_b = cos(VERTEX.z * 81.0 - TIME * 2.7);
	VERTEX.y += deformation * surface * wave_a * wave_b * 0.0025;
	VERTEX.x += deformation * surface * sin(TIME * 1.9) * 0.0012;
}

void fragment() {
	vec2 flow = vec2(sin(TIME * 0.72), cos(TIME * 0.61)) * 0.003;
	vec3 tex = texture(liquid_texture, UV + flow).rgb;
	float shimmer_x = sin(UV.x * 44.0 + TIME * 2.3) * 0.055;
	float shimmer_y = cos(UV.y * 39.0 - TIME * 1.8) * 0.055;
	vec2 screen_uv = clamp(SCREEN_UV + NORMAL.xy * refraction_strength + flow * 0.25, vec2(0.001), vec2(0.999));
	vec3 transmitted = textureLod(screen_texture, screen_uv, 0.0).rgb * liquid_tint.rgb;
	vec3 body = tex * liquid_tint.rgb * brightness;
	ALBEDO = mix(transmitted, body, 0.38);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.78;
	NORMAL = normalize(NORMAL + vec3(shimmer_x, shimmer_y, 0.0));
	ALPHA = opacity * liquid_tint.a;
}
