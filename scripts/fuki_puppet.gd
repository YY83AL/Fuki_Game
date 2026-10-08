class_name FukiPuppet
extends Node2D

signal foot_down(side: int, power: float)
## Красная кошка — кукла из частей (вид 3/4, для ходьбы влево и вправо; влево — зеркально).
## Подключается к Player как и другие куклы: animate(delta, скорость, направление, в_воздухе).
## Части лежат в assets/characters/red_cat/*.png (нарисованы лицом вправо). Земля — точка между сапогами.
## Движение считается кодом: ходьба и бег — шаг с подъёмом ноги, раскачка рук, пританцовывание корпуса,
## подол пальто тянется назад; в прыжке — присед, взлёт с поднятыми руками, полёт, приземление.

@export var frame_scale: float = 0.38           ## Размер кошки (1 — как на листе, 660 px высотой)
@export var walk_hz: float = 1.7                ## Полных шагов (левая+правая нога) в секунду при ходьбе
@export var run_hz: float = 2.7
@export var run_threshold: float = 1.25
@export var crouch_seconds: float = 0.05
@export var jump_up_seconds: float = 0.20
@export var land_seconds: float = 0.12
@export var turn_seconds: float = 0.10
@export var cloak_wind: bool = true
@export var clothes: bool = true               ## false — кот без плаща и рукавов (голое тело)
@export var boots_on: bool = true               ## false — босиком

const OX := 1515.0      # точка земли на листе (между сапогами)
const OY := 784.0
const LEG_LEN := 178.0  # от бедра до земли
const THIGH := 84.0     # бедро: от таза до колена (верх сапога)
const SHIN := 66.0      # голень: от колена до щиколотки
const FOOT_H := 28.0    # щиколотка над землёй при плоской стопе
const LEG_REACH := 149.5
const KNEE_Y := 84.0
const CH := Vector2(1515.0, 520.0)      # талия: ось поворота груди
const WAIST := Vector2(0.0, -86.0)
const HIP := Vector2(1515.0, 606.0)
# имя: [файл, x, y] — левый верхний угол части на листе
const PART_POS := {
	"leg_L": Vector2(1455.33, 591.67), "leg_R": Vector2(1507.0, 588.67),
	"boot_L": Vector2(1451.33, 672.33), "boot_R": Vector2(1505.33, 670.0),
	"boot_shaft_L": Vector2(1451.33, 672.33), "boot_shaft_R": Vector2(1505.33, 670.0),
	"boot_foot_L": Vector2(1451.33, 672.33), "boot_foot_R": Vector2(1505.33, 670.0),
	"body": Vector2(1364.0, 340.0), "torso_nude": Vector2(1440.0, 330.0), "base_body": Vector2(1364.0, 340.0),
	"arm_L": Vector2(1357.0, 352.33), "paw_L": Vector2(1357.0, 352.33), "sleeveonly_L": Vector2(1369.5, 357.0),
	"arm_R": Vector2(1539.67, 352.0), "paw_R": Vector2(1539.67, 352.0), "sleeveonly_R": Vector2(1543.5, 357.0), "sleeve_L": Vector2(1357.0, 352.33), "sleeve_R": Vector2(1539.67, 352.0),
	"head": Vector2(1367.0, 120.67), "eye_L": Vector2(1422.33, 239.0), "eye_R": Vector2(1548.33, 239.67),
}
const HIP_L := Vector2(1486.0, 606.0)
const HIP_R := Vector2(1536.0, 606.0)
const ANKLE_L := Vector2(1486.0, 690.0)
const ANKLE_R := Vector2(1536.0, 690.0)
const SH_L := Vector2(1466.0, 372.0)
const SH_R := Vector2(1545.0, 372.0)
const NECK := Vector2(1510.0, 352.0)
const EYE_C_L := Vector2(1467.0, 280.0)
const EYE_C_R := Vector2(1579.0, 278.0)

var flip: Node2D
var torso: Node2D
var chest: Node2D
var chest_rot: float = 0.0
var nude_skin: Polygon2D
var nude_rest: PackedVector2Array
var nude_w: PackedFloat32Array
var arm_skins: Array[Polygon2D] = []
var arm_rest: Array = []
var arm_w: Array = []
var legs: Array[Node2D] = []
var boots: Array[Node2D] = []
var feet: Array[Node2D] = []
var sleeves: Array[Node2D] = []
var sleeve_cloths: Array = []
var forearms: Array[Node2D] = []
var head: Node2D
var eyes: Array[Node2D] = []
var body_sprite: Sprite2D
var mat: ShaderMaterial

var cloths: Array = []

var facing: float = 1.0
var t: float = 0.0
var phase: float = 0.0
var skins: Array[Polygon2D] = []
var skin_rest: Array = []
var skin_w1: Array = []
var skin_w2: Array = []
var anticipate: float = 0.0              # 0..1: игрок готовится к прыжку (присед до отрыва)
@export var stepped: bool = false                # «на двойках»
var stepped_fps: float = 12.0
var step_acc: float = 0.0
var stance_prev: Array[bool] = [false, false]
var last_gp: Vector2 = Vector2.ZERO
var rig_vel: Vector2 = Vector2.ZERO
var rig_acc: Vector2 = Vector2.ZERO
var lean_v: float = 0.0
var lean_s: float = 0.0
var idle_t: float = 4.0
var idle_kind: int = 0
var idle_left: float = 0.0
var idle_age: float = 0.0
var running: bool = false
var dust_t: float = 0.0
var dust: CPUParticles2D
var turn_left: float = 0.0
var turn_from: float = 1.0
var air_time: float = 0.0
var was_in_air: bool = false
var land_left: float = 0.0
var blink_in: float = 2.5
var blink_t: float = -1.0
# сглаженные «размахи» походки
var stride: float = 0.0
var lift: float = 0.0
var arm: float = 0.0
var turn_cool: float = 0.0
var prev_sr: float = 0.0
var accel: float = 0.0
var lean: float = 0.0
var bob: float = 0.0
var drop: float = 0.0
var kick: float = 0.0
var sway: float = 0.0
var head_lag: float = 0.0
# позы воздуха
var y_off: float = 0.0
var squash: float = 1.0
var arm_out: float = 0.0
var arm_fwd: float = 0.0
var leg_apart: float = 0.0
var leg_tuck: float = 0.0
var boot_drop: float = 0.0
var rise: float = 0.0


