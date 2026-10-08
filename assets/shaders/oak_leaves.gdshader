shader_type canvas_item;
// Крона дуба: верх качается сильнее низа, листва мелко трепещет. wind — порыв со знаком направления.
uniform float wind = 0.0;
uniform float breeze = 0.5;
uniform float amount = 26.0;

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * sz;
	float h = 1.0 - UV.y;                                   // 0 внизу кроны, 1 вверху
	float sway = (wind * 1.0 + breeze * 0.08 * sin(TIME * 0.9)) * pow(h, 1.3) * amount;
	float flutter = sin(TIME * 5.0 + px.x * 0.045 + px.y * 0.06) + 0.6 * sin(TIME * 8.3 + px.x * 0.09 - px.y * 0.05);
	float fl = (0.5 + 2.8 * abs(wind)) * flutter;
	vec2 d = vec2(sway + fl * 0.6, fl * 0.35);
	COLOR = texture(TEXTURE, UV - d / sz);
}
