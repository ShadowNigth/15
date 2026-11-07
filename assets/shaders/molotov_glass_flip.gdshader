shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, specular_schlick_ggx;

// Liquid-glass bottle: screen-space transmission/refraction, Fresnel edge
// reflection and subtle moving micro-normal distortion. Bright printed texels
// remain readable instead of becoming part of the transparent glass.
uniform sampler2D bottle_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 bottle_tint : source_color = vec4(1.0);
uniform vec3 glass_tint : source_color = vec3(0.82, 1.04, 0.88);
uniform float glass_opacity = 0.48;
uniform float refraction_strength = 0.018;
uniform float brightness = 1.12;

void fragment() {
	vec4 texel = texture(bottle_texture, UV);
	vec3 colour = texel.rgb * bottle_tint.rgb;
	float luminance = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	float printed_detail = smoothstep(0.25, 0.52, luminance);
	vec2 micro = vec2(
		sin(UV.y * 41.0 + TIME * 0.75),
		cos(UV.x * 37.0 - TIME * 0.62)
	) * 0.018;
	vec3 surface_normal = normalize(NORMAL + vec3(micro, 0.0));
	float facing = clamp(abs(dot(surface_normal, normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.0);
	vec2 distortion = surface_normal.xy * refraction_strength * (0.55 + fresnel * 0.85);
	vec2 screen_uv = clamp(SCREEN_UV + distortion, vec2(0.001), vec2(0.999));
	vec3 transmitted = textureLod(screen_texture, screen_uv, 0.0).rgb;
	transmitted *= mix(vec3(1.0), glass_tint, 0.32);
	vec3 green_glass = colour * glass_tint * brightness;
	vec3 liquid_glass = mix(transmitted, green_glass, 0.20 + fresnel * 0.25);
	ALBEDO = mix(liquid_glass, colour * brightness, printed_detail);
	NORMAL = surface_normal;
	ROUGHNESS = mix(0.10, 0.045, fresnel);
	METALLIC = 0.0;
	SPECULAR = 0.90;
	EMISSION = vec3(0.025, 0.035, 0.028) * fresnel * (1.0 - printed_detail);
	float clear_alpha = clamp(glass_opacity + fresnel * 0.42, 0.0, 0.86);
	ALPHA = mix(clear_alpha, 0.98, printed_detail) * bottle_tint.a;
}
