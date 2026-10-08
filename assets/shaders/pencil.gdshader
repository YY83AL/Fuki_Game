shader_type canvas_item;
// Эффект «закрашено цветным карандашом»: штриховка по ткани, зерно бумаги и тёмный карандашный контур.
// Штрихи привязаны к рисунку ткани (UV), поэтому двигаются и гнутся вместе с плащом.

uniform float strength : hint_range(0.0, 1.0) = 0.85;      // 0 — как раньше, 1 — полностью карандаш
uniform float line_spacing = 11.0;                          // расстояние между штрихами, пикселей рисунка
uniform float hatch_angle = 0.95;                          // наклон штриховки, радианы
uniform float paper_lift = 0.38;                            // насколько светлее «бумага» между штрихами (0..1)
uniform float outline = 0.45;                              // сила тёмного контура по краю
uniform float grain_amount = 0.38;                          // зернистость графита

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float stroke(vec2 p, float ang, float spacing, float seed) {
	vec2 d = vec2(cos(ang), sin(ang));
	vec2 n = vec2(-d.y, d.x);
	float u = dot(p, n) / spacing + (noise(p * 0.045 + seed) - 0.5) * 1.6;   // линия чуть «дрожит»
	float line = abs(fract(u) - 0.5) * 2.0;                                   // 0 в центре штриха, 1 между
	float along = dot(p, d);
	float pressure = 0.35 + 0.65 * noise(vec2(along * 0.035, floor(u) * 3.7 + seed)); // нажим меняется вдоль штриха
	float width = 0.38 + 0.35 * pressure;
	return smoothstep(width, width - 0.22, line) * pressure;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float shade = clamp(1.0 - lum, 0.0, 1.0);

	float h1 = stroke(p, hatch_angle, line_spacing, 0.0);
	float h2 = stroke(p, hatch_angle + 1.15, line_spacing * 1.25, 11.0) * smoothstep(0.30, 0.60, shade);  // перекрёстная штриховка в тёмных местах
	float cover = clamp(h1 * (0.30 + 1.5 * shade) + h2 * 0.8, 0.0, 1.0);

	// зерно бумаги: мелкие крапинки разрывают штрих
	float g = hash(floor(p * 0.9));
	float g2 = noise(p * 0.7);
	float tooth = mix(1.0, smoothstep(0.15, 0.75, g * 0.6 + g2 * 0.6), grain_amount);
	cover *= tooth;

	vec3 paper = mix(c.rgb, vec3(1.0), paper_lift);          // светлая «бумага» цвета ткани
	vec3 pencil = c.rgb * (0.80 - 0.15 * shade);              // цвет карандаша чуть темнее ткани
	vec3 col = mix(paper, pencil, cover);

	// контур: где рядом прозрачно — тёмная карандашная линия
	vec2 px = TEXTURE_PIXEL_SIZE * 2.5;
	float a_min = min(min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
					  min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	float edge = (1.0 - a_min) * c.a;
	float wobble = 0.65 + 0.35 * noise(p * 0.25);
	col = mix(col, c.rgb * 0.45, clamp(edge * outline * wobble * 1.4, 0.0, 0.85));

	COLOR = vec4(mix(c.rgb, col, strength), c.a);
}
