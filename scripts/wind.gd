class_name Wind
extends Node
## Порыв ветра (кнопка «Ветер» сверху или клавиша 6).
## Колышет плащ, листья на полу, шерсть на голове и наклоняет дождь за окнами.
## Другие скрипты читают силу ветра из Wind.gust (0 — штиль, 1 — полный порыв) и направление из Wind.dir.

signal gust_started

static var gust: float = 0.0   ## Сила ветра сейчас: 0..1
static var dir: float = -1.0   ## Куда дует: 1 — вправо, -1 — влево (каждый новый порыв меняет сторону)

@export var duration: float = 5.0        ## Сколько длится порыв, секунды
@export var rain_slant: float = 1100.0   ## Насколько ветер наклоняет дождь

var t: float = -1.0
var rain_nodes: Array[CPUParticles2D] = []
var rain_base: Array[Vector2] = []


func setup(rain_root: Node) -> void:
	if rain_root == null:
		return
	for c in rain_root.get_children():
		if c is CPUParticles2D:
			rain_nodes.append(c)
			rain_base.append(c.gravity)


func blow() -> void:
	if t < 0.0:
		dir = -dir
	t = 0.0
	gust_started.emit()


func _process(delta: float) -> void:
	var env: float = 0.0
	if t >= 0.0:
		t += delta
		if t > duration:
			t = -1.0
		else:
			env = smoothstep(0.0, 0.9, t) * (1.0 - smoothstep(duration * 0.55, duration, t))
	var turb: float = 0.6 * sin(t * 9.0) + 0.4 * sin(t * 5.3 + 1.0)
	gust = clampf(env * (0.88 + 0.12 * turb), 0.0, 1.0)
	for i in rain_nodes.size():
		rain_nodes[i].gravity = rain_base[i] + Vector2(dir * gust * rain_slant, 0.0)
