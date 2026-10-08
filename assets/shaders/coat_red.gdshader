shader_type canvas_item;
// Красный плащ: подол мягко запаздывает за движением и колышется на ветру.
uniform float drag = 0.0;      // сдвиг подола в пикселях картинки (минус — назад)
uniform float lift = 0.0;      // подол поднимается (падение/прыжок), пиксели
uniform float breeze = 1.0;    // лёгкое колыхание
uniform float y_top = 40.0;    // с какой высоты текстуры плащ начинает гнуться
uniform float y_hem = 275.0;   // низ плаща

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * sz;
	float h = clamp((px.y - y_top) / (y_hem - y_top), 0.0, 1.0);
	float flutter = sin(TIME * 6.0 + px.y * 0.05) * 0.6 + sin(TIME * 9.5 + px.y * 0.03 + 1.3) * 0.4;
	float dx = (drag + breeze * 1.2 * flutter) * h * h;
	float dy = lift * h * h;
	vec2 p = vec2(px.x - dx, px.y + dy);
	vec4 c = texture(TEXTURE, p / sz);
	// за пределами текстуры — прозрачно
	if (p.x < 0.0 || p.y < 0.0 || p.x > sz.x || p.y > sz.y) c = vec4(0.0);
	COLOR = c;
}