func _spr(file: String, pos: Vector2, origin: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load("res://assets/characters/red_cat/%s.png" % file)
	s.centered = false
	s.scale = Vector2(0.5, 0.5)
	s.position = PART_POS[file] - origin
	return s


func _loc(file: String, offset: Vector2) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/characters/red_cat/%s.png" % file)
	sp.centered = false
	sp.scale = Vector2(0.5, 0.5)
	sp.position = offset
	return sp


func _make_skin(leg: Node2D, tex_name: String) -> void:
	var x0: float = -60.0
	var y0: float = -40.0
	var cell: float = 7.0
	var cols: int = int(140.0 / cell)
	var rows: int = int(240.0 / cell)
	var poly := Polygon2D.new()
	poly.name = "LegSkin"
	poly.texture = load("res://assets/characters/red_cat/%s.png" % tex_name)
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var w1 := PackedFloat32Array()
	var w2 := PackedFloat32Array()
	for r in rows + 1:
		for c in cols + 1:
			var p := Vector2(x0 + c * cell, y0 + r * cell)
			verts.append(p)
			uvs.append(Vector2((p.x - x0) * 2.0, (p.y - y0) * 2.0))
			w1.append(smoothstep(KNEE_Y - 10.0, KNEE_Y + 10.0, p.y))
			w2.append(smoothstep(KNEE_Y + SHIN - 10.0, KNEE_Y + SHIN + 12.0, p.y))
	var tris: Array = []
	for r in rows:
		for c in cols:
			var i: int = r * (cols + 1) + c
			tris.append(PackedInt32Array([i, i + 1, i + cols + 2]))
			tris.append(PackedInt32Array([i, i + cols + 2, i + cols + 1]))
	poly.polygon = verts
	poly.uv = uvs
	poly.polygons = tris
	leg.add_child(poly)
	skins.append(poly)
	skin_rest.append(verts)
	skin_w1.append(w1)
	skin_w2.append(w2)


func _skin(i: int) -> void:
	var a1: float = boots[i].rotation
	var a2: float = a1 + feet[i].rotation
	var k := Vector2(0.0, KNEE_Y)
	var an: Vector2 = k + Vector2(0.0, SHIN).rotated(a1)
	var piv2 := Vector2(0.0, KNEE_Y + SHIN)
	var rest: PackedVector2Array = skin_rest[i]
	var w1: PackedFloat32Array = skin_w1[i]
	var w2: PackedFloat32Array = skin_w2[i]
	var out := PackedVector2Array()
	out.resize(rest.size())
	var c1: float = cos(a1)
	var s1: float = sin(a1)
	var c2: float = cos(a2)
	var s2: float = sin(a2)
	for j in rest.size():
		var p: Vector2 = rest[j]
		var a: float = w1[j]
		if a <= 0.0:
			out[j] = p
			continue
		var d1: Vector2 = p - k
		var p1 := Vector2(k.x + d1.x * c1 - d1.y * s1, k.y + d1.x * s1 + d1.y * c1)
		var b: float = w2[j]
		if b > 0.0:
			var d2: Vector2 = p - piv2
			var p2 := Vector2(an.x + d2.x * c2 - d2.y * s2, an.y + d2.x * s2 + d2.y * c2)
			p1 = p1.lerp(p2, b)
		out[j] = p.lerp(p1, a)
	skins[i].polygon = out


func _make_nude_skin() -> void:
	var cell: float = 8.0
	var x0: float = -75.0
	var y0: float = -190.0
	var cols: int = int(150.0 / cell) + 1
	var rows: int = int(300.0 / cell) + 1
	var cw: float = 150.0 / cols
	var rh: float = 300.0 / rows
	nude_skin = Polygon2D.new()
	nude_skin.name = "NudeSkin"
	nude_skin.texture = load("res://assets/characters/red_cat/torso_nude.png")
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	nude_w = PackedFloat32Array()
	for r in rows + 1:
		for c in cols + 1:
			var p := Vector2(x0 + c * cw, y0 + r * rh)
			verts.append(p)
			uvs.append(Vector2((p.x - x0) * 2.0, (p.y - y0) * 2.0))
			nude_w.append(smoothstep(10.0, 80.0, p.y))
	var tris: Array = []
	for r in rows:
		for c in cols:
			var i: int = r * (cols + 1) + c
			tris.append(PackedInt32Array([i, i + 1, i + cols + 2]))
			tris.append(PackedInt32Array([i, i + cols + 2, i + cols + 1]))
	nude_skin.polygon = verts
	nude_skin.uv = uvs
	nude_skin.polygons = tris
	nude_rest = verts
	chest.add_child(nude_skin)


func _nude_skin() -> void:
	var a: float = -chest.rotation
	var ca: float = cos(a)
	var sa: float = sin(a)
	var out := PackedVector2Array()
	out.resize(nude_rest.size())
	for j in nude_rest.size():
		var p: Vector2 = nude_rest[j]
		var w: float = nude_w[j]
		if w <= 0.0:
			out[j] = p
		else:
			out[j] = p.lerp(Vector2(p.x * ca - p.y * sa, p.x * sa + p.y * ca), w)
	nude_skin.polygon = out


func _make_arm_skin(sl: Node2D) -> void:
	var poly := Polygon2D.new()
	poly.name = "ArmSkin"
	poly.texture = load("res://assets/characters/red_cat/armskin_bare.png")
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var w := PackedFloat32Array()
	var cell: float = 7.0
	var cols: int = 17
	var rows: int = 40
	for r in rows + 1:
		for c in cols + 1:
			var p := Vector2(-60.0 + c * 120.0 / cols, -40.0 + r * 280.0 / rows)
			verts.append(p)
			uvs.append(Vector2((p.x + 60.0) * 2.0, (p.y + 40.0) * 2.0))
			w.append(smoothstep(80.0 - 11.0, 80.0 + 11.0, p.y))
	var tris: Array = []
	for r in rows:
		for c in cols:
			var i: int = r * (cols + 1) + c
			tris.append(PackedInt32Array([i, i + 1, i + cols + 2]))
			tris.append(PackedInt32Array([i, i + cols + 2, i + cols + 1]))
	poly.polygon = verts
	poly.uv = uvs
	poly.polygons = tris
	sl.add_child(poly)
	arm_skins.append(poly)
	arm_rest.append(verts)
	arm_w.append(w)


func _arm_skin(i: int) -> void:
	var a: float = forearms[i].rotation
	var ca: float = cos(a)
	var sa: float = sin(a)
	var rest: PackedVector2Array = arm_rest[i]
	var w: PackedFloat32Array = arm_w[i]
	var out := PackedVector2Array()
	out.resize(rest.size())
	for j in rest.size():
		var p: Vector2 = rest[j]
		var k: float = w[j]
		if k <= 0.0:
			out[j] = p
		else:
			var d: Vector2 = p - Vector2(0.0, 80.0)
			var q := Vector2(d.x * ca - d.y * sa, 80.0 + d.x * sa + d.y * ca)
			out[j] = p.lerp(q, k)
	arm_skins[i].polygon = out


func _eye_base_x(e: Node2D) -> float:
	if not e.has_meta("bx"):
		e.set_meta("bx", e.position.x)
	return e.get_meta("bx")


func _node(parent: Node, name: String, pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


func _ready() -> void:
	flip = _node(self, "Flip", Vector2.ZERO)
	var g := Vector2(OX, OY)
	# ноги и сапоги (сзади)
	var hips: Array[Vector2] = [HIP_L, HIP_R]
	var ankles: Array[Vector2] = [ANKLE_L, ANKLE_R]
	var ln: Array[String] = ["leg_L", "leg_R"]
	var bn: Array[String] = ["boot_L", "boot_R"]
	for i in 2:
		var leg := _node(flip, ln[i], hips[i] - g)
		var tex_name: String = ("legskin_boots_" + ("L" if i == 0 else "R")) if boots_on else "legskin_bare"
		_make_skin(leg, tex_name)
		legs.append(leg)
		var boot := _node(leg, bn[i], ankles[i] - hips[i])
		var foot := _node(boot, "Foot", Vector2(0.0, SHIN))             # стопа — отдельное звено на щиколотке
		var ankle_sheet := Vector2(ankles[i].x, ankles[i].y + SHIN)
		feet.append(foot)
		boots.append(boot)
	# корпус с бедра
	torso = _node(flip, "Torso", HIP - g)
	chest = _node(torso, "Chest", WAIST)
	_make_nude_skin()                                             # голое тело под одеждой
	body_sprite = _spr("body", Vector2.ZERO, CH)
	chest.add_child(body_sprite)
	body_sprite.visible = clothes and not cloak_wind
	if clothes and cloak_wind:
		var coat := Cloth.new()
		coat.setup(chest, "body", PART_POS["body"] - CH, Rect2(70.0, 33.0, 472.0, 524.0), 10, 12, 0.30, 0.12, 0.007, 90.0)
		cloths.append(coat)
	var shs: Array[Vector2] = [SH_L, SH_R]
	var sn: Array[String] = ["sleeve_L", "sleeve_R"]
	var sides: Array[String] = ["L", "R"]
	var srect: Array[Rect2] = [Rect2(0.0, 0.0, 220.0, 370.0), Rect2(0.0, 0.0, 184.0, 349.0)]
	for i in 2:
		var sl := _node(chest, sn[i], shs[i] - CH)
		if not clothes:                                                 # голая рука: плечо, локоть, лапа
			_make_arm_skin(sl)
			var fore := _node(sl, "Forearm", Vector2(0.0, 80.0))
			forearms.append(fore)
			sleeves.append(sl)
			continue
		var paw_sprite := _spr("paw_L" if cloak_wind else "paw_" + sides[i], Vector2.ZERO, shs[0] if cloak_wind else shs[i])     # лапа: сидит в манжете рукава
		if cloak_wind:
			var sc := Cloth.new()                                       # рукав — отдельная ткань
			sc.setup(sl, "sleeveonly_L", PART_POS["sleeveonly_L"] - SH_L, srect[0], 6, 10, 0.14, 0.16, 0.07, 40.0, Vector2.ONE, Vector2.ZERO if i == 0 else Vector2(6.25, 0.0), i == 1)
			sc.clamp_node = chest
			sc.clamp_rect = Rect2(-146.0, -400.0, 268.0 if i == 0 else 520.0, 1000.0)
			var pawn := Node2D.new()
			pawn.name = "PawHolder"
			sl.add_child(pawn)
			sl.move_child(pawn, 0)                                      # под тканью рукава
			if i == 1:                                                  # дальняя рука — точное зеркало ближней
				var cuff_l := Vector2(-(sc.cuff_rest.x - 6.25), sc.cuff_rest.y)
				var dd: Vector2 = paw_sprite.position - cuff_l
				paw_sprite.position = Vector2(-dd.x, dd.y)
				paw_sprite.scale = Vector2(-0.5, 0.5)
			else:
				paw_sprite.position -= sc.cuff_rest
			pawn.add_child(paw_sprite)
			pawn.position = sc.cuff_rest
			sc.paw = pawn
			sc.elbow_row = 5
			sc.elbow_pt = sc._row_avg(sc.rest, 5)
			sleeve_cloths.append(sc)
			cloths.append(sc)
		else:
			sl.add_child(paw_sprite)
			sl.add_child(_spr("sleeveonly_" + sides[i], Vector2.ZERO, shs[i]))
		sleeves.append(sl)
	head = _node(chest, "Head", NECK - CH)
	head.add_child(_spr("head", Vector2.ZERO, NECK))
	var ec: Array[Vector2] = [EYE_C_L, EYE_C_R]
	var en: Array[String] = ["eye_L", "eye_R"]
	for i in 2:
		var e := _node(head, en[i], ec[i] - NECK)
		var sp := _spr(en[i], Vector2.ZERO, ec[i])
		e.add_child(sp)
		eyes.append(e)
	scale = Vector2(frame_scale, frame_scale)
	dust = CPUParticles2D.new()
	dust.name = "Dust"
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = 12
	dust.lifetime = 0.55
	dust.local_coords = false
	dust.spread = 35.0
	dust.gravity = Vector2(0.0, -40.0)
	dust.initial_velocity_min = 60.0
	dust.initial_velocity_max = 190.0
	dust.damping_min = 120.0
	dust.damping_max = 200.0
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.1
	var gt := GradientTexture2D.new()
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(0.96, 0.93, 0.86, 0.9))
	gr.set_color(1, Color(0.96, 0.93, 0.86, 0.0))
	gt.gradient = gr
	dust.texture = gt
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.85))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	dust.color_ramp = ramp
	dust.z_index = -1
	add_child(dust)


