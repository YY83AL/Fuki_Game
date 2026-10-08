shader_type canvas_item;
render_mode blend_add;
// Солнечная дорожка на воде: блики мерцают.

void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * sz;
	vec4 c = texture(TEXTURE, UV);
	float f = 0.55 + 0.45 * sin(TIME * 2.3 + px.x * 0.11 + px.y * 0.37) * sin(TIME * 1.7 - px.x * 0.05 + px.y * 0.23);
	float slow = 0.85 + 0.15 * sin(TIME * 0.6 + px.x * 0.01);
	COLOR = vec4(c.rgb * f * slow, 1.0);
}
