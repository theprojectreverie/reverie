shader_type canvas_item;

// Motion is confined to the outer hair in the existing authored illustration.
// The face, horns, arms, torso, legs, and entire canvas remain fixed.
uniform float phase = 0.0;
uniform float motion_strength : hint_range(0.0, 1.0) = 0.0;

float region(vec2 uv, vec2 center, vec2 radius) {
	return 1.0 - smoothstep(0.18, 1.0, length((uv - center) / radius));
}

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec2 uv = UV;
	float left_hair = region(uv, vec2(0.087, 0.70), vec2(0.083, 0.30));
	float upper_hair = region(uv, vec2(0.466, 0.35), vec2(0.105, 0.22));
	float trailing_hair = region(uv, vec2(0.34, 0.86), vec2(0.06, 0.11));
	vec2 offset = vec2(
		left_hair * sin(phase + uv.y * 5.0) * 0.0024 + upper_hair * sin(phase * 0.8 + uv.x * 9.0) * 0.0018,
		left_hair * sin(phase + uv.x * 9.0 + 0.8) * 0.005 + upper_hair * sin(phase * 0.8 + uv.x * 12.0) * 0.004 + trailing_hair * sin(phase * 0.9 + uv.x * 7.0) * 0.003
	);
	COLOR = texture(TEXTURE, uv + offset * motion_strength) * vertex_tint;
}
