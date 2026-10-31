shader_type spatial;
render_mode ambient_light_disabled, diffuse_lambert, specular_disabled, cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear;
uniform float lightmap_boost : hint_range(0.5, 3.0) = 1.25;

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 lm_raw = texture(lightmap_tex, UV2).rgb;
	vec3 lm = pow(max(lm_raw, vec3(0.001)), vec3(0.84)) * lightmap_boost;
	lm = clamp(lm, vec3(0.10), vec3(1.60));

	ALBEDO = tex;
	EMISSION = tex * lm;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
