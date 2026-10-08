class_name Leaves
extends Node2D
## Осенние листья на полу. Когда Фуки проходит мимо (или приземляется после прыжка),
## листья взлетают, разлетаются в стороны и медленно опускаются обратно на пол.
##
## Листья, которые лежат дальше от зрителя, чем Фуки, рисуются за ней (этот узел),
## а те, что ближе, рисуются поверх неё (узел LeavesFront).

@export var leaf_count: int = 220                          ## Сколько листьев на полу
@export var disturb_radius: Vector2 = Vector2(85.0, 48.0)  ## Зона вокруг Фуки, где листья взлетают (по x и по глубине)
@export var gravity: float = 600.0                         ## Как быстро листья падают вниз
@export var max_fall_speed: float = 140.0                  ## Предельная скорость падения (листья планируют)
@export var floor_top: float = 566.0                       ## Верх области пола, где лежат листья (y)
@export var floor_height: float = 140.0                    ## Высота области пола

const SHAPES: int = 3
const COLORS: int = 5
const FLAT: float = 0.42   ## Насколько сплющен лист, лежащий на полу (вид сверху под углом)

class Leaf:
	var x: float
	var gy: float            # положение на полу (глубина), экранный y лежащего листа
	var z: float = 0.0       # высота над полом
	var vx: float = 0.0
	var vgy: float = 0.0
	var vz: float = 0.0
	var angle: float = 0.0
	var spin: float = 0.0
	var phase: float = 0.0
	var size: float = 28.0
	var tex: Texture2D
	var airborne: bool = false

var leaves: Array[Leaf] = []
var textures: Array[Texture2D] = []
var player: Player
var front_layer: Node2D
var time: float = 0.0
var was_airborne: bool = false
var area: Rect2


func setup(p_player: Player, p_front_layer: Node2D, world_size: Vector2) -> void:
	player = p_player
	front_layer = p_front_layer
	area = Rect2(40.0, floor_top, world_size.x - 80.0, floor_height)
	_load_textures()
	_scatter()


func _load_textures() -> void:
	for s in SHAPES:
		for c in COLORS:
			textures.append(load("res://assets/leaves/leaf_%d_%d.png" % [s, c]) as Texture2D)


func _scatter() -> void:
	# Часть листьев лежит кучками, часть разбросана поодиночке.
	var clumps: Array[Vector2] = []
	for i in 28:
		clumps.append(Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y + 20.0, area.end.y - 20.0)))
	var color_pool: Array[int] = [0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4]
	for i in leaf_count:
		var leaf := Leaf.new()
		if randf() < 0.4:
			var c: Vector2 = clumps.pick_random()
			leaf.x = clampf(c.x + randfn(0.0, 60.0), area.position.x, area.end.x)
			leaf.gy = clampf(c.y + randfn(0.0, 18.0), area.position.y, area.end.y)
		else:
			leaf.x = randf_range(area.position.x, area.end.x)
			leaf.gy = randf_range(area.position.y, area.end.y)
		leaf.angle = randf() * TAU
		leaf.phase = randf() * TAU
		leaf.size = randf_range(22.0, 34.0)
		leaf.tex = textures[randi() % SHAPES * COLORS + color_pool.pick_random()]
		leaves.append(leaf)


func _process(delta: float) -> void:
	if player == null:
		return
	time += delta
	_disturb()
	_wind(delta)
	for leaf in leaves:
		if leaf.airborne:
			_update_air(leaf, delta)
	queue_redraw()
	if front_layer != null:
		front_layer.queue_redraw()


func _wind(delta: float) -> void:
	var g: float = Wind.gust
	if g < 0.02:
		return
	for leaf in leaves:
		if leaf.airborne:
			leaf.vx = clampf(leaf.vx + Wind.dir * g * 420.0 * delta, -480.0, 480.0)
			leaf.vz += g * 540.0 * delta * (0.6 + 0.4 * sin(time * 6.0 + leaf.phase))
			leaf.spin = clampf(leaf.spin + Wind.dir * g * 6.0 * delta, -12.0, 12.0)
		elif randf() < g * 2.0 * delta:
			leaf.vz = randf_range(120.0, 260.0)
			leaf.vx = Wind.dir * randf_range(80.0, 240.0) * g
			leaf.vgy = randf_range(-20.0, 20.0)
			leaf.spin = randf_range(-8.0, 8.0)
			leaf.airborne = true


