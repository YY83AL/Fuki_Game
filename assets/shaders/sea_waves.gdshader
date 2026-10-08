shader_type canvas_item;
// Живое море: рябь на воде, бегущие к берегу гребни и прибой, который наползает на песок и откатывается.

const float TOP = 322.0;      // y верхнего края слоя моря в мире
const float HORIZON = 330.0;
const float SHORE = 436.0;

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * sz;
	float yw = TOP + px.y;
	float depth = clamp((yw - HORIZON) / (SHORE - HORIZON), 0.0, 1.0);
	float water = 1.0 - smoothstep(SHORE - 10.0, SHORE + 2.0, yw);

	// рябь: поверхность воды чуть плывёт вбок, дальше от берега — слабее
	float dx = sin(px.y * 0.55 + TIME * 1.3 + px.x * 0.006) * 0.9 + sin(px.y * 0.23 - TIME * 0.9 + px.x * 0.011) * 1.1;
	dx *= depth * water;
	// медленная зыбь: волны чуть поднимаются и опускаются
	float dy = sin(px.x * 0.009 + TIME * 0.7 + px.y * 0.05) * 1.3 * depth * water;

	// прибой: пена и кромка воды наползают на песок и откатываются
	float sh = exp(-pow((yw - SHORE) / 20.0, 2.0));
	float surge = sin(TIME * 0.55 + px.x * 0.0045) * 0.6 + sin(TIME * 0.93 + px.x * 0.012 + 1.0) * 0.4;
	dy += surge * 7.0 * sh;

	vec4 c = texture(TEXTURE, (px + vec2(dx, dy)) / sz);

	// гребни бегут к берегу (перспектива: чем ближе, тем шире)
	float ph = 520.0 / max(yw - HORIZON + 4.0, 1.0);
	float n = 0.5 + 0.5 * sin(px.x * 0.021 + ph * 1.7) * sin(px.x * 0.007 - ph);
	float lines = pow(0.5 + 0.5 * sin(ph + TIME * 1.5 + sin(px.x * 0.013 + ph) * 1.8), 5.0) * n;
	float mask = water * smoothstep(0.02, 0.2, depth);
	c.rgb += vec3(0.40, 0.30, 0.22) * lines * (0.15 + 0.85 * depth) * mask * 0.55;

	// на самой кромке пена то вспыхивает, то гаснет
	float foam = sh * (0.5 + 0.5 * surge) * 0.12;
	c.rgb += vec3(foam);
	COLOR = c;
}