func _puff(n: int, power: float) -> void:
	if dust == null:
		return
	dust.position = Vector2(-22.0 * facing, 0.0)
	dust.direction = Vector2(-facing, -0.35)
	dust.amount = maxi(n, 1)
	dust.initial_velocity_max = 190.0 * power
	dust.restart()
	dust.emitting = true


func _sm(cur: float, target: float, k: float, delta: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * delta))


func animate(delta: float, speed_ratio: float, face: float, in_air: bool) -> void:
	if stepped:
		step_acc += delta
		if step_acc < 1.0 / stepped_fps:
			return
		delta = step_acc
		step_acc = 0.0
	# движение куклы в мире — нужно ткани (инерция и сопротивление воздуха)
	var gp: Vector2 = global_position
	if last_gp != Vector2.ZERO and delta > 0.0:
		var v_new: Vector2 = (gp - last_gp) / delta
		rig_acc = rig_acc.lerp((v_new - rig_vel) / delta, 0.35)
		rig_vel = rig_vel.lerp(v_new, 0.5)
	last_gp = gp
	t += delta
	# --- направление и быстрый разворот ---
	if face != 0.0 and face != facing:
		if not in_air and turn_seconds > 0.0:
			turn_from = facing
			turn_left = turn_seconds
		facing = face
	var sx: float = facing
	if turn_left > 0.0 and not in_air:
		turn_left -= delta
		var k: float = 1.0 - clampf(turn_left / turn_seconds, 0.0, 1.0)
		var v: float = lerpf(turn_from, facing, k)
		sx = signf(v) * maxf(absf(v), 0.35)
	flip.scale.x = sx
	# --- состояние ---
	var t_stride: float = 0.0
	var t_lift: float = 0.0
	var t_arm: float = 0.0
	var t_lean: float = 0.0
	var t_bob: float = 0.0
	var t_drop: float = 0.0
	var t_kick: float = 0.0
	var t_sway: float = 0.0
	var t_yoff: float = 0.0
	var t_squash: float = 1.0
	var t_out: float = 0.0
	var t_fwd: float = 0.0
	var t_apart: float = 0.0
	var t_tuck: float = 0.0
	var t_bdrop: float = 0.0
	var t_rise: float = 0.0
	var fast: float = 8.0
	if in_air:
		if not was_in_air:
			air_time = 0.0
		air_time += delta
		land_left = maxf(land_seconds, 0.26)
		if air_time < crouch_seconds:                         # присед перед прыжком
			t_yoff = 30.0
			t_squash = 0.92
			t_fwd = -0.45                                     # руки назад
			t_lean = 0.04
		elif air_time < crouch_seconds + jump_up_seconds:     # взлёт: руки вверх, ноги поджаты
			t_yoff = -8.0
			t_squash = 1.07
			t_fwd = 0.05
			t_out = 0.22
			t_apart = 0.0
			t_tuck = 0.5
			t_bdrop = 0.45
			t_rise = 12.0
			t_sway = -6.0
		elif air_time < crouch_seconds + jump_up_seconds + 0.35:  # верхняя точка: группировка, колени к груди
			t_out = 0.30
			t_fwd = -0.15
			t_apart = 0.10
			t_tuck = 1.0
			t_bdrop = 0.55
			t_yoff = -4.0
			t_squash = 0.97
			t_rise = 22.0
		else:                                                 # падение: ноги вытянуты вниз, руки в стороны
			t_out = 0.34
			t_fwd = 0.03
			t_apart = 0.22
			t_tuck = 0.08
			t_bdrop = 0.12
			t_squash = 1.05
			t_rise = 26.0
			t_sway = -10.0 * minf(speed_ratio, 1.5)
		t_lean = 0.07 if speed_ratio > 0.3 else 0.0
		fast = 12.0
	elif anticipate > 0.0 and land_left <= 0.0:                # готовится к прыжку: присед, руки назад
		t_yoff = 28.0 * anticipate
		t_squash = 1.0 - 0.09 * anticipate
		t_fwd = -0.45 * anticipate
		t_lean = 0.05 * anticipate
		t_out = 0.1 * anticipate
		fast = 16.0
		if speed_ratio > 0.05:
			t_stride = 20.0
			phase += TAU * walk_hz * 0.5 * delta
	elif land_left > 0.0:                                     # приземление
		land_left -= delta
		var lf: float = land_left / 0.26
		if lf > 0.6:                                          # удар
			t_yoff = 26.0
			t_squash = 0.89
			t_fwd = -0.1
			fast = 22.0
		else:                                                 # плавное выпрямление
			t_yoff = 6.0
			t_squash = 0.98
			fast = 9.0
		t_out = 0.5
		t_rise = -4.0
	elif speed_ratio > 0.05:
		if running:
			running = speed_ratio > run_threshold * 0.92
		else:
			running = speed_ratio > run_threshold
		if running:
			phase += TAU * run_hz * clampf(speed_ratio / 1.75, 0.7, 1.2) * delta
			t_stride = 62.0
			t_lift = 52.0
			t_arm = 0.60
			t_lean = 0.24
			t_bob = -17.0
			t_drop = 10.0
			t_kick = 0.8
			t_sway = -14.0
		else:
			var s: float = clampf(speed_ratio, 0.45, 1.2)
			phase += TAU * walk_hz * s * delta
			t_stride = 56.0 * s
			t_lift = 14.0 * s
			t_arm = 0.46 * s
			t_lean = 0.045
			t_bob = 4.0
			t_sway = -5.0 * s
	else:
		running = false
	if was_in_air and not in_air and air_time > 0.12:
		_puff(10, 1.0)
	was_in_air = in_air
	# --- разгон и торможение: наклон по ускорению ---
	var acc_raw: float = (speed_ratio - prev_sr) / maxf(delta, 0.0001)
	prev_sr = speed_ratio
	accel = _sm(accel, clampf(acc_raw, -12.0, 12.0), 10.0, delta)
	if not in_air:
		t_lean += clampf(accel * 0.012, -0.07, 0.10)
	# --- сглаживание размахов ---
	stride = _sm(stride, t_stride, 9.0, delta)
	lift = _sm(lift, t_lift, 9.0, delta)
	arm = _sm(arm, t_arm, 8.0, delta)
	lean = _sm(lean, t_lean, 8.0, delta)
	bob = _sm(bob, t_bob, 8.0, delta)
	drop = _sm(drop, t_drop, 8.0, delta)
	kick = _sm(kick, t_kick, 8.0, delta)
	sway = _sm(sway, t_sway, 5.0, delta)
	y_off = _sm(y_off, t_yoff, fast, delta)
	squash = _sm(squash, t_squash, fast, delta)
	arm_out = _sm(arm_out, t_out, fast, delta)
	arm_fwd = _sm(arm_fwd, t_fwd, fast, delta)
	leg_apart = _sm(leg_apart, t_apart, fast, delta)
	leg_tuck = _sm(leg_tuck, t_tuck, fast, delta)
	boot_drop = _sm(boot_drop, t_bdrop, fast, delta)
	rise = _sm(rise, t_rise, 9.0, delta)
	# --- ноги: бедро + голень + стопа, обратная кинематика, перекат пятка → носок ---
	var act: float = clampf(stride / 20.0, 0.0, 1.0)
	var ty_pre: float = y_off + drop + bob * absf(sin(phase))
	var cross: float = 0.6 * act
	var air_w: float = clampf((leg_tuck + leg_apart) * 4.0, 0.0, 1.0)
	var anks: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var fang: Array[float] = [0.0, 0.0]
	var ups: Array[float] = [0.0, 0.0]
	var pelvis: float = 0.0
	for i in 2:
		var ph: float = phase + PI * i
		var sph: float = fposmod(ph + PI * 0.5, TAU) - PI * 0.5      # (-90°, 270°)
		var in_stance: bool = sph >= PI * 0.5
		if in_stance and not stance_prev[i] and act > 0.3 and not in_air:
			foot_down.emit(i, clampf(stride / 60.0, 0.3, 1.0))
			if running:
				_puff(3, 0.6)
		stance_prev[i] = in_stance
		var dxl: float
		var f: float
		var up: float = 0.0
		if sph < PI * 0.5:                                            # переноска вперёд
			var tt: float = (sph + PI * 0.5) / PI
			dxl = stride * sin(sph)
			up = lift * cos(sph)
			f = lerpf(0.55, -0.22, smoothstep(0.0, 0.4, tt))
			f = lerpf(f, -0.16, smoothstep(0.6, 1.0, tt))
		else:                                                         # опора: стопа едет назад по земле
			var tau: float = (sph - PI * 0.5) / PI
			dxl = stride * (1.0 - 2.0 * tau)
			f = lerpf(-0.16, 0.0, smoothstep(0.0, 0.18, tau))
			f = lerpf(f, 0.55 + (0.2 if running else 0.0), smoothstep(0.55, 1.0, tau))
		f *= act
		dxl += (25.0 if i == 0 else -25.0) * cross
		f = lerpf(f, 0.25 + boot_drop * (1.0 if i == 1 else 0.7), air_w)
		var xc: float = -16.0 * clampf(-f / 0.25, 0.0, 1.0) + 38.0 * clampf(f / 0.5, 0.0, 1.0)
		var rx: float = xc * cos(f) - FOOT_H * sin(f)
		var ry: float = xc * sin(f) + FOOT_H * cos(f)
		anks[i] = Vector2(dxl - rx, -ry - up)                         # щиколотка: x и «над землёй»
		fang[i] = f
		ups[i] = up
		if not in_air:
			var need: float = LEG_LEN + anks[i].y - ty_pre - sqrt(maxf(0.0, LEG_REACH * LEG_REACH - anks[i].x * anks[i].x))
			pelvis = maxf(pelvis, need)
	pelvis = clampf(pelvis, 0.0, 40.0)
	var ty: float = ty_pre + pelvis
	for i in 2:
		var leg: Node2D = legs[i]
		var base: Vector2 = (HIP_L if i == 0 else HIP_R) - Vector2(OX, OY)
		var side: float = -1.0 if i == 0 else 1.0
		var air_rot: float = (side * leg_apart + (-0.18 if i == 0 else 0.30) * leg_tuck) * -1.0
		var tgt := Vector2(anks[i].x, LEG_LEN + anks[i].y - ty - leg_tuck * 62.0)
		var ca: float = cos(air_rot)
		var sa: float = sin(air_rot)
		tgt = Vector2(tgt.x * ca - tgt.y * sa, tgt.x * sa + tgt.y * ca)
		var d: float = clampf(tgt.length(), 20.0, LEG_REACH)
		var ang_t: float = atan2(-tgt.x, tgt.y)
		var cosa: float = clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0)
		var th: float = ang_t - acos(cosa)                          # колено смотрит вперёд
		var kn := Vector2(-sin(th), cos(th)) * THIGH
		var tpos: Vector2 = tgt.normalized() * d
		var sh: float = atan2(-(tpos.x - kn.x), tpos.y - kn.y)
		leg.rotation = th
		leg.position = base + Vector2(0.0, ty)
		boots[i].rotation = sh - th
		feet[i].rotation = fang[i] - sh
		_skin(i)
	# порядок отрисовки: переносимая вперёд нога сверху опорной
	var front: int = 0 if cos(phase) > 0.0 else 1
	if act > 0.2 and legs[front].get_index() < legs[1 - front].get_index():
		legs[front].get_parent().move_child(legs[front], legs[1 - front].get_index())
	# --- корпус ---
	torso.position = HIP - Vector2(OX, OY) + Vector2(0.0, ty)
	var spine_t: float = lean + 0.012 * sin(t * 0.55) * (1.0 - act)
	torso.rotation = 0.5 * spine_t - 0.03 * sin(phase) * act                  # таз
	var chest_target: float = 0.5 * spine_t + 0.05 * sin(phase) * act + accel * 0.004
	lean_v += ((chest_target - chest_rot) * 220.0 - lean_v * 15.0) * delta           # пружина: небольшой «перелёт» при остановке
	chest_rot += lean_v * delta
	chest.rotation = chest_rot
	torso.scale = Vector2(1.0 / sqrt(squash), squash)
	chest.scale.x = 1.0 + 0.035 * cos(phase) * act
	chest.position = WAIST + Vector2(0.0, 0.0)
	torso.position.x += 3.0 * sin(t * 0.55) * (1.0 - act)
	# дыхание в покое
	var calm: float = 1.0 - act
	torso.scale.y *= 1.0 + 0.012 * sin(t * 2.2) * calm
	# --- руки ---
	var sw: float = arm * sin(phase)
	if clothes:
		# рукава болтаются на руках: рука качается мало, остальное делает ткань; наружу за плащ не выходят
		var cl_l: float = sw + 0.6 * (arm_out - arm_fwd) - 0.08 * act + 0.025 * sin(t * 1.6) * calm
		var cl_r: float = -sw + 0.6 * (-arm_out - arm_fwd) + 0.08 * act - 0.025 * sin(t * 1.6 + 1.0) * calm
		sleeves[0].rotation = clampf(cl_l, -0.30, 0.15)
		sleeves[1].rotation = clampf(cl_r - 0.05, -0.22, 0.20)
		if sleeve_cloths.size() == 2:
			for j in 2:
				var rj: float = sleeves[j].rotation
				var eb: float = 0.10 * act + (0.85 if running else 0.14) * act * clampf(-rj / 0.3, 0.0, 1.0) + 0.05 * calm
				sleeve_cloths[j].elbow_ang = _sm(sleeve_cloths[j].elbow_ang, -eb, 14.0, delta)
	else:
		# голые руки: размах шире, локоть сгибается вперёд на махе вперёд
		var swn: float = sw * (2.0 if not running else 1.6)
		var rl: float = swn * (1.0 if swn < 0.0 else 0.55) + 0.10 + arm_out - arm_fwd + 0.03 * sin(t * 1.6) * calm
		var rr: float = -swn * (1.0 if swn > 0.0 else 0.55) - 0.10 - arm_out - arm_fwd - 0.03 * sin(t * 1.6 + 1.0) * calm
		sleeves[0].rotation = rl
		sleeves[1].rotation = rr
		var base_f: float = 0.12 + (1.6 if running else 0.4) * act
		forearms[0].rotation = -(base_f + 0.7 * maxf(0.0, -rl) * act)
		forearms[1].rotation = -(base_f + 0.7 * maxf(0.0, -rr) * act)
		_arm_skin(0)
		_arm_skin(1)
	# дальняя от камеры рука (кукла зеркалится целиком, поэтому всегда одна и та же) спрятана за телом и плащом
	var far_arm: Node2D = sleeves[1]
	var near_arm: Node2D = sleeves[0]
	if far_arm.get_index() != 0:
		chest.move_child(far_arm, 0)
	if near_arm.get_index() < 3:
		chest.move_child(near_arm, chest.get_child_count() - 2)
	if not clothes:
		_nude_skin()
	# --- голова: отстаёт от корпуса, держит горизонт ---
	head_lag = _sm(head_lag, ty, 10.0, delta)
	head.position = NECK - CH + Vector2(0.0, (head_lag - ty) * 0.9)
	# --- покой: иногда оглядывается, пожимает плечами ---
	var idle_head: float = 0.0
	var idle_shr: float = 0.0
	var idle_eye: float = 0.0
	if act < 0.05 and not in_air and land_left <= 0.0 and anticipate <= 0.0:
		idle_t -= delta
		if idle_t <= 0.0 and idle_left <= 0.0:
			idle_kind = randi() % 3
			idle_left = 1.6
			idle_age = 0.0
			idle_t = randf_range(4.0, 9.0)
		if idle_left > 0.0:
			idle_left -= delta
			idle_age += delta
			var e: float = sin(clampf(idle_age / 1.6, 0.0, 1.0) * PI)
			match idle_kind:
				0:
					idle_head = 0.10 * e
					idle_eye = 5.0 * e
				1:
					idle_head = -0.07 * e
					idle_eye = -4.0 * e
				2:
					idle_shr = 5.0 * e
					idle_head = 0.03 * e
	else:
		idle_left = 0.0
	chest.position = WAIST + Vector2(0.0, -idle_shr)
	for e2 in eyes:
		e2.position.x = _eye_base_x(e2) + idle_eye
	head.rotation = -0.55 * (torso.rotation + chest.rotation) + idle_head + 0.018 * sin(phase * 2.0 + 1.0) * act + 0.02 * sin(t * 0.9) * calm
	# --- глаза: моргание ---
	blink_in -= delta
	if blink_in <= 0.0 and blink_t < 0.0:
		blink_t = 0.0
		blink_in = randf_range(2.2, 5.0)
	var lid: float = 1.0
	if blink_t >= 0.0:
		blink_t += delta
		var b: float = blink_t / 0.14
		lid = 1.0 - sin(clampf(b, 0.0, 1.0) * PI) * 0.92
		if b >= 1.0:
			blink_t = -1.0
	for e in eyes:
		e.scale.y = lid
	# --- подол: настоящая симуляция ткани ---
	var wind_f: float = Wind.gust * Wind.dir * facing
	var inv_x: Transform2D = global_transform.affine_inverse()
	var vl_loc: Vector2 = inv_x.basis_xform(rig_vel)
	var al_loc: Vector2 = inv_x.basis_xform(rig_acc)
	if al_loc.length() > 7000.0:
		al_loc = al_loc.normalized() * 7000.0
	var tw: float = clampf(turn_left / maxf(turn_seconds, 0.001), 0.0, 1.0)
	turn_cool = maxf(turn_cool - delta, 0.0)
	if turn_left > 0.0:
		turn_cool = 0.25
	for c in cloths:
		c.turning = clampf(turn_cool / 0.25, 0.0, 1.0)
		c.step(self, delta, wind_f, vl_loc, al_loc)


