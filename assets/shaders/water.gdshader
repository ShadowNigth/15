shader_type spatial;
render_mode ambient_light_disabled, diffuse_burley, specular_schlick_ggx, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float lightmap_boost : hint_range(0.5, 3.0) = 1.25;
uniform float alpha_Val : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float wave_x = sin(UV.x * 38.0 + TIME * 1.75 + sin(UV.y * 17.0 - TIME * 0.65));
	float wave_y = cos(UV.y * 43.0 - TIME * 1.35 + cos(UV.x * 21.0 + TIME * 0.55));
	vec2 wave_uv = UV + vec2(wave_x, wave_y) * 0.008;
	vec4 tex = texture(albedo_tex, wave_uv);
	vec3 lm_raw = texture(lightmap_tex, UV2).rgb;
	vec3 lm = pow(max(lm_raw, vec3(0.001)), vec3(0.84)) * lightmap_boost;
	lm = clamp(lm, vec3(0.14), vec3(1.60));

	vec2 refraction_uv = clamp(SCREEN_UV + vec2(wave_x, wave_y) * 0.0055, vec2(0.002), vec2(0.998));
	vec3 behind = texture(screen_tex, refraction_uv).rgb;
	vec3 water_tint = tex.rgb * vec3(0.68, 0.88, 0.94);
	vec3 water_colour = mix(behind, water_tint, 0.44);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.0);

	ALBEDO = water_colour * 0.15;
	EMISSION = water_colour * (0.70 + lm * 0.18) + vec3(0.10, 0.16, 0.19) * fresnel;
	NORMAL = normalize(NORMAL + vec3(wave_x * 0.13, wave_y * 0.13, 0.0));
	ROUGHNESS = 0.18;
	METALLIC = 0.04;
	SPECULAR = 0.68;
	ALPHA = clamp(alpha_Val + fresnel * 0.14, 0.32, 0.86);
}
