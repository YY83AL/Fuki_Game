class_name IndoorRain
extends Node2D
## Дождь прямо в комнате: капли падают сверху на пол, на полу вспыхивают брызги и остаются мокрые лужицы.
## Капли, которые падают дальше Фуки (за ней), рисуются под ней, ближние — поверх (слой IndoorRainFront).
## Ветер (клавиша 6) сносит капли в сторону. Клавиша 7 — включить/выключить дождь в доме.

@export var enabled: bool = true
@export var drop_count: int = 200                ## Сколько капель падает одновременно вокруг Фуки
@export var spread: float = 850.0                ## Как далеко от Фуки по сторонам идёт дождь
@export var top_y: float = 135.0                 ## Высота, с которой капли начинают падать (под потолком)
@export var floor_top: float = 575.0             ## Дальний край пола (y)
@export var floor_bottom: float = 705.0          ## Ближний край пола (y)
@export var fall_speed: float = 950.0            ## Скорость падения капель
@export var puddle_chance: float = 0.16           ## Шанс, что капля оставит мокрое пятно
@export var max_puddles: int = 150               ## Сколько мокрых пятен может быть на полу сразу
@export var puddle_life: float = 9.0             ## Через сколько секунд пятно высыхает
@export var drop_color: Color = Color(0.82, 0.9, 1.0, 0.55)

class Drop:
	var x: float
	var y: float
	var gy: float
	var vy: float
	var len: float

class Splash:
	var x: float
	var gy: float
	var t: float = 0.0
	var dx: Array[float] = []
	var vz: Array[float] = []

class Puddle:
	var x: float
	var gy: float
	var r: float
	var age: float = 0.0
	var life: float

var drops: Array[Drop] = []
var splashes: Array[Splash] = []
var puddles: Array[Puddle] = []
var player: Player
var front_layer: Node2D
var area_x: Vector2 = Vector2(40.0, 3000.0)


func setup(p_player: Player, p_front: Node2D, world_size: Vector2) -> void:
	player = p_player
	front_layer = p_front
	area_x = Vector2(40.0, world_size.x - 40.0)
	for i in drop_count:
		var d := Drop.new()
		_respawn(d, true)
		drops.append(d)


func _respawn(d: Drop, initial: bool) -> void:
	var cx: float = player.position.x if player else 600.0
	d.x = randf_range(maxf(cx - spread, area_x.x), minf(cx + spread, area_x.y))
	d.gy = randf_range(floor_top, floor_bottom)
	d.vy = fall_speed * randf_range(0.85, 1.1)
	d.len = randf_range(14.0, 26.0) * lerpf(0.8, 1.15, inverse_lerp(floor_top, floor_bottom, d.gy))
	d.y = randf_range(top_y, d.gy) if initial else top_y - randf_range(0.0, 300.0)


func _process(delta: float) -> void:
	if player == null:
		return
	if not enabled:
		if not splashes.is_empty() or not puddles.is_empty():
			splashes.clear()
		_age_puddles(delta)
		queue_redraw()
		if front_layer:
			front_layer.queue_redraw()
		return
	var slide: float = Wind.dir * Wind.gust * 380.0
	for d in drops:
		d.y += d.vy * delta
		d.x += slide * delta
		if d.y >= d.gy:
			_land(d)
			_respawn(d, false)
		elif d.x < area_x.x or d.x > area_x.y:
			_respawn(d, false)
	for s in splashes:
		s.t += delta
	splashes = splashes.filter(func(s: Splash) -> bool: return s.t < 0.4)
	_age_puddles(delta)
	queue_redraw()
	if front_layer:
		front_layer.queue_redraw()


func _age_puddles(delta: float) -> void:
	for p in puddles:
		p.age += delta
	puddles = puddles.filter(func(p: Puddle) -> bool: return p.age < p.life)


func _land(d: Drop) -> void:
	var s := Splash.new()
	s.x = d.x
	s.gy = d.gy
	for k in 3:
		s.dx.append(randf_range(-45.0, 45.0))
		s.vz.append(randf_range(110.0, 220.0))
	splashes.append(s)
	if randf() < puddle_chance and puddles.size() < max_puddles:
		var p := Puddle.new()
		p.x = d.x + randf_range(-6.0, 6.0)
		p.gy = d.gy
		p.r = randf_range(7.0, 20.0)
		p.life = puddle_life * randf_range(0.7, 1.2)
		puddles.append(p)


func _draw() -> void:
	draw_on(self, false)


## front = false: всё, что дальше Фуки (и лужи). front = true: то, что ближе к зрителю, поверх Фуки.
func draw_on(canvas: CanvasItem, front: bool) -> void:
	if player == null:
		return
	var feet: float = player.position.y
	if not front:
		for p in puddles:
			var a: float = clampf(p.age / 0.5, 0.0, 1.0) * (1.0 - smoothstep(0.65, 1.0, p.age / p.life))
			var r: float = p.r * lerpf(0.5, 1.0, clampf(p.age / 0.6, 0.0, 1.0))
			canvas.draw_set_transform(Vector2(p.x, p.gy), 0.0, Vector2(1.0, 0.32))
			canvas.draw_circle(Vector2.ZERO, r, Color(0.62, 0.74, 0.9, 0.16 * a))
			canvas.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(0.92, 0.96, 1.0, 0.32 * a), 1.2)
			canvas.draw_arc(Vector2(0.0, -1.5), r * 0.55, PI * 1.1, PI * 1.8, 8, Color(1, 1, 1, 0.35 * a), 1.0)
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	if not enabled:
		return
	var slide: float = Wind.dir * Wind.gust * 380.0
	for d in drops:
		if (d.gy > feet) != front or d.y < top_y:
			continue
		var tail := Vector2(d.x - slide / d.vy * d.len, d.y - d.len)
		canvas.draw_line(Vector2(d.x, d.y), tail, drop_color, 1.6)
	for s in splashes:
		if (s.gy > feet) != front:
			continue
		var k: float = s.t / 0.4
		var col := Color(0.92, 0.96, 1.0, 0.75 * (1.0 - k))
		canvas.draw_set_transform(Vector2(s.x, s.gy), 0.0, Vector2(1.0, 0.38))
		canvas.draw_arc(Vector2.ZERO, 3.0 + k * 15.0, 0.0, TAU, 14, col, 1.6)
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		for i in 3:
			var t: float = s.t
			var pos := Vector2(s.x + s.dx[i] * t * 2.0, s.gy - (s.vz[i] * t - 700.0 * t * t))
			if pos.y <= s.gy:
				canvas.draw_circle(pos, 1.5, col)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
