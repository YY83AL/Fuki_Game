extends Node2D
## Машины едут по дороге вдоль склона: по нижней полосе — в горку, по верхней — вниз.
## Дорога идёт вверх вправо: высота линии земли — как в location_4.gd (g(x) = 1170 − 0.2·x).

const SLOPE := 0.2
const LANES := [
	{"dy": 118.0, "dir": 1.0, "k": 1.0},     # ближе к бордюру, едут в горку (вправо)
	{"dy": 236.0, "dir": -1.0, "k": 1.12},   # дальше от тротуара, едут вниз (влево)
]
const X_MIN := -420.0
const X_MAX := 3020.0

var cars: Array = []
var textures: Array[Texture2D] = []


func _ready() -> void:
	for i in 6:
		textures.append(load("res://assets/backgrounds/location_4/cars/car_%d.png" % i))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for lane in LANES.size():
		var x: float = rng.randf_range(0.0, 600.0)
		while x < X_MAX:
			_spawn(lane, x, rng)
			x += rng.randf_range(520.0, 980.0)


func _spawn(lane: int, x: float, rng: RandomNumberGenerator) -> void:
	var sp := Sprite2D.new()
	sp.texture = textures[rng.randi() % textures.size()]
	sp.centered = false
	sp.offset = -Vector2(110.0, 74.0)       # точка привязки — низ колёс посередине машины
	add_child(sp)
	var l: Dictionary = LANES[lane]
	var dir: float = l["dir"]
	var d := {"sp": sp, "x": x, "lane": lane, "v": rng.randf_range(150.0, 250.0) * dir}
	cars.append(d)
	_place(d)


func _place(d: Dictionary) -> void:
	var sp: Sprite2D = d["sp"]
	var l: Dictionary = LANES[d["lane"]]
	var x: float = d["x"]
	sp.position = Vector2(x, 1170.0 - SLOPE * x + l["dy"])
	sp.rotation = -atan(SLOPE)
	var k: float = l["k"]
	sp.scale = Vector2(k * signf(l["dir"]), k)


func _process(delta: float) -> void:
	for d in cars:
		d["x"] += d["v"] * delta
		var l: Dictionary = LANES[d["lane"]]
		if l["dir"] > 0.0 and d["x"] > X_MAX:
			d["x"] = X_MIN
			(d["sp"] as Sprite2D).texture = textures[randi() % textures.size()]
		elif l["dir"] < 0.0 and d["x"] < X_MIN:
			d["x"] = X_MAX
			(d["sp"] as Sprite2D).texture = textures[randi() % textures.size()]
		_place(d)
