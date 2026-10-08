extends Node2D
## Лужи на полу: отражение Фуки, круги на воде, брызги от шагов.

var player: Node2D
var puddles: Array = []        # {c: Vector2, r: Vector2, poly: PackedVector2Array}
var ripples: Array = []        # {p: Vector2, r: Vector2, age: float}
var splashes: Array = []       # {p: Vector2, v: Vector2, age: float}
var lamp_pos: Array[Vector2] = []
var t := 0.0
var rain_timer := 0.0


func setup(pl: Node2D, world_w: float, y0: float, y1: float, lamps: Array[Vector2], seed_text: String) -> void:
	player = pl
	lamp_pos = lamps
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var n := int(world_w / 380.0)
	for i in n:
		var c := Vector2(rng.randf_range(120.0, world_w - 120.0), rng.randf_range(y0 + 10.0, y1 - 6.0))
		var r := Vector2(rng.randf_range(70.0, 150.0), rng.randf_range(9.0, 15.0))
		puddles.append({"c": c, "r": r, "poly": _ellipse(c, r)})
	var rig = pl.get("rig")
	if rig and rig.has_signal("foot_down"):
		rig.foot_down.connect(_on_foot)


func _ellipse(c: Vector2, r: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * float(i) / 32.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


func _inside(pu: Dictionary, p: Vector2, k: float) -> bool:
	var d: Vector2 = (p - pu["c"]) / pu["r"]
	return d.length_squared() < k


func _on_foot(_side: int, power: float) -> void:
	if not visible:
		return
	var p: Vector2 = player.position
	for pu in puddles:
		if _inside(pu, p, 1.5):
			for k in 2:
				ripples.append({"p": p + Vector2(randf_range(-8, 8), randf_range(-2, 2)), "r": Vector2(10, 3), "age": -0.06 * k})
			for k in int(6 + 8 * power):
				splashes.append({"p": p, "v": Vector2(randf_range(-90, 90), randf_range(-190, -80)), "age": 0.0})
			return


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	rain_timer -= delta
	if rain_timer < 0.0 and puddles.size() > 0:
		rain_timer = randf_range(0.05, 0.18)
		var pu: Dictionary = puddles[randi() % puddles.size()]
		var a := randf() * TAU
		var rr := sqrt(randf())
		ripples.append({"p": pu["c"] + Vector2(cos(a) * pu["r"].x * rr * 0.8, sin(a) * pu["r"].y * rr * 0.8), "r": Vector2(6, 2), "age": 0.0})
	for rp in ripples:
		rp["age"] += delta
	ripples = ripples.filter(func(r): return r["age"] < 0.9)
	for s in splashes:
		s["age"] += delta
		s["v"].y += 700.0 * delta
		s["p"] += s["v"] * delta
	splashes = splashes.filter(func(s): return s["age"] < 0.45)
	queue_redraw()


func _body_shapes() -> Array:
	# Силуэт Фуки в координатах от ног: y вверх отрицательный. [полигон, цвет]
	var red := Color(0.80, 0.16, 0.16, 0.5)
	var white := Color(0.92, 0.90, 0.84, 0.45)
	var head := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		head.append(Vector2(cos(a) * 50.0, -262.0 + sin(a) * 46.0))
	return [
		[PackedVector2Array([Vector2(-24, 0), Vector2(-6, 0), Vector2(-6, -52), Vector2(-24, -52)]), red],
		[PackedVector2Array([Vector2(6, 0), Vector2(24, 0), Vector2(24, -52), Vector2(6, -52)]), red],
		[PackedVector2Array([Vector2(-20, -52), Vector2(-8, -52), Vector2(-8, -96), Vector2(-20, -96)]), white],
		[PackedVector2Array([Vector2(8, -52), Vector2(20, -52), Vector2(20, -96), Vector2(8, -96)]), white],
		[PackedVector2Array([Vector2(-52, -90), Vector2(52, -90), Vector2(34, -212), Vector2(-34, -212)]), red],
		[head, white],
	]


func _draw() -> void:
	var feet: Vector2 = player.position
	var s: float = 1.0
	var body: Node2D = player.get_node_or_null("Body")
	if body:
		s = body.scale.x
	var air: float = float(player.get("air_height"))
	var shapes := _body_shapes()
	for pu in puddles:
		var c: Vector2 = pu["c"]
		var r: Vector2 = pu["r"]
		draw_colored_polygon(pu["poly"], Color(0.45, 0.58, 0.78, 0.30))
		draw_polyline(pu["poly"] + PackedVector2Array([pu["poly"][0]]), Color(0.85, 0.92, 1.0, 0.25), 1.5)
		# Блик от фонарей.
		for lp in lamp_pos:
			if absf(lp.x - c.x) < r.x * 1.1:
				var w: float = r.x * 0.18
				var a: float = 0.55 * (1.0 - absf(lp.x - c.x) / (r.x * 1.1))
				var streak := PackedVector2Array([Vector2(lp.x - w, c.y - r.y * 0.7), Vector2(lp.x + w, c.y - r.y * 0.7), Vector2(lp.x + w * 0.4, c.y + r.y * 0.7), Vector2(lp.x - w * 0.4, c.y + r.y * 0.7)])
				for part in Geometry2D.intersect_polygons(streak, pu["poly"]):
					draw_colored_polygon(part, Color(1.0, 0.85, 0.55, a))
		# Отражение Фуки.
		if absf(feet.x - c.x) < r.x + 60.0 and absf(feet.y - c.y) < 60.0:
			var fade := clampf(1.0 - absf(feet.y - c.y) / 60.0, 0.0, 1.0)
			for sh in shapes:
				var pts := PackedVector2Array()
				for q in sh[0]:
					pts.append(Vector2(feet.x + q.x * s, feet.y + (air - q.y) * s))
				for part in Geometry2D.intersect_polygons(pts, pu["poly"]):
					var col: Color = sh[1]
					col.a *= fade
					draw_colored_polygon(part, col)
	for rp in ripples:
		if rp["age"] < 0.0:
			continue
		var k: float = rp["age"] / 0.9
		var rr: Vector2 = rp["r"] + Vector2(46.0, 13.0) * k
		var pts2 := PackedVector2Array()
		for i in 20:
			var a2 := TAU * float(i) / 20.0
			pts2.append(rp["p"] + Vector2(cos(a2) * rr.x, sin(a2) * rr.y))
		pts2.append(pts2[0])
		draw_polyline(pts2, Color(0.9, 0.95, 1.0, 0.5 * (1.0 - k)), 1.5)
	for sp in splashes:
		draw_circle(sp["p"], 2.2 * (1.0 - sp["age"] / 0.45) + 0.6, Color(0.9, 0.95, 1.0, 0.8))
