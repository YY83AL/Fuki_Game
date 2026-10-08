shader_type canvas_item;
// Пост-обработка кадра: капли на объективе, глубина резкости, аберрация,
// свечение, цветокоррекция, бумага, виньетка, зерно, вспышка молнии.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float bloom : hint_range(0.0, 1.0) = 0.0;
uniform float grade : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 1.0) = 0.0;
uniform float dof : hint_range(0.0, 1.0) = 0.0;
uniform float aberr : hint_range(0.0, 1.0) = 0.0;
uniform float aberr_pulse : hint_range(0.0, 2.0) = 0.0;
uniform float drops : hint_range(0.0, 1.0) = 0.0;
uniform float paper : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Смещение от капель на стекле.
vec2 drop_offset(vec2 uv, float t) {
	vec2 g = vec2(9.0, 5.0);
	vec2 sc = uv * g;
	vec2 id = floor(sc);
	vec2 f = fract(sc) - 0.5;
	float h = hash(id);
	if (h < 0.45) return vec2(0.0);
	float life = fract(t * (0.02 + 0.05 * h) + h * 7.0);
	vec2 c = vec2((hash(id + 3.1) - 0.5) * 0.5, (life - 0.5) * 0.7);
	vec2 d = f - c;
	d.y *= 0.8;
	float rad = 0.10 + 0.10 * hash(id + 9.2);
	float m = smoothstep(rad, rad * 0.4, length(d));
	return -d * m * 0.06 * vec2(1.0, 1.78);
}

vec3 sample_ab(vec2 uv, vec2 dir) {
	return vec3(texture(screen_tex, uv + dir).r, texture(screen_tex, uv).g, texture(screen_tex, uv - dir).b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (drops > 0.0) {
		uv += (drop_offset(uv, TIME) + drop_offset(uv * 1.7 + 0.31, TIME * 1.3) * 0.7) * drops;
	}

	// Аберрация: растёт к краям, всплеск при вспышке и ударе.
	vec2 cen = uv - vec2(0.5);
	float ab = (aberr * 0.0018 + aberr_pulse * 0.004) * dot(cen, cen) * 4.0 + aberr_pulse * 0.0015;
	vec2 abdir = normalize(cen + vec2(0.0001)) * ab;

	vec3 c;
	if (dof > 0.0) {
		float k = smoothstep(0.52, 0.08, uv.y) * 0.9 + smoothstep(0.93, 1.0, uv.y) * 0.5;
		k *= dof;
		c = sample_ab(uv, abdir);
		if (k > 0.01) {
			vec3 acc = c;
			for (int i = 0; i < 8; i++) {
				float a = float(i) * 0.785398 + 0.3;
				vec2 o = vec2(cos(a) * 0.5625, sin(a)) * 0.0075 * k;
				acc += sample_ab(uv + o, abdir);
			}
			c = acc / 9.0;
		}
	} else {
		c = sample_ab(uv, abdir);
	}

	if (bloom > 0.0) {
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		for (int i = 0; i < 24; i++) {
			float ring = float(i / 8);
			float a = float(i) * 2.399963 + ring;
			float r = (0.004 + 0.007 * ring) * (1.0 + 0.3 * ring);
			vec2 o = vec2(cos(a) * r * 0.5625, sin(a) * r);
			vec3 s = texture(screen_tex, uv + o).rgb;
			float l = dot(s, vec3(0.299, 0.587, 0.114));
			float k2 = smoothstep(0.70, 1.0, l);
			float w = 1.0 / (1.0 + ring);
			acc += s * k2 * w;
			wsum += w;
		}
		c += (acc / wsum) * 0.9 * bloom;
	}

	if (grade > 0.0) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 shadow_tint = vec3(0.92, 0.98, 1.08);
		vec3 light_tint = vec3(1.08, 1.02, 0.92);
		vec3 g = c * mix(shadow_tint, light_tint, smoothstep(0.15, 0.85, l));
		g = mix(vec3(l), g, 1.08);
		g = (g - 0.5) * 1.06 + 0.5;
		c = mix(c, g, grade);
	}

	if (paper > 0.0) {
		vec2 p = SCREEN_UV * vec2(1280.0, 720.0);
		float fib = vnoise(p * vec2(0.9, 0.12)) * 0.5 + vnoise(p * vec2(0.15, 0.8)) * 0.5;
		float fine = vnoise(p * 0.6);
		float blot = vnoise(p * 0.012);
		float tex = (fib - 0.5) * 0.07 + (fine - 0.5) * 0.045 + (blot - 0.5) * 0.06;
		c = c * (1.0 + tex * paper) + 0.012 * paper;
	}

	if (vignette > 0.0) {
		vec2 d = SCREEN_UV - vec2(0.5);
		d.x *= 1.1;
		float v = smoothstep(0.35, 0.95, length(d));
		c *= 1.0 - v * 0.55 * vignette;
	}

	if (grain > 0.0) {
		// Крупное зерно плёнки: ячейки ~1.5 px, меняется 14 раз в секунду.
		vec2 gp = floor(SCREEN_UV * vec2(853.0, 480.0));
		float n = hash(gp + floor(TIME * 14.0) * 37.0) - 0.5;
		n += (hash(gp * 1.7 + floor(TIME * 14.0) * 11.0) - 0.5) * 0.6;
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c += n * 0.16 * grain * (1.0 - 0.35 * l);
	}

	c += vec3(0.80, 0.86, 1.0) * flash * 0.30;
	COLOR = vec4(c, 1.0);
}
