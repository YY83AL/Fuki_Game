extends Node2D
## Мотыльки у фонариков; иногда один подлетает к Фуки.

var player: Node2D
var lamp_pos: Array[Vector2] = []
var moths: Array = []
var t := 0.0


func setup(pl: Node2D, lamps: Array[Vector2]) -> void:
	player = pl
	lamp_pos = lamps
	z_index = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in lamps.size():
		for k in 3:
			moths.append({
				"lamp": i, "a": rng.randf() * TAU, "r": rng.randf_range(26.0, 70.0),
				"w": rng.randf_range(1.6, 3.2) * (1.0 if rng.randf() < 0.5 else -1.0),
				"ph": rng.randf() * TAU, "pos": lamps[i], "curious": (k == 0),
			})


func _process(delta: float) -> void:
	t += delta
	var head: Vector2 = player.position + Vector2(0, -300)
	for m in moths:
		m["a"] += m["w"] * delta
		var center: Vector2 = lamp_pos[m["lamp"]]
		var rr: float = m["r"]
		if m["curious"] and absf(player.position.x - center.x) < 300.0:
			center = head + Vector2(0, 10)
			rr = 70.0
		var target: Vector2 = center + Vector2(cos(m["a"]) * rr, sin(m["a"]) * rr * 0.6) + Vector2(sin(t * 3.1 + m["ph"]) * 8.0, cos(t * 2.3 + m["ph"]) * 6.0)
		m["pos"] = m["pos"].lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	for m in moths:
		var flap: float = 0.35 + 0.65 * absf(sin(t * 28.0 + m["ph"]))
		var p: Vector2 = m["pos"]
		var wing := Color(0.97, 0.93, 0.80, 0.92)
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(-9.0 * flap, -5), p + Vector2(-8.0 * flap, 3)]), wing)
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(9.0 * flap, -5), p + Vector2(8.0 * flap, 3)]), wing)
		draw_circle(p, 1.8, Color(0.25, 0.2, 0.16, 1.0))
