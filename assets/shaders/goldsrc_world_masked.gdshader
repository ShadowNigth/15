shader_type spatial;
render_mode ambient_light_disabled, diffuse_lambert, specular_disabled, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear;
uniform float lightmap_boost : hint_range(0.5, 3.0) = 1.25;

uniform float lightmap_exponent = 0.84;
uniform float lightmap_floor = 0.10;
uniform float lightmap_ceiling = 1.60;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 lm_raw = texture(lightmap_tex, UV2).rgb;
	vec3 lm = pow(max(lm_raw, vec3(0.001)), vec3(lightmap_exponent)) * lightmap_boost;
	lm = clamp(lm, vec3(lightmap_floor), vec3(lightmap_ceiling));

	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * lm;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
