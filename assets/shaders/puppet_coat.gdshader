shader_type canvas_item;
// Подол пальто красной кошки: сдвигается назад от скорости, колышется на ветру, взлетает в прыжке.
// Все величины — в пикселях листа (текстура вдвое больше листа).
uniform float sway = 0.0;      // сдвиг подола (вперёд +, назад −)
uniform float wind = 0.0;      // сила ветра со знаком относительно взгляда
uniform float rise = 0.0;      // подол приподнимается (прыжок)
uniform float flutter_amt = 3.0;

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	float h = clamp((UV.y - 0.30) / 0.70, 0.0, 1.0);
	float w = h * h;
	float f = sin(TIME * 8.0 + UV.y * 9.0) * 0.6 + sin(TIME * 13.0 + UV.y * 5.0 + 1.3) * 0.4;
	float dx = (sway + wind * 9.0 + f * flutter_amt * (0.2 + abs(wind) + abs(sway) * 0.08)) * 2.0 * w;
	float dy = rise * 2.0 * w;
	COLOR = texture(TEXTURE, vec2(UV.x - dx / sz.x, UV.y + dy / sz.y));
}
