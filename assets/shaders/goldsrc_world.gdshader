shader_type spatial;
render_mode ambient_light_disabled, diffuse_lambert, specular_disabled, cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear;
uniform float lightmap_boost : hint_range(0.5, 3.0) = 1.25;
uniform float lightmap_exponent = 0.84;
uniform float lightmap_floor = 0.10;
uniform float lightmap_ceiling = 1.60;
uniform float material_roughness = 0.94;
uniform float relief_depth : hint_range(0.0, 0.12) = 0.045;
uniform float relief_light_strength : hint_range(0.0, 1.5) = 0.82;
uniform float detail_strength : hint_range(0.0, 0.8) = 0.34;

float world_height(vec3 colour) {
	return dot(colour, vec3(0.299, 0.587, 0.114));
}

vec3 sample_defined_albedo(vec2 uv) {
	// Sharpen local detail at the same mip level instead of disabling mipmaps.
	// This keeps distant architecture stable while making close walls/floors crisp.
	vec2 dimensions = vec2(textureSize(albedo_tex, 0));
	vec2 dx = dFdx(uv) * dimensions;
	vec2 dy = dFdy(uv) * dimensions;
	float lod = clamp(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 0.000001)), 0.0, 12.0);
	vec3 sharp = textureLod(albedo_tex, uv, lod).rgb;
	vec3 soft = textureLod(albedo_tex, uv, lod + 1.0).rgb;
	return clamp(sharp + (sharp - soft) * detail_strength, vec3(0.0), vec3(1.0));
}

vec3 height_relief_normal(vec3 base_normal, vec3 view_position, float height, float depth) {
	if (depth <= 0.00001) {
		return base_normal;
	}
	// Cotangent-frame bump mapping: the converted BSP has normals and UVs but
	// no tangent buffer, so derive a stable frame from screen-space derivatives.
	vec3 sigma_x = dFdx(view_position);
	vec3 sigma_y = dFdy(view_position);
	vec3 r1 = cross(sigma_y, base_normal);
	vec3 r2 = cross(base_normal, sigma_x);
	float determinant = dot(sigma_x, r1);
	if (abs(determinant) < 0.0000001) {
		return base_normal;
	}
	vec3 gradient = sign(determinant) * (dFdx(height) * r1 + dFdy(height) * r2);
	return normalize(abs(determinant) * base_normal - depth * gradient);
}

void fragment() {
	vec3 tex = sample_defined_albedo(UV);
	vec3 lm_raw = texture(lightmap_tex, UV2).rgb;
	vec3 lm = pow(max(lm_raw, vec3(0.001)), vec3(lightmap_exponent)) * lightmap_boost;
	lm = clamp(lm, vec3(lightmap_floor), vec3(lightmap_ceiling));

	vec3 base_normal = normalize(NORMAL);
	float height = world_height(tex);
	vec3 relief_normal = height_relief_normal(base_normal, VERTEX, height, relief_depth);
	vec3 light_direction = normalize((VIEW_MATRIX * vec4(normalize(vec3(-0.38, 0.82, 0.42)), 0.0)).xyz);
	float relief_delta = dot(relief_normal, light_direction) - dot(base_normal, light_direction);
	float relief_shade = clamp(1.0 + relief_delta * relief_light_strength, 0.62, 1.42);

	ALBEDO = tex;
	EMISSION = tex * lm * relief_shade;
	NORMAL = relief_normal;
	ROUGHNESS = material_roughness;
	METALLIC = 0.0;
}
