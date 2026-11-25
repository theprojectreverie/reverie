shader_type canvas_item;

uniform float wind_amplitude : hint_range(0.0, 4.0) = 1.35;
uniform float wind_speed : hint_range(0.0, 4.0) = 0.85;
uniform float wind_phase : hint_range(0.0, 6.283) = 0.0;

void vertex() {
	float canopy_weight = pow(1.0 - UV.y, 2.0);
	float gust = sin(TIME * wind_speed + UV.y * 2.4 + wind_phase);
	VERTEX.x += gust * wind_amplitude * canopy_weight;
}
