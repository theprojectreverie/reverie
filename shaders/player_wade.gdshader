shader_type canvas_item;

// Keep the original authored sprite and animation. Sink the drawn frame,
// then occlude its lower half at the actual ground-plane waterline.
uniform float sink_pixels = 0.0;
uniform float waterline_strength = 1.0;
varying float waterline_y;
varying float waterline_x;

void vertex() {
	VERTEX.y += sink_pixels;
	waterline_y = VERTEX.y;
	waterline_x = VERTEX.x;
}

void fragment() {
	float wave = sin(waterline_x * 0.13 + TIME * 3.0) * 0.9 * waterline_strength;
	float line_distance = wave - waterline_y;
	if (line_distance < 0.0) {
		discard;
	}
	float rim = (1.0 - smoothstep(0.0, 2.4, line_distance)) * waterline_strength;
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * vec3(0.65, 1.05, 1.16), rim * 0.65);
}
