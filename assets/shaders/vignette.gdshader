shader_type canvas_item;
// Свет вокруг Фуки: рядом — как есть, к краям экрана затемнение растёт всё сильнее.
uniform vec2 center_px = vec2(640.0, 360.0);   // где Фуки на экране (в пикселях)
uniform float inner_r : hint_range(0.0, 1500.0) = 230.0;   // до этого радиуса — нормальный свет
uniform float outer_r : hint_range(0.0, 2000.0) = 680.0;   // на этом радиусе затемнение максимальное
uniform float strength : hint_range(0.0, 1.0) = 0.92;
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.10, 1.0);

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * vec2(1280.0, 720.0);
	vec2 d = (px - center_px) * vec2(1.0, 1.25);     // чуть вытянуто по вертикали
	float t = clamp((length(d) - inner_r) / (outer_r - inner_r), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t);
	t = pow(t, 1.3);
	COLOR = vec4(tint.rgb, t * strength);
}
