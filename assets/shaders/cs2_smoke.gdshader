shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.38, 0.82, 0.42);
uniform vec3 light_top_col : source_color = vec3(0.95, 0.96, 0.98);
uniform vec3 shadow_belly_col : source_color = vec3(0.41, 0.44, 0.50);

varying vec4 v_custom;
varying vec3 v_view_ray;
varying vec3 v_cam_right;
varying vec3 v_cam_up;
varying vec3 v_cam_fwd;

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
	vec3 cam_fwd = INV_VIEW_MATRIX[2].xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;

	v_cam_right = cam_right;
	v_cam_up = cam_up;
	v_cam_fwd = cam_fwd;

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

		float t = TIME * 0.048;
		vec2 uv1 = UV * 0.64 + vec2(seed * 3.71 + t * 0.62, seed * 5.13 - t * 0.46);
		vec3 n1 = texture(noise_tex, uv1).rgb;

		vec2 warp = (n1.rg - vec2(0.5)) * (0.28 + agitate * 0.18);
		vec2 uv2 = UV * 1.32 + warp + vec2(-seed * 2.83 - t * 0.52, seed * 4.29 + t * 0.58);
		vec3 n2 = texture(noise_tex, uv2).rgb;

		float cumulus = n1.r * 0.56 + n2.g * 0.44;
		float detail = n2.b;

		// Plump, thick CS2 cauliflower silhouette with solid volumetric interior
		float rad = sqrt(r2);
		float pert_rad = rad - (cumulus - 0.5) * 0.42 - (detail - 0.5) * 0.14;
		float radial_mask = 1.0 - smoothstep(0.38, 0.97, pert_rad);
		float hemi_z = sqrt(max(0.0, 1.0 - r2));
		float hemi_thick = pow(hemi_z, 0.34);
		float density = clamp(radial_mask * hemi_thick * (0.94 + 0.52 * cumulus), 0.0, 1.0);

		// CS2 turbulent FBM erosion when bullets or HE shockwaves carve the voxel!
		float erode = agitate * (0.46 + 0.74 * (1.0 - detail));
		density = clamp((density - erode) / max(0.18, 1.0 - agitate * 0.42), 0.0, 1.0);

		// Perturbed 3D cumulus billow normal for rich CS2 volumetric light & crevice relief!
		vec2 n_pert = (n1.rg - vec2(0.5)) * 0.72 + (n2.gb - vec2(0.5)) * 0.46;
		vec3 local_n = normalize(vec3(p.x * 0.78 + n_pert.x, -p.y * 0.78 + n_pert.y, hemi_z * 0.92 + 0.18));
		vec3 world_n = normalize(v_cam_right * local_n.x + v_cam_up * local_n.y + v_cam_fwd * local_n.z);
		vec3 L = normalize(sun_dir);
		float ndotl = clamp(dot(world_n, L) * 0.52 + 0.50, 0.0, 1.0);

		// Crevice ambient occlusion + macro dome elevation lighting
		float crevice_ao = smoothstep(0.16, 0.84, cumulus * 0.72 + detail * 0.28);
		float lit = clamp(mix(h_dome, ndotl, 0.56) * (0.72 + 0.34 * crevice_ao), 0.0, 1.0);

		// Henyey-Greenstein forward sun silver-lining scattering on outer cumulus rims
		float cos_theta = clamp(dot(v_view_ray, L) * 0.5 + 0.5, 0.0, 1.0);
		float phase = pow(cos_theta, 3.0);
		float silver_rim = pow(1.0 - density * 0.88, 1.65) * radial_mask * (0.08 + 0.17 * phase);

		vec3 base_col = mix(shadow_belly_col, light_top_col, smoothstep(0.05, 0.95, lit));
		ALBEDO = clamp(base_col * COLOR.rgb + vec3(silver_rim), vec3(0.0), vec3(1.0));
		ALPHA = clamp(density * COLOR.a, 0.0, 0.985);
	}
}
