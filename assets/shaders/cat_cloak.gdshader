shader_type canvas_item;
// Плащ кота колышется на ветру: желтоватые пиксели ниже плеч и выше сапог сдвигаются волной.
uniform float wind = 0.0;       // сила ветра (Wind.gust) со знаком направления относительно взгляда
uniform float breeze = 0.35;    // лёгкое колыхание, когда ветра нет
uniform float amount = 11.0;    // размах в пикселях кадра
uniform float y_top = 120.0;    // с какой высоты кадра начинается плащ
uniform float y_hem = 250.0;    // где кончается плащ (ниже — сапоги)

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * sz;
	float w = smoothstep(y_top, y_hem - 40.0, px.y) * (1.0 - smoothstep(y_hem - 10.0, y_hem + 15.0, px.y));
	float flutter = sin(TIME * 7.0 + px.y * 0.09) * 0.5 + sin(TIME * 11.0 + px.y * 0.05 + 1.7) * 0.3;
	float dx = amount * w * (wind * (0.8 + 0.4 * flutter) + breeze * 0.12 * flutter);
	vec4 c = texture(TEXTURE, vec2(UV.x - dx / sz.x, UV.y));
	COLOR = c;
}
