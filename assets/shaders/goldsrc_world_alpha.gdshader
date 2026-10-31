shader_type spatial;
render_mode ambient_light_disabled, diffuse_lambert, specular_disabled, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear;
uniform float lightmap_boost : hint_range(0.5, 3.0) = 1.25;
uniform float alpha_Val : hint_range(0.0, 1.0) = 0.72;
uniform bool is_water = false;

void fragment() {
	vec2 uv = UV;
	if (is_water) {
		uv.x += sin(TIME * 1.6 + UV.y * 6.2831) * 0.03;
		uv.y += cos(TIME * 1.3 + UV.x * 6.2831) * 0.03;
	}
	vec4 tex = texture(albedo_tex, uv);
	vec3 lm_raw = texture(lightmap_tex, UV2).rgb;
	vec3 lm = pow(max(lm_raw, vec3(0.001)), vec3(0.84)) * lightmap_boost;
	lm = clamp(lm, vec3(0.14), vec3(1.60));

	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * lm;
	ALPHA = clamp(alpha_Val * tex.a, 0.08, 0.96);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
