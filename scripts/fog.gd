class_name Fog
extends CanvasLayer
## Туман в комнате (клавиша 8). Плавно появляется и исчезает, плывёт медленными слоями
## и чуть смещается вслед за камерой. Гуще у пола.

@export var max_density: float = 0.85     ## Насколько густой туман (0..1)
@export var fade_seconds: float = 1.8     ## За сколько секунд появляется и исчезает
@export var fog_color: Color = Color(0.86, 0.88, 0.93)

const SHADER := """
shader_type canvas_item;
uniform float density = 0.0;
uniform float cam_x = 0.0;
uniform vec3 fog_color : source_color = vec3(0.86, 0.88, 0.93);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV;
	vec2 p1 = vec2(uv.x * 3.2 + cam_x * 0.0011 + TIME * 0.018, uv.y * 2.0 + TIME * 0.004);
	vec2 p2 = vec2(uv.x * 5.0 + cam_x * 0.0019 - TIME * 0.031 + 7.0, uv.y * 2.8 - TIME * 0.006);
	float n = fbm(p1) * 0.6 + fbm(p2) * 0.4;
	float shape = smoothstep(0.28, 0.78, n);
	float low = mix(0.45, 1.0, smoothstep(0.1, 0.95, uv.y));
	float a = density * (0.10 + 0.72 * shape) * low;
	COLOR = vec4(fog_color, clamp(a, 0.0, 0.9));
}
"""

var rect: ColorRect
var mat: ShaderMaterial
var level: float = 0.0
var target: float = 0.0
var tween: Tween
var camera_source: Node2D   ## У кого брать положение камеры (Фуки)


func _ready() -> void:
	layer = 3
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.visible = false
	add_child(rect)


func set_enabled(on: bool) -> void:
	target = max_density if on else 0.0
	if on:
		rect.visible = true
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "level", target, fade_seconds)
	if not on:
		tween.tween_callback(func(): rect.visible = false)


func _process(_delta: float) -> void:
	if not rect.visible:
		return
	mat.set_shader_parameter("density", level)
	mat.set_shader_parameter("fog_color", Vector3(fog_color.r, fog_color.g, fog_color.b))
	if camera_source:
		mat.set_shader_parameter("cam_x", camera_source.position.x)
