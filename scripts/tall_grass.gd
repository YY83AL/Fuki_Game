class_name TallGrass
extends Node2D
## Высокая трава: каждая травинка — маленькая пружина (угол + скорость).
## Её качают ветер (кнопка 6), лёгкая волна по полю и Фуки, когда проходит сквозь траву.
## Травинки рисуются кодом, картинок не нужно.

@export var count: int = 260
@export var width_px: float = 2100.0          ## На какую ширину рассыпаны травинки
@export var h_min: float = 110.0
@export var h_max: float = 260.0
@export var base_color: Color = Color(0.05, 0.10, 0.09)
@export var tip_color: Color = Color(0.30, 0.42, 0.28)
@export var stiffness: float = 38.0           ## Насколько сильно травинка возвращается вертикально
@export var damping: float = 3.2              ## Чем больше — тем быстрее затухают качания
@export var wind_force: float = 70.0          ## Сила порыва (кнопка 6)
@export var breeze_force: float = 9.0         ## Лёгкая волна без порыва
@export var push_radius: float = 110.0        ## Как далеко от Фуки трава расступается
@export var push_force: float = 260.0
@export var seed_value: int = 7

const SEG := 7
var blades: Array = []   # [x, h, w, angle, vel, hue, phase]
var player: Node2D
var t: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		# Травинки собраны в пучки: плотнее в центре пучка
		var x: float = rng.randf() * width_px
		blades.append([
			x,
			rng.randf_range(h_min, h_max),
			rng.randf_range(5.0, 9.0),
			rng.randf_range(-0.05, 0.05),   # angle
			0.0,                            # vel
			rng.randf(),                    # оттенок
			rng.randf() * TAU,              # фаза
		])
	blades.sort_custom(func(a, b): return a[5] < b[5])   # тёмные сзади, светлые спереди


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	t += delta
	var g: float = Wind.gust * Wind.dir
	var px: float = INF
	if player:
		px = player.global_position.x - global_position.x
	for b in blades:
		var x: float = b[0]
		var h: float = b[1]
		var k: float = stiffness * (160.0 / h)          # длинные травинки мягче
		# ветер: порыв + бегущая волна + мелкое дрожание
		var wave: float = sin(x * 0.006 - t * 1.4) * 0.6 + sin(x * 0.017 - t * 2.3 + b[6]) * 0.4
		var f: float = g * wind_force * (0.7 + 0.3 * sin(t * 3.1 + b[6])) + wave * breeze_force
		# Фуки раздвигает траву
		var dx: float = x - px
		if absf(dx) < push_radius:
			f += signf(dx) * push_force * (1.0 - absf(dx) / push_radius)
		var acc: float = f * (h / 200.0) / 10.0 - k * b[3] - damping * b[4]
		b[4] += acc * delta
		b[3] = clampf(b[3] + b[4] * delta, -1.1, 1.1)
	queue_redraw()


func _draw() -> void:
	for b in blades:
		var h: float = b[1]
		var w: float = b[2]
		var ang: float = b[3]
		var left_pts := PackedVector2Array()
		var right_pts := PackedVector2Array()
		var cols_l := PackedColorArray()
		var cols_r := PackedColorArray()
		var c_base: Color = base_color.lerp(tip_color, b[5] * 0.35)
		var c_tip: Color = tip_color.lerp(base_color, 0.25 - b[5] * 0.25)
		var p := Vector2(b[0], 0.0)
		var a: float = 0.0
		for i in SEG + 1:
			var s: float = float(i) / SEG
			var ww: float = w * (1.0 - s) * (1.0 - s * 0.15)
			# изгиб растёт к кончику
			var dir := Vector2(sin(a), -cos(a))
			var nrm := Vector2(dir.y * -1.0, dir.x) * -1.0
			left_pts.append(p - Vector2(cos(a), sin(a)) * ww * 0.5)
			right_pts.append(p + Vector2(cos(a), sin(a)) * ww * 0.5)
			var col: Color = c_base.lerp(c_tip, s)
			cols_l.append(col)
			cols_r.append(col)
			if i < SEG:
				a = ang * pow((i + 1.0) / SEG, 1.6) + 0.18 * sign(ang) * s * s * absf(ang)
				p += Vector2(sin(a), -cos(a)) * (h / SEG)
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in left_pts.size():
			pts.append(left_pts[i]); cols.append(cols_l[i])
		for i in range(right_pts.size() - 1, -1, -1):
			pts.append(right_pts[i]); cols.append(cols_r[i])
		draw_polygon(pts, cols)
