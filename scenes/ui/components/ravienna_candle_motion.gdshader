shader_type canvas_item;
uniform float phase = 0.0;
varying vec4 vertex_tint;
void vertex() { vertex_tint = COLOR; }
void fragment() {
    vec2 p = UV;
    vec2 shift = vec2(0.0);
    float glow = 0.0;
    vec2 candles[8] = vec2[8](vec2(.067,.079),vec2(.097,.135),vec2(.616,.162),vec2(.633,.161),vec2(.657,.197),vec2(.797,.143),vec2(.937,.272),vec2(.966,.295));
    for (int i=0;i<8;i++) {
        vec2 d = (p-candles[i]) / vec2(.007,.022);
        float mask = exp(-dot(d,d)*1.5);
        float t = phase * 7.0 + float(i)*1.7;
        shift.x += mask * sin(t + d.y*2.6) * .0024;
        shift.y += mask * cos(t*1.28 + d.y) * .0017;
        vec2 g = (p-candles[i]) / vec2(.026,.045);
        glow += exp(-dot(g,g)*1.6) * (.035 + .026*sin(t));
    }
    vec2 d9 = (p-vec2(.988,.307))/vec2(.007,.022);
    shift.x += exp(-dot(d9,d9)*1.5)*sin(phase*7.5+d9.y*2.6)*.0024;
    vec4 base = texture(TEXTURE, clamp(p+shift,vec2(0.0),vec2(1.0)));
    base.rgb += vec3(1.0,.41,.13)*glow;
    COLOR = base * vertex_tint;
}