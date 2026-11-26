shader_type canvas_item;
render_mode unshaded;
uniform vec2 rect_size = vec2(1.0);
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
 vec2 p = local_position / max(rect_size, vec2(1.0)) * 2.0 - 1.0;
 COLOR.a *= 1.0 - smoothstep(0.95, 1.0, length(p));
}
