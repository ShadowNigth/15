shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

// The archi bottle contains two textured green surfaces plus a separate liquid
// volume. Dark green texels are glass; bright label/rag texels stay readable.
// This avoids both an opaque bottle and a completely invisible paper label.
uniform sampler2D bottle_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 bottle_tint : source_color = vec4(1.0);
uniform float glass_opacity = 0.14;
uniform float brightness = 1.18;

void fragment() {
	vec4 texel = texture(bottle_texture, UV);
	vec3 colour = texel.rgb * bottle_tint.rgb;
	float luminance = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	float printed_detail = smoothstep(0.25, 0.52, luminance);
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 3.0);
	float clear_alpha = max(glass_opacity, fresnel * 0.42);
	ALBEDO = colour * brightness + vec3(fresnel * 0.035);
	ROUGHNESS = mix(0.16, 0.075, fresnel);
	METALLIC = 0.0;
	SPECULAR = 0.82;
	ALPHA = mix(clear_alpha, 0.96, printed_detail) * bottle_tint.a;
}
