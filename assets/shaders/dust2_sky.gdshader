shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Preserve original mountain artwork; sky-only detail is continuous in world
// direction, so clouds/gradient cannot develop cube-face seams. No TIME or RTT.
uniform sampler2D original_sky : source_color, filter_linear, repeat_disable;
varying vec3 sky_direction;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
		mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	sky_direction = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}
void fragment() {
	vec3 d = normalize(sky_direction);
	vec3 original = texture(original_sky, UV).rgb;
	float clear_sky = smoothstep(0.015, 0.14, original.b - original.r * 0.85);
	float high_sky = smoothstep(0.18, 0.42, d.y);
	float mask = clear_sky * high_sky;
	vec3 gradient = mix(vec3(0.61, 0.65, 0.67), vec3(0.10, 0.23, 0.42), pow(clamp(d.y, 0.0, 1.0), 0.5));
	vec3 p = d * vec3(4.5, 19.0, 4.5) + vec3(7, 1, 3);
	float cloud = noise3(p) * 0.58 + noise3(p * 2.1) * 0.28 + noise3(p * 4.2) * 0.14;
	float wisps = smoothstep(0.49, 0.77, cloud) * 0.43;
	float sun_halo = pow(max(dot(d, normalize(vec3(-0.38, 0.82, 0.42))), 0.0), 32.0);
	vec3 sky = mix(gradient, vec3(0.88, 0.83, 0.74), wisps);
	sky += vec3(0.10, 0.07, 0.03) * sun_halo;
	ALBEDO = mix(original, sky, mask * 0.86);
}
