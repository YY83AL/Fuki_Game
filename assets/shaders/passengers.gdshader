shader_type canvas_item;
// Едва заметное оживление пассажиров: покачивание на ходу поезда, дыхание, раскачивание петель-поручней.
// box[i] = (x0, x1, верх, низ) в пикселях картинки; prm[i] = (амплитуда px, частота, фаза, тип)
// тип 0 — стоит (качается от ног), 1 — сидит, 2 — петля (подвешена сверху)
uniform vec4 box[32];
uniform vec4 prm[32];
uniform int count = 0;
uniform float shake = 1.0;   // общая сила (0 — всё замерло)

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * sz;
	vec2 d = vec2(0.0);
	for (int i = 0; i < 32; i++) {
		if (i >= count) break;
		vec4 b = box[i];
		vec4 p = prm[i];
		float wx = smoothstep(b.x - 3.0, b.x + 3.0, px.x) * (1.0 - smoothstep(b.y - 3.0, b.y + 3.0, px.x));
		float wy = smoothstep(b.z - 3.0, b.z + 1.0, px.y) * (1.0 - smoothstep(b.w, b.w + 3.0, px.y));
		float w = wx * wy;
		float h;
		if (p.w > 1.5) {
			h = clamp((px.y - b.z) / max(b.w - b.z, 1.0), 0.0, 1.0);   // 0 наверху (крепление) → 1 внизу
		} else {
			h = clamp((b.w - px.y) / max(b.w - b.z, 1.0), 0.0, 1.0);   // 0 у ног → 1 у головы
		}
		float s = sin(TIME * p.y + p.z) + 0.45 * sin(TIME * p.y * 2.3 + p.z * 1.7);
		float dx = p.x * s * h * h;
		float br = sin(TIME * 1.7 + p.z * 3.0);
		float dy = (p.w < 0.5 ? 0.45 : 0.3) * br * h * (1.0 - h) * 4.0;
		if (p.w > 1.5) dy = 0.0;
		d += w * vec2(dx, dy) * shake;
	}
	COLOR = texture(TEXTURE, UV - d / sz);
}
