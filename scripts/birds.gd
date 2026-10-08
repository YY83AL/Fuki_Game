extends Node2D
## Белые чайки в небе: машут крыльями, иногда планируют, медленно летят вдоль неба.
## Лежит внутри слоя неба, поэтому вместе с ним сдвигается при ходьбе (параллакс).

const SKY_W := 1344.0
const COLOR := Color(0.99, 0.97, 0.96)
const SHADE := Color(0.93, 0.80, 0.82)     # чуть розовый низ крыла от зари

var birds: Array = []
var time: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	# [x, y, скорость, размер, направление]
	var setup: Array = [
		[220.0, 175.0, 26.0, 1.05, 1.0], [262.0, 150.0, 25.0, 0.8, 1.0], [300.0, 192.0, 27.0, 0.7, 1.0],
		[700.0, 120.0, -20.0, 0.9, -1.0], [1010.0, 215.0, 31.0, 1.2, 1.0], [1120.0, 140.0, -24.0, 0.65, -1.0],
		[520.0, 240.0, 18.0, 0.6, 1.0],
	]
	for s in setup:
		birds.append({
			"x": s[0], "y": s[1], "v": s[2], "k": s[3], "dir": s[4],
			"phase": rng.randf() * TAU, "freq": rng.randf_range(4.2, 5.8),
			"glide": rng.randf() * TAU, "bob": rng.randf() * TAU,
		})


func _process(delta: float) -> void:
	time += delta
	for b in birds:
		b["x"] += b["v"] * delta
		if b["x"] > SKY_W + 40.0:
			b["x"] = -40.0
		elif b["x"] < -40.0:
			b["x"] = SKY_W + 40.0
	queue_redraw()


func _wing(root: Vector2, side: float, lift: float, lag: float, k: float) -> void:
	# крыло из двух звеньев: плечо→локоть→кончик; кончик отстаёт от взмаха
	var a1: float = lift * 0.75 - 0.12
	var a2: float = lag * 0.9 + 0.1
	var elbow: Vector2 = root + Vector2(side * cos(a1) * 11.0 * k, -sin(a1) * 11.0 * k)
	var tip: Vector2 = elbow + Vector2(side * cos(a2) * 12.0 * k, -sin(a2) * 12.0 * k)
	var pts: Array[Vector2] = [root, elbow, tip]
	var w: Array[float] = [2.4 * k, 2.1 * k, 0.3 * k]
	var up := PackedVector2Array()
	var down := PackedVector2Array()
	for i in 3:
		var dirv: Vector2 = (pts[min(i + 1, 2)] - pts[max(i - 1, 0)]).normalized()
		var n := Vector2(-dirv.y, dirv.x)
		up.append(pts[i] + n * w[i])
		down.append(pts[i] - n * w[i] * 0.8)
	down.reverse()
	up.append_array(down)
	draw_colored_polygon(up, COLOR)
	# лёгкая тень на внутренней стороне крыла
	draw_line(root + Vector2(0, 0.6 * k), elbow + Vector2(0, 0.8 * k), SHADE, 1.0 * k)


func _draw() -> void:
	for b in birds:
		var k: float = b["k"]
		var amp: float = smoothstep(0.1, 0.6, 0.5 + 0.5 * sin(time * 0.35 + b["glide"]))
		var ph: float = time * b["freq"] + b["phase"]
		var lift: float = sin(ph) * amp
		var lag: float = sin(ph - 0.9) * amp
		var bob: float = -cos(ph) * 1.4 * amp * k + sin(time * 0.5 + b["bob"]) * 3.0
		var p: Vector2 = Vector2(b["x"], b["y"] + bob)
		var dir: float = b["dir"]
		# тело, голова, хвост
		draw_set_transform(p, 0.0, Vector2(1, 1))
		draw_colored_polygon(_ellipse(Vector2(0, 0), 5.2 * k, 2.1 * k), COLOR)
		draw_colored_polygon(_ellipse(Vector2(dir * 5.4 * k, -0.6 * k), 1.9 * k, 1.6 * k, 10), COLOR)
		draw_colored_polygon(PackedVector2Array([Vector2(-dir * 4.5 * k, -0.6 * k), Vector2(-dir * 9.0 * k, 0.4 * k), Vector2(-dir * 4.5 * k, 1.4 * k)]), COLOR)
		# клюв
		draw_line(Vector2(dir * 6.8 * k, -0.6 * k), Vector2(dir * 8.6 * k, -0.2 * k), Color(1.0, 0.82, 0.55), 0.9 * k)
		# два крыла
		_wing(Vector2(-0.6 * k, -0.8 * k), -1.0, lift, lag, k)
		_wing(Vector2(0.6 * k, -0.8 * k), 1.0, lift, lag, k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 1))


func _ellipse(c: Vector2, rx: float, ry: float, n: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
