shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Procedural crossed-ribbon fire. UV.y is zero at the fuel root and one at
// the tip. Geometry is unique per patch; these uniforms animate it independently.
uniform float seed = 0.0;
uniform float ignition = 1.0;
uniform float fade = 1.0;
uniform float height_fade = 1.0;
uniform float intensity = 1.0;
uniform float motion_rate = 1.0;

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
	float amplitude = 0.55;
	for (int octave = 0; octave < 3; octave++) {
		sum += value_noise(p) * amplitude;
		p = p * 2.07 + vec2(13.7, 8.3);
		amplitude *= 0.48;
	}
	return sum;
}

void vertex() {
	float h = clamp(UV.y, 0.0, 1.0);
	float clock = TIME * motion_rate + seed;
	float growing_height = max(0.001, ignition) * height_fade;
	VERTEX.y *= growing_height * (0.94 + 0.10 * sin(clock * 3.1 + h * 5.0));
	float bend = h * h * ignition;
	VERTEX.x += (sin(clock * 2.3 + h * 5.7) + 0.45 * sin(clock * 4.9 + h * 11.0)) * bend * 0.11;
	VERTEX.z += (cos(clock * 1.9 + h * 6.4) + 0.40 * sin(clock * 4.1 + h * 9.0)) * bend * 0.09;
}

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	float side = abs(UV.x - 0.5) * 2.0;
	float clock = TIME * motion_rate;
	float turbulence = fbm(vec2(UV.x * 4.2 + seed * 0.71, h * 5.8 - clock * 1.35));
	float fine = value_noise(vec2(UV.x * 19.0 + seed, h * 21.0 - clock * 3.2));

	// Ragged edges and holes break the ribbons into organic tongues instead of
	// leaving a solid cone, gel surface, or painted ground stain.
	float ragged_side = side + (turbulence - 0.48) * 0.62 + (fine - 0.5) * 0.16;
	float body = 1.0 - smoothstep(0.05, 1.0, ragged_side);
	float root = smoothstep(0.0, 0.09, h);
	float tip_height = 0.65 + turbulence * 0.31;
	float tip = 1.0 - smoothstep(tip_height, 1.0, h);
	float breakup = smoothstep(0.22, 0.66, turbulence + (1.0 - h) * 0.17);
	float shape = body * root * tip * breakup;

	float centre = 1.0 - smoothstep(0.05, 0.72, side + (fine - 0.5) * 0.16);
	float core = centre * (1.0 - smoothstep(0.18, 0.90, h));
	float root_heat = smoothstep(0.015, 0.17, h);
	float heat = clamp(core * 0.80 * root_heat + (1.0 - h) * 0.13 + turbulence * 0.17, 0.0, 1.0);
	vec3 colour = mix(vec3(0.16, 0.002, 0.001), vec3(0.72, 0.022, 0.002), smoothstep(0.02, 0.28, heat));
	colour = mix(colour, vec3(1.0, 0.19, 0.004), smoothstep(0.24, 0.48, heat));
	colour = mix(colour, vec3(1.0, 0.68, 0.035), smoothstep(0.46, 0.72, heat));
	colour = mix(colour, vec3(1.0, 0.98, 0.74), smoothstep(0.72, 0.98, heat));

	float alpha = shape * mix(0.38, 0.74, core) * ignition * fade;
	ALBEDO = colour * intensity * mix(0.82, 1.22, core);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
