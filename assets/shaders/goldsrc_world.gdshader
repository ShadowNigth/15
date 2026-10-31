shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear;
uniform float lightmap_boost : hint_range(0.5, 3.5) = 1.55;
uniform float alpha_Val : hint_range(0.0, 1.0) = 1.0;
uniform bool use_alpha_scissor = false;
uniform bool is_water = false;

void fragment() {
	vec2 uv = UV;
	if (is_water) {
		uv.x += sin(TIME * 1.6 + UV.y * 6.2831) * 0.03;
		uv.y += cos(TIME * 1.3 + UV.x * 6.2831) * 0.03;
	}
	vec4 tex = texture(albedo_tex, uv);
	if (use_alpha_scissor && tex.a < 0.5) {
		discard;
	}
	vec3 lm = texture(lightmap_tex, UV2).rgb * lightmap_boost;
	lm = clamp(lm, vec3(0.10), vec3(2.4));
	ALBEDO = tex.rgb;
	// Base lighting comes from authentic baked GoldSrc RGB lightmaps; dynamic OmniLight3D / SpotLight3D add on top!
	EMISSION = tex.rgb * lm;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	if (alpha_Val < 0.999) {
		ALPHA = alpha_Val * tex.a;
	}
}
