shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float scan = sin(FRAGCOORD.y * 2.2 + TIME * 18.0) * 0.04;
	vec2 centered = UV - vec2(0.5);
	float vig = 1.0 - dot(centered, centered) * 1.15;
	vec3 col = vec3(0.08, 0.85, 0.22) * clamp(vig + scan, 0.25, 1.15);
	COLOR = vec4(col, 0.28 * intensity);
}
