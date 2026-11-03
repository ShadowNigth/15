shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// CS2-like ground fire: a violet fuel fringe, orange turbulent body and a
// white-yellow hot core. Every patch has an independent seed so a spreading
// fire does not look like one repeated billboard.
uniform float seed = 0.0;
uniform float layer = 0.0; // 0 = outer flame, 1 = compact hot core
uniform float ignition = 1.0;
uniform float fade = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		sum += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return sum;
}

float tongue(vec2 p, float h, float centre, float width, float height, float phase) {
	float travel = TIME * (1.45 + layer * 0.35);
	float curl = fbm(vec2(centre * 7.0 + seed + phase, h * 3.4 - travel));
	float sway = sin(h * 7.2 + phase + seed) * 0.055 * h;
	sway += (curl - 0.5) * 0.19 * h;
	float remaining = clamp(1.0 - h / height, 0.0, 1.0);
	float half_width = width * pow(remaining, 0.64) + 0.006;
	float edge_noise = (fbm(vec2(p.x * 10.0 + phase + seed, h * 7.0 - travel * 1.7)) - 0.5) * 0.07;
	float distance_to_edge = abs(p.x - centre - sway) - half_width + edge_noise;
	float sides = 1.0 - smoothstep(-0.018, 0.050, distance_to_edge);
	float root = smoothstep(0.0, 0.035, h);
	float tip = 1.0 - smoothstep(height * 0.72, height, h);
	return sides * root * tip;
}

void vertex() {
	// Camera-facing quad while retaining the per-patch animated scale.
	vec4 right = vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0);
	vec4 up = vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0);
	vec4 forward = vec4(INV_VIEW_MATRIX[2].xyz, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(right, up, forward, MODEL_MATRIX[3]);
}

void fragment() {
	float h = 1.0 - UV.y;
	vec2 p = UV;
	float core = clamp(layer, 0.0, 1.0);
	float spread = mix(1.0, 0.58, core);

	float a = tongue(p, h, 0.29, 0.145 * spread, mix(0.90, 0.76, core), 0.7);
	float b = tongue(p, h, 0.52, 0.180 * spread, mix(1.02, 0.88, core), 2.9);
	float c = tongue(p, h, 0.73, 0.125 * spread, mix(0.79, 0.67, core), 5.1);
	float body = max(a, max(b, c));
	float turbulence = fbm(vec2(p.x * 12.0 + seed * 1.31, h * 8.5 - TIME * 2.8));
	float fine = value_noise(vec2(p.x * 62.0 + seed, h * 37.0 - TIME * 5.4));
	body *= smoothstep(0.24, 0.71, turbulence + (1.0 - h) * 0.07) * (0.65 + fine * 0.55);
	body = clamp(body, 0.0, 1.0);

	// The outer envelope stays orange/violet; only the compact core reaches
	// white. Noise-driven holes keep the tongues translucent and irregular.
	float heat = clamp((1.0 - h) * 0.18 + body * 0.38 + core * 0.52, 0.0, 1.0);
	vec3 colour = mix(vec3(0.24, 0.008, 0.58), vec3(0.95, 0.035, 0.008), smoothstep(0.025, 0.23, h + body * 0.10));
	colour = mix(colour, vec3(1.0, 0.30, 0.012), smoothstep(0.28, 0.53, heat));
	colour = mix(colour, vec3(1.0, 0.79, 0.10), smoothstep(0.52, 0.78, heat));
	colour = mix(colour, vec3(1.0, 0.985, 0.76), smoothstep(0.73, 1.0, heat) * mix(0.52, 1.0, core));
	float violet_root = (1.0 - smoothstep(0.0, 0.16, h)) * (1.0 - core) * 0.82;
	colour = mix(colour, vec3(0.30, 0.008, 0.72), violet_root);

	float alpha = body * mix(0.30, 0.66, core) * ignition * fade;
	// Break up the upper tips rather than leaving a smooth triangular cap.
	alpha *= 1.0 - smoothstep(0.78, 1.0, h) * (0.35 + turbulence * 0.45);
	ALBEDO = colour * mix(1.0, 1.75, core);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
