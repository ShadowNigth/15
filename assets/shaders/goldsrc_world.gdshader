shader_type spatial;
render_mode ambient_light_disabled, diffuse_lambert, specular_disabled, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear;
uniform float lightmap_boost : hint_range(0.5, 3.0) = 1.22;
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
	// GoldSrc hlrad lightmap is stored in gamma space; apply authentic GoldSrc overbright curve
	vec3 lm_raw = texture(lightmap_tex, UV2).rgb;
	vec3 lm = pow(max(lm_raw, vec3(0.001)), vec3(0.85)) * lightmap_boost;
	lm = clamp(lm, vec3(0.09), vec3(1.55));

	// ALBEDO receives dynamic lights on Layer 1 (Flashlight F, Muzzle Flash, C4 Blast);
	// SunLight is masked to Layer 2 (Players/Weapons/Props) so world surfaces are never double-lit!
	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * lm;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	if (alpha_Val < 0.999) {
		ALPHA = alpha_Val * tex.a;
	}
}