func _disturb() -> void:
	var on_ground: bool = player.air_height <= 0.0
	var landed: bool = was_airborne and on_ground
	was_airborne = not on_ground
	var moving: bool = on_ground and player.velocity.length() > 40.0
	if not moving and not landed:
		return
	var radius: Vector2 = disturb_radius * (1.8 if landed else 1.0)
	var px: float = player.position.x
	var py: float = player.position.y
	for leaf in leaves:
		if leaf.airborne:
			continue
		var dx: float = (leaf.x - px) / radius.x
		var dy: float = (leaf.gy - py) / radius.y
		if dx * dx + dy * dy < 1.0:
			_launch(leaf, dx, dy, landed)


func _launch(leaf: Leaf, dx: float, dy: float, strong: bool) -> void:
	var push: float = 1.0 if dx >= 0.0 else -1.0
	if absf(dx) < 0.05:
		push = 1.0 if randf() < 0.5 else -1.0
	var power: float = 1.5 if strong else 1.0
	leaf.vz = randf_range(250.0, 420.0) * power
	leaf.vx = push * randf_range(60.0, 200.0) * power + player.velocity.x * randf_range(0.2, 0.5)
	leaf.vgy = signf(dy) * randf_range(10.0, 60.0) * power + randf_range(-20.0, 20.0)
	leaf.spin = randf_range(-9.0, 9.0)
	leaf.airborne = true


func _update_air(leaf: Leaf, delta: float) -> void:
	leaf.vz = maxf(leaf.vz - gravity * delta, -max_fall_speed)
	# Покачивание из стороны в сторону, как у настоящего падающего листа.
	leaf.x += (leaf.vx + sin(time * 4.0 + leaf.phase) * 40.0) * delta
	leaf.gy += leaf.vgy * delta
	leaf.z += leaf.vz * delta
	leaf.vx = move_toward(leaf.vx, 0.0, 90.0 * delta)
	leaf.vgy = move_toward(leaf.vgy, 0.0, 60.0 * delta)
	leaf.angle += leaf.spin * delta
	leaf.x = clampf(leaf.x, area.position.x, area.end.x)
	leaf.gy = clampf(leaf.gy, area.position.y, area.end.y)
	if leaf.z <= 0.0 and leaf.vz < 0.0:
		leaf.z = 0.0
		leaf.vz = 0.0
		leaf.vx = 0.0
		leaf.vgy = 0.0
		leaf.spin = 0.0
		leaf.airborne = false


func _draw() -> void:
	draw_on(self, false)


## Рисует листья на переданном слое. front = false: листья позади Фуки, true: перед ней.
func draw_on(canvas: CanvasItem, front: bool) -> void:
	if player == null:
		return
	var feet_y: float = player.position.y
	for leaf in leaves:
		if (leaf.gy > feet_y) != front:
			continue
		var tilt: float = FLAT
		if leaf.airborne:
			# В воздухе лист кувыркается: то разворачивается к зрителю, то сплющивается.
			tilt = lerpf(FLAT, 1.0, clampf(leaf.z / 50.0, 0.0, 1.0))
			tilt *= 0.6 + 0.4 * absf(cos(time * 5.0 + leaf.phase))
			tilt = maxf(tilt, 0.2)
			if leaf.z > 2.0:
				canvas.draw_set_transform(Vector2(leaf.x, leaf.gy), 0.0, Vector2(1.0, 0.4))
				canvas.draw_circle(Vector2.ZERO, leaf.size * 0.3, Color(0.0, 0.0, 0.0, 0.14))
		var xf: Transform2D = Transform2D(leaf.angle, Vector2.ZERO).scaled(Vector2(1.0, tilt))
		xf.origin = Vector2(leaf.x, leaf.gy - leaf.z)
		canvas.draw_set_transform_matrix(xf)
		var half: float = leaf.size * 0.5
		canvas.draw_texture_rect(leaf.tex, Rect2(-half, -half, leaf.size, leaf.size), false)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