## Лоскут ткани: сетка частиц (Верле). Верхние строки держатся на родителе, нижние свободны.
class Cloth extends RefCounted:
	const GRAVITY := 2400.0
	const WIND := 2600.0
	var parent: Node2D
	var poly: Polygon2D
	var cols: int = 0
	var rows: int = 0
	var rest: PackedVector2Array
	var pos: PackedVector2Array
	var prev: PackedVector2Array
	var k: PackedFloat32Array
	var pinned: PackedByteArray
	var len_h: float = 0.0
	var len_v: float = 0.0
	var inited: bool = false
	var time: float = 0.0
	var reach: float = 90.0
	var clamp_node: Node2D
	var clamp_rect: Rect2
	var loose: float = 1.0
	var turning: float = 0.0
	var elbow_row: int = -1
	var elbow_pt: Vector2 = Vector2.ZERO
	var elbow_ang: float = 0.0
	var paw: Node2D
	var cuff_rest: Vector2
	var axis_rest: Vector2

	func setup(par: Node2D, tex_name: String, origin: Vector2, tex: Rect2, c: int, r: int, pin: float, k_top: float, k_low: float, max_dist: float, size_mul: Vector2 = Vector2.ONE, shift: Vector2 = Vector2.ZERO, mirror: bool = false) -> void:
		parent = par
		cols = c
		rows = r
		reach = max_dist
		poly = Polygon2D.new()
		poly.name = "Cloth_" + tex_name
		poly.texture = load("res://assets/characters/red_cat/%s.png" % tex_name)
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for ri in rows + 1:
			for ci in cols + 1:
				var uv := Vector2(tex.position.x + tex.size.x * ci / cols, tex.position.y + tex.size.y * ri / rows)
				uvs.append(uv)
				var rp: Vector2 = origin + uv * 0.5
				rest.append(rp)
				verts.append(rp)
				var fr: float = float(ri) / rows
				k.append(lerpf(k_top, k_low, smoothstep(pin, 1.0, fr)))
				pinned.append(1 if fr <= pin + 0.001 else 0)
		var tris: Array = []
		for ri in rows:
			for ci in cols:
				var i: int = ri * (cols + 1) + ci
				tris.append(PackedInt32Array([i, i + 1, i + cols + 2]))
				tris.append(PackedInt32Array([i, i + cols + 2, i + cols + 1]))
		if size_mul != Vector2.ONE or shift != Vector2.ZERO or mirror:
			var pv := Vector2.ZERO
			for ci in cols + 1:
				pv += rest[ci]
			pv /= float(cols + 1)
			for i in rest.size():
				if mirror:
					rest[i].x = -rest[i].x
				rest[i] = pv + (rest[i] - pv) * size_mul + shift
				verts[i] = rest[i]
		poly.polygon = verts
		poly.uv = uvs
		poly.polygons = tris
		par.add_child(poly)
		len_h = (rest[1] - rest[0]).length()
		len_v = (rest[cols + 1] - rest[0]).length()
		pos.resize(rest.size())
		prev.resize(rest.size())
		cuff_rest = _row_avg(rest, rows)
		axis_rest = cuff_rest - _row_avg(rest, 1)

	func _row_avg(arr: PackedVector2Array, row: int) -> Vector2:
		var sum := Vector2.ZERO
		for ci in cols + 1:
			sum += arr[row * (cols + 1) + ci]
		return sum / float(cols + 1)

	func update_paw() -> void:
		if paw == null:
			return
		var v: PackedVector2Array = poly.polygon
		var cuff: Vector2 = _row_avg(v, rows)
		var axis: Vector2 = cuff - _row_avg(v, 1)
		paw.position = cuff
		paw.rotation = axis.angle() - axis_rest.angle()

	func step(rig: Node2D, delta: float, wind_f: float, vl: Vector2 = Vector2.ZERO, al: Vector2 = Vector2.ZERO) -> void:
		var n: int = rest.size()
		var xf: Transform2D = rig.global_transform
		var to_rig: Transform2D = xf.affine_inverse() * parent.global_transform
		var targets := PackedVector2Array()
		targets.resize(n)
		for i in n:
			var rp: Vector2 = rest[i]
			if elbow_row >= 0:
				var w: float = smoothstep(float(elbow_row) - 1.0, float(elbow_row) + 1.5, float(i / (cols + 1)))
				rp = elbow_pt + (rp - elbow_pt).rotated(elbow_ang * w)
			targets[i] = to_rig * rp
		if not inited:
			for i in n:
				pos[i] = targets[i]
				prev[i] = targets[i]
			inited = true
		var steps: int = clampi(int(ceil(delta / 0.0083)), 1, 6)
		var dt: float = delta / steps
		for st in steps:
			time += dt
			for i in n:
				if pinned[i] == 1:
					prev[i] = pos[i]
					pos[i] = targets[i]
					continue
				var p: Vector2 = pos[i]
				var v: Vector2 = (p - prev[i]) * lerpf(0.99, 0.78, turning)
				var rr: int = i / (cols + 1)
				var cc: int = i % (cols + 1)
				var low: float = float(rr) / rows
				var gust: float = sin(time * 7.0 + cc * 0.9 + rr * 0.5) * 0.5 + sin(time * 11.3 + cc * 1.7) * 0.5
				var a := Vector2(0.0, GRAVITY)
				a.x += (wind_f * WIND + gust * 380.0 * (0.25 + absf(wind_f))) * low * low * (1.0 - 0.8 * turning)
				a.y += gust * 120.0 * low * low * absf(wind_f)
				a -= al * (0.22 * low)                       # инерция: ткань отстаёт при разгоне и торможении
				a -= vl * (1.3 * low * low)                  # сопротивление воздуха: на бегу подол отгибается назад
				prev[i] = p
				pos[i] = p + v + a * dt * dt
				pos[i] += (targets[i] - pos[i]) * minf(1.0, k[i] * dt * 120.0 * (1.0 + 3.0 * turning))
			for it in 2:
				for ri in rows + 1:
					for ci in cols + 1:
						var i: int = ri * (cols + 1) + ci
						if ci < cols:
							_link(i, i + 1, len_h)
						if ri < rows:
							_link(i, i + cols + 1, len_v)
			for i in n:
				if pinned[i] == 0:
					var d: Vector2 = pos[i] - targets[i]
					if d.length() > reach:
						pos[i] = targets[i] + d.normalized() * reach
		if clamp_node != null:                       # ткань не выходит за контур плаща по ширине
			var to_c: Transform2D = clamp_node.global_transform.affine_inverse() * xf
			var from_c: Transform2D = to_c.affine_inverse()
			for i in n:
				if pinned[i] == 0:
					var q: Vector2 = to_c * pos[i]
					q.x = clampf(q.x, clamp_rect.position.x, clamp_rect.end.x)
					pos[i] = from_c * q
		var verts := poly.polygon
		var back: Transform2D = parent.global_transform.affine_inverse() * xf
		for i in n:
			verts[i] = back * pos[i]
		poly.polygon = verts
		update_paw()

	func _link(a: int, b: int, rest_len: float) -> void:
		var d: Vector2 = pos[b] - pos[a]
		var l: float = d.length()
		if l < 0.001 or l <= rest_len * 1.04:
			return
		var diff: float = (l - rest_len * 1.04) / l
		var wa: float = 0.0 if pinned[a] == 1 else 0.5
		var wb: float = 0.0 if pinned[b] == 1 else 0.5
		if wa + wb == 0.0:
			return
		var kk: float = 1.0 / (wa + wb)
		pos[a] += d * diff * wa * kk
		pos[b] -= d * diff * wb * kk
