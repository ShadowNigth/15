shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.38, 0.82, 0.42);
uniform vec3 light_top_col : source_color = vec3(0.92, 0.93, 0.95);
uniform vec3 shadow_belly_col : source_color = vec3(0.45, 0.48, 0.53);

varying vec4 v_custom;
varying vec3 v_view_ray;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float ang = INSTANCE_CUSTOM.w;
	float ca = cos(ang);
	float sa = sin(ang);
	vec2 r_pos = vec2(VERTEX.x * ca - VERTEX.y * sa, VERTEX.x * sa + VERTEX.y * ca);

	vec3 world_center = MODEL_MATRIX[3].xyz;
	vec2 inst_scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;

	vec3 world_pos = world_center + cam_right * (r_pos.x * inst_scale.x) + cam_up * (r_pos.y * inst_scale.y);
	v_view_ray = normalize(world_pos - cam_pos);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - vec2(1.0);
	float r2 = dot(p, p);
	if (r2 >= 1.0) {
		ALPHA = 0.0;
	} else {
		float seed = v_custom.x;
		float agitate = clamp(v_custom.y, 0.0, 1.0);
		float h_dome = clamp(v_custom.z, 0.0, 1.0);

		float t = TIME * 0.052;
		vec2 uv1 = UV * 0.68 + vec2(seed * 3.71 + t * 0.65, seed * 5.13 - t * 0.48);
		vec3 n1 = texture(noise_tex, uv1).rgb;

		vec2 warp = (n1.rg - vec2(0.5)) * (0.26 + agitate * 0.16);
		vec2 uv2 = UV * 1.38 + warp + vec2(-seed * 2.83 - t * 0.55, seed * 4.29 + t * 0.62);
		vec3 n2 = texture(noise_tex, uv2).rgb;

		float cumulus = n1.r * 0.56 + n2.g * 0.44;
		float detail = n2.b;

		float rad = sqrt(r2);
		float pert_rad = rad - (cumulus - 0.5) * 0.38 - (detail - 0.5) * 0.12;
		float radial_mask = 1.0 - smoothstep(0.18, 0.96, pert_rad);
		float hemi_thick = sqrt(max(0.0, 1.0 - r2));
		float density = radial_mask * hemi_thick * (0.78 + 0.54 * cumulus);

		// CS2 turbulent FBM erosion when bullets or HE shockwaves carve the voxel!
		float erode = agitate * (0.44 + 0.72 * (1.0 - detail));
		density = clamp((density - erode) / max(0.18, 1.0 - agitate * 0.40), 0.0, 1.0);

		// Volumetric self-shadowing (QuadMesh UV.y=0 is top, so -p.y points upward!)
		float puff_up = clamp(-p.y * 0.48 + 0.52 + (cumulus - 0.5) * 0.42, 0.0, 1.0);
		float lit = clamp(mix(h_dome, puff_up, 0.50) * 0.84 + cumulus * 0.22, 0.0, 1.0);

		// Henyey-Greenstein forward sun silver-lining scattering on thin aerosol rims
		float cos_theta = clamp(dot(v_view_ray, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
		float phase = pow(cos_theta, 3.2);
		float silver_rim = pow(1.0 - density, 1.75) * radial_mask * (0.09 + 0.16 * phase);

		vec3 base_col = mix(shadow_belly_col, light_top_col, smoothstep(0.06, 0.94, lit));
		ALBEDO = clamp(base_col * COLOR.rgb + vec3(silver_rim), vec3(0.0), vec3(1.0));
		ALPHA = clamp(density * COLOR.a, 0.0, 0.98);
	}
}
